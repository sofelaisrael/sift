# Chat Link-Finding — Plan & Third-Party Research

**Date:** Aug 14, 2026
**Status:** IMPLEMENTED + VERIFIED (Aug 14) — analyze clean, 61/61 tests (50 existing + 11 new)

---

## Goal

When the user asks about a screenshot in chat, Sift should actually hand back the
link — e.g. a YouTube video whose thumbnail/title was captured in a screenshot.
"If one of them contains a screenshot of a YouTube video I want to watch, I want
to actually get that link." Search online using the keywords found **in** the
images (their OCR text + on-device labels).

**User decisions (locked Aug 14):**
1. **All matched screenshots** contribute links (not just the top match).
2. **Keyless YouTube fallback** — search `site:youtube.com` via DuckDuckGo when
   no YouTube API key is set.
3. **Thumbnails** in the chat link strip for video links (via YouTube oEmbed).

---

## Current flow & verified gaps

```
ChatScreen._runQuery ──► provider.search(text) ──► ranked results
        └──► ChatEngine.reply(results) ──► LAMService.chat()  (parallel)
                              └──► _maybeLookupLinks(results.FIRST)  ⚠ only #1
                                        └──► WebLookupService.lookup()
                                              ├─ 1. extract URLs from OCR text
                                              ├─ 2. YouTube Data API (needs key)
                                              └─ 3. DuckDuckGo HTML scrape
```

Gaps (verified in `lib/services/web_lookup.dart`, `lib/services/chat_engine.dart`):

1. **The video title is ignored.** `_buildQuery()` uses only the first 3 words of
   the summary + the first recognition. A video screenshot's OCR text (which
   contains the actual title — the strongest search key) is never used.
2. **Links come only from `results.first`.** A video matched as the 2nd–5th
   result never contributes a link, even though its URL may sit in its OCR text
   (a free, local read).
3. **YouTube search needs an API key.** Without `key_youtube` set, YouTube
   search is skipped entirely and the generic DuckDuckGo scrape usually misses
   the exact video.
4. **Extracted URLs are bare.** `title == url`. No real title, no thumbnail.
5. **`WebLookupService` has no injectable `http.Client`** — the one service in
   the app that can't be tested hermetically (already flagged in
   WORKFLOWSTATE.md as a pending seam).

---

## Implementation plan

### 1. `lib/services/web_lookup.dart`

- **Inject `http.Client`** (`WebLookupService({http.Client? client})`), mirroring
  `LAMService`. All `http.get/post` go through `_client`. No behavior change,
  unlocks hermetic tests.
- **Smarter query** (`_buildQuery`): primary terms = first non-empty line of the
  OCR text (usually the title), capped ~6 words; secondary = summary words +
  first recognition; total cap ~8 words.
- **Keyless YouTube-first fallback** in `lookup()` order:
  1. URLs found in the text (existing, network-free).
  2. YouTube Data API when a key is present (existing).
  3. **NEW** when no key AND content is video-ish (case-insensitive
     `youtube|video|tiktok|shorts` in text/summary/recognitions): DuckDuckGo
     query `site:youtube.com <keywords>`, keep only real video URLs
     (`/watch?v=` and `/shorts/`, drop `/results` + channel pages).
  4. Generic DuckDuckGo (existing).
- **oEmbed enrichment** (keyless, first-party): for YouTube links found in text
  or via DDG, `GET https://www.youtube.com/oembed?url=<url>&format=json`
  (4s timeout) → real `title` + `thumbnail_url`. For Data-API results the
  thumbnail is derived from the video ID with zero extra calls:
  `https://i.ytimg.com/vi/<id>/hqdefault.jpg`. Failures degrade silently
  (keep bare URL / no thumb), never throw.
- **`WebResult` gains `thumbnail`** (default `''`).

### 2. `lib/services/chat_engine.dart`

- **Phase A — all results, no network:** iterate the full result list in rank
  order, `extractUrlsFromText(s.ocrText)` per screenshot (new public static on
  `WebLookupService`), dedupe by URL, stop at 3.
- **Phase B — bounded to one search call:** only if Phase A < 3 links, run
  `lookup()` once on the first result with searchable content
  (text/summary/recognitions non-empty); merge + dedupe + cap 3.
- **Local-only mode:** return Phase-A links too — they're already on-device
  text, so no network is involved and the no-network promise holds.
- Keep the existing `Future.wait` parallel structure (LLM answer ‖ link hunt).

### 3. `lib/widgets/chat_atoms.dart` — `RelatedLinksStrip`

- Render a small 16:9 thumbnail (`Image.network` + `errorBuilder` fallback to
  the current icon row) + real title when `link['thumb']` is present.
