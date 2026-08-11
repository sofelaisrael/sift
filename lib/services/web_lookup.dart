import 'dart:convert';

import 'package:http/http.dart' as http;

class WebResult {
  final String title;
  final String url;

  const WebResult({required this.title, required this.url});
}

class WebLookupService {
  /// Cheap guard against pathological DuckDuckGo responses: anything larger
  /// than 2 MB is dropped before its body is materialized.
  static const int _ddgBodyCap = 2 * 1024 * 1024;

  /// Search for real links related to a screenshot's content. Extracted URLs
  /// from the text are returned first; otherwise the summary plus the first
  /// recognition become the web query against YouTube (when a key is given)
  /// and DuckDuckGo.
  Future<List<WebResult>> lookup({
    required String extractedText,
    required String summary,
    required List<String> recognitions,
    required String? youTubeApiKey,
  }) async {
    try {
      final fromText = _extractUrls(extractedText);
      if (fromText.isNotEmpty) return fromText;

      final query = _buildQuery(summary: summary, recognitions: recognitions);
      if (query.isEmpty) return const [];

      if (youTubeApiKey != null && youTubeApiKey.isNotEmpty) {
        final results = await _searchYouTube(query, youTubeApiKey);
        if (results.isNotEmpty) return results;
      }

      return await _searchDuckDuckGo(query);
    } catch (_) {
      return const [];
    }
  }

  List<WebResult> _extractUrls(String text) {
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
      if (results.length >= 3) break;
    }
    return results;
  }

  String _trimUrlTrailing(String candidate) {
    var url =
        candidate.replaceAll(RegExp(r'''[.,;!?)\}\]"']+$'''), '');
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

  String _buildQuery({
    required String summary,
    required List<String> recognitions,
  }) {
    final summaryWords = summary.trim().isEmpty
        ? ''
        : summary.trim().split(RegExp(r'\s+')).take(3).join(' ');
    if (recognitions.isNotEmpty) {
      final recognition = recognitions.first.trim();
      if (recognition.isEmpty) return summaryWords;
      return summaryWords.isEmpty ? recognition : '$recognition $summaryWords';
    }
    return summaryWords;
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
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
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
      results.add(WebResult(title: title.isEmpty ? url : title, url: url));
      if (results.length >= 3) break;
    }
    return results;
  }

  Future<List<WebResult>> _searchDuckDuckGo(String query) async {
    final res = await http
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
        .timeout(const Duration(seconds: 8));
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
        if (url.isEmpty || !seen.add(url)) continue;
        final title = _cleanTitle(m.group(2) ?? '');
        results.add(WebResult(title: title.isEmpty ? url : title, url: url));
        if (results.length >= 3) break;
      }
      if (results.length >= 3) break;
    }
    return results;
  }

  String _realUrl(String href) {
    final unescaped = _htmlUnescape(href);
    final uri = Uri.tryParse(unescaped);
    if (uri == null) return '';
    final uddg = uri.queryParameters['uddg'];
    if (uddg == null || uddg.isEmpty) return _stripToCore(unescaped);
    return _stripToCore(uddg);
  }

  String _stripToCore(String raw) {
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

  String _cleanTitle(String raw) {
    final withoutTags = raw.replaceAll(RegExp(r'<[^>]+>'), '');
    final unescaped = _htmlUnescape(withoutTags);
    return unescaped.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _htmlUnescape(String input) {
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
