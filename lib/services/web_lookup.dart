import 'dart:convert';

import 'package:http/http.dart' as http;

class WebResult {
  final String title;
  final String url;
  final String thumbnail;

  const WebResult({
    required this.title,
    required this.url,
    this.thumbnail = '',
  });
}

/// Search for real links related to a screenshot's content.
///
/// Order: URLs embedded in the text (free, local) -> YouTube Data API (only
/// when a key is set) -> a keyless `site:youtube.com` DuckDuckGo search for
/// video-like content -> a generic DuckDuckGo search. YouTube links are then
/// enriched with a real title + thumbnail via the keyless oEmbed endpoint
/// (or derived from the video id, which needs no call at all). Everything
/// fails silently and returns an empty list — a lookup must never break a
/// chat reply.
class WebLookupService {
  /// Cheap guard against pathological DuckDuckGo responses: anything larger
  /// than 2 MB is dropped before its body is materialized.
  static const int _ddgBodyCap = 2 * 1024 * 1024;

  static const int _maxLinks = 3;
  static const Duration _timeout = Duration(seconds: 8);
  static const Duration _oembedTimeout = Duration(seconds: 4);

  final http.Client _client;

  WebLookupService({http.Client? client}) : _client = client ?? http.Client();

  /// Common words that add no signal to a search query.
  static const Set<String> _stopwords = {
    'a', 'an', 'the', 'and', 'or', 'but', 'if', 'of', 'to', 'for', 'with',
    'on', 'in', 'at', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been',
    'this', 'that', 'these', 'those', 'my', 'your', 'our', 'their', 'his',
    'her', 'its', 'it', 'we', 'you', 'i', 'me', 'us', 'them', 'as', 'so',
    'than', 'then', 'just', 'not', 'no', 'about', 'into', 'over', 'under',
    'up', 'down', 'out', 'off', 's', 't', 'll', 're', 've', 'd',
  };

  /// All http(s) URLs found in [text], de-duplicated, capped at three.
  /// Pure string work — never touches the network.
  static List<WebResult> extractUrlsFromText(String text) {
    final matches =
        RegExp(r'''https?://[^\s"')>]+''').allMatches(text);
    final seen = <String>{};
    final results = <WebResult>[];
    for (final m in matches) {
      final candidate = _trimUrlTrailing(m.group(0) ?? '');
      final uri = Uri.tryParse(candidate);
      if (uri == null) continue;
      if (uri.scheme != 'http' && uri.scheme != 'https') continue;
      if (uri.host.isEmpty || !uri.host.contains('.')) continue;
      final url = _stripToCore(candidate);
      if (url.isEmpty || !seen.add(url)) continue;
      results.add(WebResult(title: url, url: url));
      if (results.length >= _maxLinks) break;
    }
    return results;
  }

  /// Search for real links related to a screenshot's content. Extracted URLs
  /// from the text are returned first; otherwise the OCR text's first line
  /// (usually the title) plus the summary, the first recognition and the
  /// on-device visual labels ([objects]) become the web query against YouTube
  /// (when a key is given) and DuckDuckGo.
  Future<List<WebResult>> lookup({
    required String extractedText,
    required String summary,
    required List<String> recognitions,
    required List<String> objects,
    required String? youTubeApiKey,
  }) async {
    try {
      final fromText = extractUrlsFromText(extractedText);
      if (fromText.isNotEmpty) {
        return _enrichYouTubeLinks(fromText);
      }

      final query = _buildQuery(
        extractedText: extractedText,
        summary: summary,
        recognitions: recognitions,
        objects: objects,
      );
      if (query.isEmpty) return const [];

      if (youTubeApiKey != null && youTubeApiKey.isNotEmpty) {
        final results = await _searchYouTube(query, youTubeApiKey);
        if (results.isNotEmpty) return results;
      }

      // Keyless YouTube path: when the content is video-like (a video
      // screenshot rarely contains its own URL), DuckDuckGo restricted to
      // site:youtube.com finds the actual watch page with no API key.
      if (_isVideoContent(extractedText, summary, recognitions)) {
        final videoResults =
            await _searchDuckDuckGo('site:youtube.com $query', youtubeOnly: true);
        if (videoResults.isNotEmpty) {
          return _enrichYouTubeLinks(videoResults);
        }
      }

      final generic = await _searchDuckDuckGo(query);
      return _enrichYouTubeLinks(generic);
    } catch (_) {
      return const [];
    }
  }