- `ChatMessage.relatedLinks` is already `List<Map<String, String>>` — `'thumb'`
  is just another key, so **no model/storage change** (round-trip covered by
  `chat_message_roundtrip_test`).

### 4. Tests

- `web_lookup_test` (now with MockClient): query built from OCR title line;
  keyless `site:youtube.com` path keeps only watch/shorts URLs; oEmbed
  enrichment swaps title + adds thumb; URL extraction stays network-free.
- `chat_engine_test`: links from 2nd result when the top has none; dedupe +
  cap across results; local-only returns embedded links with no network;
  exactly one lookup call per reply (MockClient call count).

### 5. `lib/screens/chat_screen.dart`

- No logic change — the engine handles everything. (Only the
  `lookupOverride` seam already exists.)

---

## Third-party research (verified Aug 14, 2026)

### Verdict up front

**No third party is required for the core feature.** Keyless YouTube oEmbed +
the free YouTube Data API (only if the user adds a key) + `site:youtube.com`
via DuckDuckGo covers the "get me the video link" case end-to-end. Everything
below is optional and mostly paid — worth knowing about, not worth wiring in
now.

### YouTube video search & metadata

| Option | Key needed | Free tier | Verdict |
|--------|-----------|-----------|---------|
| **YouTube oEmbed** (`youtube.com/oembed?url=…`) | No | Unlimited | ✅ **Use.** First-party, keyless, returns real title + thumbnail. |
| **YouTube Data API v3** (`search.list`) | Yes | 10,000 quota units/day; search = 100 units → **~100 searches/day** | ✅ **Use when key set.** Free, generous for a personal app. |
| Invidious / Piped public instances | No | Free | ❌ **Skip.** YouTube actively blocks instances; public uptime ~50% (2024–2026 reports). Not a foundation. |

### General web search (replacing the DuckDuckGo HTML scrape)

| Option | Free tier | Verdict |
|--------|-----------|---------|
| **DuckDuckGo HTML scrape** (current) | Unlimited | ✅ Keep as keyless default. Free but fragile (HTML parsing, captcha guards). |
| **Tavily** | 1,000 credits/month (recurring) | ◐ Optional upgrade — clean JSON, built for AI/RAG. Only if DDG friction becomes real. |
| **Serper.dev** | 2,500 queries one-time trial (not recurring) | ❌ Skip — trial burns out; no recurring free tier. |
| **Brave Search API** | None — free plan removed late 2025; $5/mo credit ≈ 1k queries | ❌ Skip for a free app. |
| **Google Custom Search JSON API** | 100 queries/day | ❌ **Dead** — closed to new customers (Feb 2026). |

### "Google Lens" — reverse image search

Lens itself has **no public API** (Google Cloud Vision is the paid equivalent).
Third-party wrappers exist and would be the only way to get real Lens behavior:

- **SerpAPI** (Google Lens endpoint, image upload) — paid, from ~$25/mo.
- **DataForSEO** / **Scrapingdog** / **Apify** Google Lens actors — paid.

**Recommendation: do not pursue now.** (a) It uploads the user's *image* to a
third party — a materially bigger privacy step than sending keywords, needing
its own consent gate. (b) It solves the wrong problem: the user wants the video
*they already found*; the video title is in the OCR text, so keyword search
finds it without image upload. Revisit only if "identify what this image is"
becomes a product goal.

### Privacy posture

Sending **keywords** (OCR-derived) to YouTube/DDG is the same posture as
today's chat web lookup, already covered by the existing privacy consent gate.
Only reverse-image-search (image upload) would change that posture — another
reason it's deferred.

---

## Out of scope / deferred

- Real Google Lens / reverse image search (above).
- Search-API replacement for DDG (revisit if scraping breaks).
- Per-reply link caching (would need a cache key + TTL; revisit if latency
  complaints appear).
- No new pub dependencies — oEmbed, DDG, YouTube all use the existing `http`.

## Acceptance criteria

1. Asking about a video screenshot returns a real YouTube link with title +
   thumbnail, with **no API key configured**.
2. Links can come from any matched screenshot, not just the top one.
3. Exactly one online search call per reply (plus bounded oEmbed enrichment).
4. Local-only mode returns embedded links with zero network calls.
5. `flutter analyze` clean; full suite green (50 existing + new tests).

## Follow-up: text-less screenshots (implemented)

A screenshot with no OCR text, no summary and no recognitions — a photo, meme
or product image — previously returned **no links at all**: `_lookupLinks`
skipped it and `_buildQuery` never used the on-device visual labels. Now the
ML Kit labels in `objects` ("dog", "mountain", ...) become the search query
when there is no title line, and a screenshot with only labels is no longer
skipped. This is keyword search from labels — still not reverse-image search
(deferred above).