  /// Build the web query from what the screenshot actually shows. The first
  /// non-empty line of the visible text (usually the video title, headline or
  /// product name) leads; summary words and the first recognition back it up.
  /// A text-less screenshot has no title line, so the on-device visual labels
  /// ("dog", "mountain", ...) become the query instead. Stopwords are dropped
  /// and the whole query is capped at ~8 terms.
  String _buildQuery({
    required String extractedText,
    required String summary,
    required List<String> recognitions,
    required List<String> objects,
  }) {
    final terms = <String>[];

    final firstLine = extractedText
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
        .trim();
    if (firstLine.isNotEmpty) {
      _addTerms(terms, _takeWords(firstLine, 6));
    } else {
      _addTerms(terms, objects.take(4).toList());
    }

    _addTerms(terms, _takeWords(summary, 3));

    if (recognitions.isNotEmpty) {
      final recognition = recognitions.first.trim();
      if (recognition.isNotEmpty) {
        _addTerms(terms, _takeWords(recognition, 2));
      }
    }

    return terms.take(8).join(' ');
  }

  /// Adds words, skipping stopwords and duplicates.
  static void _addTerms(List<String> terms, List<String> words) {
    for (final w in words) {
      final lower = w.toLowerCase();
      if (_stopwords.contains(lower)) continue;
      if (terms.contains(lower)) continue;
      terms.add(w);
    }
  }

  static List<String> _takeWords(String text, int n) => text
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .take(n)
      .toList();

  /// True when the screenshot content looks like a video page — the signal
  /// that a `site:youtube.com` search is the right keyless move.
  static bool _isVideoContent(
    String extractedText,
    String summary,
    List<String> recognitions,
  ) {
    final hay = '${extractedText.toLowerCase()} '
        '${summary.toLowerCase()} '
        '${recognitions.join(' ').toLowerCase()}';
    return hay.contains('youtube') ||
        hay.contains('video') ||
        hay.contains('tiktok') ||
        hay.contains('shorts');
  }

  /// Replaces bare YouTube URLs with a real title (via the keyless oEmbed
  /// endpoint) and stamps a thumbnail. Thumbnails for known video ids come
  /// from i.ytimg.com directly — no call needed. Any failure keeps the link
  /// as-is; enrichment must never throw.
  Future<List<WebResult>> _enrichYouTubeLinks(List<WebResult> links) async {
    return Future.wait(links.map(_enrichYouTube));
  }

  Future<WebResult> _enrichYouTube(WebResult link) async {
    final videoId = _youtubeVideoId(link.url);
    if (videoId == null) return link;
    final derivedThumb = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

    // A real title already exists (search results, DDG) — no oEmbed call.
    if (link.title.isNotEmpty && link.title != link.url) {
      return WebResult(
        title: link.title,
        url: link.url,
        thumbnail: derivedThumb,
      );
    }

    try {
      final res = await _client.get(
        Uri.parse(
          'https://www.youtube.com/oembed'
          '?url=${Uri.encodeComponent(link.url)}&format=json',
        ),
      ).timeout(_oembedTimeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is Map) {
          final title = body['title'] as String?;
          final oembedThumb = body['thumbnail_url'] as String?;
          return WebResult(
            title: (title == null || title.isEmpty) ? link.url : title,
            url: link.url,
            thumbnail: (oembedThumb == null || oembedThumb.isEmpty)
                ? derivedThumb
                : oembedThumb,
          );
        }
      }
    } catch (_) {
      // Enrichment failure keeps the original link.
    }
    return WebResult(title: link.url, url: link.url, thumbnail: derivedThumb);
  }

  /// The video id of a watchable YouTube URL, or null for non-YouTube or
  /// non-video pages (channels, /results, embeds).
  String? _youtubeVideoId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host != 'youtube.com' &&
        host != 'www.youtube.com' &&
        host != 'm.youtube.com' &&
        host != 'youtu.be') {
      return null;
    }
    if (host == 'youtu.be') {
      final segments = uri.pathSegments;
      return segments.isEmpty ? null : segments.first;
    }
    final v = uri.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[0] == 'shorts') return segments[1];
    return null;
  }

  /// True only for real watch pages (`/watch?v=` or `/shorts/`), so a
  /// site:youtube.com search never returns channel or search-result pages.
  static bool _isWatchableYouTube(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host != 'youtube.com' &&
        host != 'www.youtube.com' &&
        host != 'm.youtube.com') {
      return false;
    }
    final path = uri.path;
    if (path.startsWith('/watch') && uri.queryParameters.containsKey('v')) {
      return true;
    }
    return path.startsWith('/shorts/');
  }

  Future<List<WebResult>> _searchYouTube(
    String query,
    String youTubeApiKey,
  ) async {
    final uri = Uri.parse('https://www.googleapis.com/youtube/v3/search').replace(
      queryParameters: {
        'part': 'snippet',
        'type': 'video',
        'maxResults': '3',
        'q': query,
        'key': youTubeApiKey,
      },
    );
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) return const [];

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final items = decoded['items'];
    if (items is! List) return const [];

    final results = <WebResult>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id'];
      final snippet = item['snippet'];
      if (id is! Map<String, dynamic>) continue;
      if (snippet is! Map<String, dynamic>) continue;
      final videoId = id['videoId'] as String?;
      if (videoId == null || videoId.isEmpty) continue;
      final title = snippet['title'] as String? ?? '';
      final url = 'https://www.youtube.com/watch?v=$videoId';
      results.add(WebResult(
        title: title.isEmpty ? url : title,
        url: url,
        thumbnail: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      ));
      if (results.length >= _maxLinks) break;
    }
    return results;
  }

  Future<List<WebResult>> _searchDuckDuckGo(
    String query, {
    bool youtubeOnly = false,
  }) async {
    final res = await _client
        .post(
          Uri.parse('https://html.duckduckgo.com/html/'),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
            'Referer': 'https://html.duckduckgo.com/',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Site': 'same-origin',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'text/html',
          },
          body: {'q': query, 'kl': 'us-en'},
        )
        .timeout(_timeout);
    if (res.statusCode != 200) return const [];
    if (res.contentLength != null && res.contentLength! > _ddgBodyCap) {
      return const [];
    }

    final body = res.body.toLowerCase();
    if (body.contains('anomaly') ||
        body.contains('captcha') ||
        body.contains('challenge')) {
      return const [];
    }

    final linkRegex = RegExp(
      r'<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );
    final linkRegexAlt = RegExp(
      r'<a[^>]*href="([^"]+)"[^>]*class="[^"]*result__a[^"]*"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );
    final seen = <String>{};
    final results = <WebResult>[];
    for (final regex in [linkRegex, linkRegexAlt]) {
      for (final m in regex.allMatches(res.body)) {
        final url = _realUrl(m.group(1) ?? '');
        if (url.isEmpty) continue;
        if (youtubeOnly && !_isWatchableYouTube(url)) continue;
        if (!seen.add(url)) continue;
        final title = _cleanTitle(m.group(2) ?? '');
        results.add(WebResult(title: title.isEmpty ? url : title, url: url));
        if (results.length >= _maxLinks) break;
      }
      if (results.length >= _maxLinks) break;
    }
    return results;
  }

  static String _realUrl(String href) {
    final unescaped = _htmlUnescape(href);
    final uri = Uri.tryParse(unescaped);
    if (uri == null) return '';
    final uddg = uri.queryParameters['uddg'];
    if (uddg == null || uddg.isEmpty) return _stripToCore(unescaped);
    return _stripToCore(uddg);
  }

  static String _trimUrlTrailing(String candidate) {
    var url = candidate;
    // Strip trailing punctuation/braces/quotes that OCR or prose may glue
    // onto a URL (mirrors the old character-class regex, without regex
    // escaping hazards).
    while (url.isNotEmpty && '.,;!?)]}"\'\\'.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    final markdown = url.lastIndexOf('](');
    if (markdown >= 0) {
      url = url.substring(0, markdown);
    } else if (url.endsWith(']')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('(') &&
        '('.allMatches(url).length > ')'.allMatches(url).length) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static String _stripToCore(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return '';
    if (uri.scheme != 'http' && uri.scheme != 'https') return '';
    if (uri.host.isEmpty) return '';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }

  static String _cleanTitle(String raw) {
    final withoutTags = raw.replaceAll(RegExp(r'<[^>]+>'), '');
    final unescaped = _htmlUnescape(withoutTags);
    return unescaped.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _htmlUnescape(String input) {
    const entities = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&#x27;': "'",
      '&nbsp;': ' ',
      '&rsquo;': '\u2019',
      '&hellip;': '\u2026',
    };
    var output = input;
    for (var pass = 0; pass < 2; pass++) {
      for (final entry in entities.entries) {
        output = output.replaceAll(entry.key, entry.value);
      }
    }
    return output;
  }
}
