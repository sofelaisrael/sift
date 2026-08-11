# WORKFLOWSTATE — Codebase Analysis: Sift / ScreenSort-LAM

## Request
Analyze the codebase. Be brutally honest. Find gaps and how to make it better. Use the debater subagent more than once.

## Clarified Scope
Read-only analysis + research. No code changes. Deliver: verified findings, gaps, prioritized improvement plan. Debater engaged at least twice (challenge findings, challenge roadmap).

### Scope Decisions (user-confirmed, pre-implementation)
1. **Local-only mode** = on-device OCR + local search only; no AI analysis, no lookups, no network. Refinements: AI chat disabled in this mode (local search still works); watcher keeps running but notification copy says "Indexed locally" instead of "analyzing"; boolean toggle, no per-image classifier.
2. **Delete everything** = wipes ALL app-owned data: Hive boxes (screenshots/actions/chat), SharedPreferences (settings, search history, API keys), app-copied images + thumbnails, AND resets watcher_seen. NEVER touches user's gallery originals (we only delete files we created).
3. **Provider list** = keep Google Gemini (default, multimodal) + NVIDIA (secondary multimodal; needs key field in Settings + AppConfig.apiKeyFor — currently missing) + Groq (text-only, OCR path). Drop Cerebras (preview/rate-limited/PNG-JPEG-only), OpenRouter (unverified :free variant; re-add later if confirmed), OVHcloud (keyless silent-leak provider). Rules: NO silent fallback (fail loudly); per-provider keys only (never send selected provider's key to others).

## What This Is (verified)
"**Sift**" — Flutter Android/iOS app (repo: ScreenSort-LAM, remote: github.com/sofelaisrael/sift.git, branch master). Flow: detect screenshot → upload image base64 to cloud multimodal LLM (Gemini 3.5 Flash default; fallbacks Cerebras gemma-4-31b, OpenRouter, NVIDIA; text-only Groq/OVHcloud) → parse rich JSON (type/confidence/summary/description/objects/recognitions/extracted_text/extracted_data/suggested_action) → auto-execute action (calendar/reminder/shopping list/task) → store in Hive → local keyword search + AI chat over history → web lookup (YouTube API + DuckDuckGo HTML scrape). Premium custom UI (themes, onboarding, skeleton loaders, favorites, tags, search history).

## Verified facts (checked, not assumed)
- Model IDs ARE real in 2026: `gemini-3.5-flash` (GA May 19, 2026), `gemma-4-31b` (Cerebras + OpenRouter, public preview), `llama-3.3-70b-versatile` (Groq), `meta/llama-3.2-90b-vision-instruct` (NVIDIA).
- "Auto-Execute Actions" settings toggle exists but NO pref is ever read in `ScreenshotProvider.processScreenshot` — actions ALWAYS auto-execute. No confirmation dialog anywhere.
- API keys stored plaintext in SharedPreferences (`key_$providerName`).
- Gemini API key sent in URL query param (`?key=$apiKey`) instead of `x-goog-api-key` header.
- Fallback chain in `analyzeImage` re-uploads the image to EVERY provider until one succeeds.
- `extractedData` (structured fields) is DROPPED at save time — `Screenshot` model has no field for it.
- test/widget_test.dart is a placeholder (`expect(1+1, equals(2))`).
- README + Settings UI claim: "never leaves your device", "every action requires approval", "images discarded after extraction" — all three contradicted by code.

## Initial Findings (see detailed list in final report)
A. Honesty/privacy misrepresentation (3 false claims) — critical.
B. Security engineering: plaintext keys, key-in-URL, cross-provider image fan-out, no cost controls.
C. Product contradiction: README sells "LAM/acts" as core; product plan defers LAM and says edge is conversational memory. Name/identity inconsistency.
D. Data loss: extractedData dropped; images never copied in-app; no retention; no migration story; decorative Hive adapters.
E. Engineering: zero real tests; god-class provider; no retry queue; naive search; DDG scrape fragility.
F. Platform: watcher is Android-only foreground poll; exact alarm permission unhandled; webp to Cerebras (PNG/JPEG only).

## Plan
1. [x] Explore codebase (all lib/ services, models, providers, screens, config, tests)
2. [x] Verify provider model IDs via web research
3. [x] Verify action-confirmation & key-storage claims in code
4. [ ] Debater round 1 — attack findings (in progress)
5. [ ] Debater round 2 — attack improvement roadmap
6. [ ] Final synthesis + WORKFLOWSTATE.md update

## Debate Notes
### Round 1 (debater) — verdict on findings
- A1 confirmed + understated: privacy lie lives in FOUR places incl. onboarding (onboarding_screen.dart:167,301). README:49 claims "Gemini Pro + Function Calling" — no function calling exists (prompt+JSON only).
- A2 confirmed + worse: actions fire with NO confidence threshold (0.3 hallucinated action executes). Toggle subtitle "without confirmation" implies default HAS confirmation — UI is inverted-misleading.
- A3 half-right: "discard" vacuously true (no image custody), but "ephemeral" false; stored forever.
- B3 confirmed + sharp edges: fallback fires on empty/parse-fail too; OVHcloud (requiresKey:false) ALWAYS attempted → unconfigured third party gets OCR text; selected provider's key is sent to OTHER providers on fallback (key-leak bug).
- B4: NEW — watcher timer re-entrancy: _check has no re-entrancy guard; analysis >10s overlaps next tick → duplicate notifications + parallel API calls.
- C2 fair: watcher limitation IS honestly documented (progress.md + code comment). Overpromise lives in Settings/README copy.
- D4: mechanism wrong, conclusion right — nullable fields don't crash; but Hive adapter unused (typeId versioning = 0 protection), _stringMapList silently coerces non-strings to ''.
- F2: debater claims gemma-4-31b + :free variant are fictional and Cerebras is text-only — **SUPERSEDED by live 2026 research**: gemma-4-31b is real on Cerebras (multimodal public preview, June 2026, base64 PNG/JPEG only — supports the webp-MIME concern) and google/gemma-4-31b-it is real on OpenRouter. Debater's training data predates these releases. Its ADVICE stands: verify provider IDs in CI, `:free` suffix unverified.
- **THE strategic finding (debater)**: the flagship demo is IMPOSSIBLE — onboarding shows "Google Flights round trip to Lisbon $540" recall, but extractedData is dropped at save (no field on Screenshot). Conversational-memory product does not exist in code. Promoted D to co-#1 with A.
- NEW: chat_screen.dart:150-156 — developer KNOWINGLY hides provider errors because they can embed the API key in the URI → evidence B2 (key-in-URL) is a known, unfixed bug (symptom hidden, root cause ignored).
- Priority verdict: A (privacy claims) = D (data loss/impossible promise) > B (esp. B3 fan-out) > E (targeted tests) > C (positioning, "30-min doc edit") > F (platform).
- Debater's 3 extra fixes: (1) re-encode screenshots to bounded JPEG (~1280px, q80) pre-upload; (2) two-tier gating: local ML Kit OCR first, upload only if text looks actionable; (3) schemaVersion + v0-fixture round-trip test + golden tests for _extractJsonObject (5 known failure modes).

### Round 2 (debater) — roadmap verdict
- KILL the two-tier gate (self-reexamined): saves ~$0.10/month (Gemini free tier ≈ 1,000 img req/day; 100 screenshots/mo = 0.3% of a day), breaks zero-text recall (landmark/people photos are the differentiator), and regex false-negatives silently break the flagship recall promise. Replace with a BOOLEAN: "Local-only mode" toggle + "Delete everything" wipe button — converts the core lie into a real feature (~half a day).
- Week 1 = compressed "honesty sprint" (copy + consent + delete auto-action path + single provider). Ship that as legally defensible.
- Don't build a confirmation dialog — DELETE the auto-action path entirely. Removal is hours; dialog is weeks.
- Commit to soul (a) conversational memory: code has ~90% of it; soul (b) actions is fake (add_2_calendar = system sheet, shopping/tasks = local Hive, no OAuth, no undo) and trust-negative. Cuts: auto-action execution, dead toggle, auto web-lookup, multi-provider → ONE provider (Gemini Flash free), LAM/Function Calling branding (no function calling exists).
- Biggest risk: plan = "fix everything" backlog with both souls surviving → nothing ships; no milestone where app is launchable.
- ADD: Local-only mode toggle + wipe button; Hive migration plan; real-device smoke test of watcher.
- Final 10-item plan (~40h, 3 weeks) with time-boxes + acceptance tests — see final report.
- NOTE: debater twice called gemini-3.5-flash "unverifiable/fictional" — WRONG; superseded by live research (GA May 19, 2026). Debater's training data predates it. Its advice (verify provider IDs in CI) still stands.

## Files To Change (future, not now)
- lib/services/lam_service.dart, lib/providers/screenshot_provider.dart, lib/models/screenshot.dart, lib/services/action_service.dart, lib/config.dart, README.md, lib/screens/settings_screen.dart, lib/services/web_lookup.dart, lib/screens/onboarding_screen.dart, lib/widgets/about_dialog.dart, test/

## Current Status
**IMPLEMENTATION COMPLETE (uncommitted) + VERIFIED BY PLANNER (Aug 9 2026).**

The week-1 "honesty sprint" is implemented in the working tree (13 modified files + 1 new). HEAD = origin/master = ed23213 (clean, pushed). The earlier "mystery commit 29f04c7" was a **corrupted-tool-output artifact**, NOT a real commit: the git reflog shows no HEAD move above ed23213, and the impossible paths/230-line comment walls seen in that window no longer exist. No unauthorized commit ever landed. The stale `git push origin master` leftover process was confirmed dead.

### Implemented scope (all verified by planner via full file reads)
1. **Single-provider, no fan-out**: lib/services/lam_service.dart now has exactly Gemini/NVIDIA/Groq (Cerebras/OpenRouter/OVHcloud removed). `analyzeImage` attempts only the selected provider (no cross-provider fallback); `chat()` calls only the selected provider; dead `processScreenshot(ocrText)` removed. Stale provider prefs (e.g. 'OpenRouter') fall back to `AppConfig.defaultProvider` before key resolution (prevents routing images to Gemini with a wrong key).
2. **Privacy gate + truthful copy**: new lib/widgets/privacy_gate.dart — one-time consent dialog (skipped in local-only mode) before any upload; shown by home picker, chat cloud path, and settings flows. False claims removed from onboarding (both pages), about dialog, chat hero, README-referenced Settings rows. Remaining copy states exactly: screenshots live on device; AI analysis sends images to the chosen provider; Local-only keeps everything on-device.
3. **No auto-action, no auto-lookup, consent-gated manual actions**: `processScreenshot` stores `suggestedAction` (new Screenshot field 17, adapter hand-verified) but never executes it; `runSuggestedAction`/`findOnline` require consent AND not local-only, and surface a user-visible error when blocked. Watcher (`screenshot_watcher.dart`) checks consent before processing; when blocked it shows a distinct permission notification and does NOT mark the file seen (retried after consent). Local-only mode = on-device OCR only, no network; chat returns a local search reply.
4. **Delete everything**: `deleteEverything()` wipes all Hive boxes + SharedPreferences (incl. keys/search history), never touches gallery files, and reseeds `watcher_seen` with pre-wipe paths so the watcher doesn't re-upload after restart.
5. Settings: 3 provider cards only, no autoAction toggle, local-only switch wired to provider, privacy info rows, Delete Everything tile with confirm dialog.

### Verification performed — TASK 2 RUN (Aug 10 2026)
**SDK CORRECTION**: `dart`/`flutter` ARE available at `F:\develop\flutter` (earlier "no SDK" note was wrong). Real verification executed:

- `flutter test`: **23/23 passed** (chat_single_provider, consent_findonline, consent_guard, delete_everything, extract_json x5, lam_response x3, no_fan_out x4, screenshot_json, search x3, web_lookup x2, widget smoke). Zero failures, zero live-network calls (all HTTP mocked via MockClient).
- `flutter analyze`: **0 errors**. 5 pre-existing lints unrelated to this changeset: settings_screen.dart:769/783/786 + privacy_gate.dart:14 (`use_build_context_synchronously`), screenshot_provider.dart:192 (`dead_null_aware_expression` — line is context in the diff, exists in HEAD).
- String-aware delimiter balance (raw-string-aware scanner, validated on controls): **OK on all 41 .dart files** in lib/ + test/. Earlier 291/286 flag on lam_service was a SCANNER bug (`r'\'` raw string mis-tracked as escape) — construct exists in committed code since e36fa61, app compiled, hence artifact. NOTE: the pre-commit comprehensive checker had a real bug (closes dict keyed with open chars — closures never counted); it has been replaced by the corrected scanner; all files re-verified OK.
- Greps: `extractJsonObject` = 2 refs (call site lam_service.dart:234, top-level def :483); `_extractJsonObject` = 0; `_client.post` = 4 sites (:140,:209,:383,:441); `?key=` = 0 repo-wide (Task 1 header fix holds); `r'\'` = 1 (lam_service.dart:505, valid Dart).
- Screenshot model/JSON round-trip, search incl. extractedData haystack, deleteEverything wipe, consent guards — all covered by passing tests.

### Reviewer findings (APPROVE-WITH-FIXES → fixed)
- BLOCKER fixed by planner: test/screenshot_json_test.dart:11 `'Total: $540.00'` unescaped `$` (Dart compile error, broke suite) → `'\$540.00'`. After fix: 23/23.
- MINOR: Gemini auth now header-based (`x-goog-api-key`) — deliberate security improvement riding along with the seam; call out in commit message.
- MINOR: extractJsonObject misses a valid object nested inside a balanced-but-invalid outer block (pre-existing limitation, not a regression; sibling-block recovery works).
- MINOR: no test exercises the `_retry429` retry path (a future 429 test needs fakeAsync to avoid a real 3s delay).
- NIT: Gemini fixture duplicated across chat_single_provider_test / no_fan_out_test; `Future.delayed(Duration.zero)` sync hack in delete_everything_test.

### Security reviewer findings (APPROVE)
- MINOR: debugPrint of provider error bodies + up to 400 chars raw model output (lam_service.dart:158/222/236/418/457) can leak user screenshot content to device logs in release — recommend `if (kDebugMode)` redaction (pre-existing pattern).
- MINOR: extractJsonObject is O(n²) on many-unclosed-`{` input; bounded by maxOutputTokens (4096/1024) so sub-second worst case — acceptable, note only. Regexes: linear/anchored, no ReDoS.
- MINOR: `http.Client()` created in constructor never closed; LAMService instantiated per screenshot — resource note; the new seam makes a shared/long-lived client an easy future fix.
- NIT: web_lookup_test relies on short-circuit (latent egress if it regresses); broad `catch (_)` in extractJsonObject.
- Explicitly clean: no secrets committed (config keys empty strings; tests use literal 'test'); injected client used only at 4 constant-URL call sites (no SSRF); no egress in CI; consent-gated findOnline/actions verified by tests.

### Commit Message Draft
```
refactor(lam): inject http client, harden JSON parse, add test suite

- LAMService now accepts an injectable http.Client; all four call sites
  use _client.post() so tests can swap in a MockClient
  (package:http/testing) and avoid live network calls
- Gemini analyze/chat send the API key in the x-goog-api-key header
  instead of the ?key= URL query param
- Hoist _extractJsonObject to a top-level extractJsonObject(): walks
  multiple {..} candidate blocks with string-aware brace depth and
  returns the first that decodes, so messy model output can't kill
  analysis
- Add 10 test files (22 tests + smoke test); flutter test 23/23 passed,
  flutter analyze clean apart from pre-existing lints
- Also includes screenshot processing queue + extractedData search
  index, detail/chat screen updates, and DESIGNSTATE.md
```

## Current Status
**TASK 2 COMPLETE + VERIFIED (real flutter test/analyze runs).** Working tree carries Task 1 (privacy sprint) + Task 2 (seams/parser/tests), all uncommitted. HEAD = df90eed (local) / origin ed23213. 23/23 tests pass; analyze 0 errors (5 pre-existing lints). One review blocker (unescaped `$`) found and fixed by planner; both reviews otherwise clean.

## Pending
- Commit + push (awaiting explicit user approval; commit message drafted above).
- Optional follow-ups (non-blocking, recorded): debug-log redaction for privacy; close/shared http.Client; _retry429 retry-path test (fakeAsync); extractJsonObject nested-block + size-cap guards; shared Gemini fixture helper; WebLookupService injectable-client seam for hermetic tests.

## Next Agent
On user approval: commit → push (message drafted above).

## Feature Debate: Bulk Ingest (full-build.txt, Aug 10 2026)
User asked to debate the full-build.txt vision (bulk-ingest the existing camera-roll screenshot library) with the debater before planning.

### Round 1 outcome (debater): REFRAME — premise right, ~30% of the 9-point spec survives
- Load-bearing flaw: spec assumes Sift can delete/move gallery files; codebase principle is the opposite ("never touch gallery originals") and no deletion machinery exists. Dedupe/stale-clear/batch-confirm/chat-action-layer/working-sets = ceremony around that missing capability.
- BLOCKER 1: watcher's first 10s poll would enqueue all files as "new" through the same _queueTail the ingest uses → double-analysis/double-billing. Ingest must own seen/queued state and suppress the watcher during the pass.
- BLOCKER 2: bulk upload breaks the privacy contract — the one-time per-action consent gate would authorize whole-library upload. Needs a distinct, loud "analyze my whole library" consent (count/provider/cost/local-only alternative).
- Cost: ~$0.004–0.006/image → $24–36/6,000 (not $9–12); rate is the real blocker (15 RPM → 7h+; needs resumable queue with backoff; _retry429 retries once then gives up).
- Fork reframe: local ML Kit OCR = ~80% of MVP value at 0% cost/0% upload; cloud enrich = separate consent-gated phase 2.
- Chat-as-action-layer rejected: use Photos-style grid + checkmarks + batch bar; "hide from Sift" (soft-delete of index record) as the only destructive op.
- Scale: current search() does full-haystack joins per record per keystroke — needs min-query-length + capped haystack + lazy grid.
- Cut: staleness (noisy OCR dates + destructive implication), collections-as-entities (tag-filtered grid IS the collection), gallery delete/move.
- Hive migration is a non-issue (box stores JSON maps; adapter is dead code; new fields are backward-compatible key additions).
- Recommended slice: Android-only, ~3–4 wks, no new permissions beyond photo read, zero cloud cost on default path.

### Locked decisions (user: "proceed" — defaults chosen by planner, flag if wrong)
1. Scope: Android-first, same screenshot folders the watcher scans, most-recent-first.
2. Destructive op: "hide from Sift" only; real gallery deletion deferred.
3. Platform: Android only; iOS deferred.

### Round 2 (debater): stress-test the minimal slice — SOUND-WITH-FIXES. Final plan follows.

Key round-2 findings (full detail in transcript):
- B1: ingest must NOT reuse processScreenshot (timestamp hardcoded now() → whole grid collapses to "Today"; per-item notifyListeners → 6,000 rebuilds; prefs/consent read per file). Fix: dedicated addFromBulkIngest with real capture time (file mtime / createDateTime) + throttled notify.
- B2: watcher _knownPaths seeded once at start() → after ingest, EVERY poll re-processes the library. Fix: early-return when isIngesting + per-tick merge of provider paths; optional scanNow() at ingest end + delta scan for files arriving mid-pass.
- B3: idempotency needs Map<path, Screenshot> _byPath index (O(n²) scan otherwise); pick ONE enumeration source — don't add photo_manager, extract shared FileEnumerator from the watcher's Directory scan (identical paths/keys, zero new dep).
- M1: queue/hidden state in NEW Hive boxes (ingest, hidden_paths) opened in main.dart, cleared in deleteEverything — keeps Screenshot model frozen (no schema change literally true); never write queue metadata into 'screenshots' box (fromJson would crash startup).
- M2: queue state machine: per-path {status pending→processing→done|failed|skipped|hidden, attempts, lastError, enqueuedAt, processedAt, screenshotId} + __meta {running, paused, startedAt, cursor}; persist status BEFORE OCR; processing→pending on restart; no pre-check exists() (TOCTOU — catch and classify); 429 backoff is dead weight in local-only slice (use OCR-exception retry 3× 2s/8s/32s; keep 429 hook for deferred cloud phase); shared _writeTail to serialize ingest+manual saves.
- M3: runtime media permission never requested (Android 13+ READ_MEDIA_IMAGES silently finds nothing) — request via permission_handler at pass start; surface denial state.
- M4: hidden must be enforced at all 6 sinks (search, visibleScreenshots, byType, recentScreenshots, chat sources, watcher via watcher_seen, re-ingest via queue status=hidden); wipe semantics explicit: deleteEverything clears ingest+hidden_paths and reseeds watcher_seen → post-wipe re-index resurrects hidden items (correct after full forget).
- M5: OCRService constructs 2 TextRecognizers and is never disposed — share one instance, make extractText overridable (ML Kit can't run in flutter test — the seam unit tests need).
- m1 search: min-query gate (2 chars non-CJK, 1 char CJK), precomputed normalized search blob at load (not per keystroke), cheap-field prefilter (summary/tags/lamType/fileName before ocrText), tag index Map<tag, Set<path>>, ≤6 terms, blob caps ocrText at ~2k chars, ADD fileName to haystack (currently unsearchable). No persisted term index (that's the FTS project).
- m2: watcher_seen ~350KB at 6k paths — acceptable, don't stuff every ingested path into it (per-tick merge covers B2).
- m3: _check() needs re-entrancy guard (pre-existing overlap bug; matters more now).
- m4 UX: home-screen banner (ProcessingBanner slot) + More row w/ count+ETA+pause/resume; WidgetsBindingObserver pause on background; milestone wording = count/ETA.

Cut from slice: photo_manager enumerator, 429 backoff as headline, persisted term index. Add: FileEnumerator, permission request, capture-time plumbing, throttled notify, _byPath, hidden_paths box, background pause, shared injectable OCRService, watcher merge+guard, end-of-pass delta scan.

### IMPLEMENTATION — Round A COMPLETE + VERIFIED (Aug 10 2026)
- **Working-tree discovery**: after commit 419bf73 (clean tree), a major UI/theme overhaul appeared uncommitted (~3,658+/2,955− across 20 files): "Warm Paper Recall" theme (motion_tokens.dart, SourceSerif4/JetBrainsMono fonts, chat_atoms.dart, redesigned screens). NOT created by this pipeline — presumed parallel design session following DESIGNSTATE.md. VERIFIED by planner: flutter analyze = No issues found (also cleared the 5 pre-existing lints), flutter test = 23/23 pass. Core services (lam_service, ocr_service, watcher, models) untouched; provider only +2 lines. Compatible base; implementor briefed to read redesigned files before editing (esp. main.dart, home_screen.dart, settings_screen.dart, pubspec.yaml fonts block).
- Round A scope (implementor, this pass): FileEnumerator, shared injectable OCRService, _byPath index + _writeTail, addFromBulkIngest (real capture time, throttled notify), IngestService + Hive 'ingest' box state machine + crash recovery + retry, watcher coordination (isIngesting early-return, per-tick path merge, _checking guard, scanNow), search hardening (min-query gate, precomputed blob, cheap-field prefilter, tag index, fileName in haystack, ~2k OCR cap), hidden_paths box + hide at all 6 sinks + watcher_seen on hide, deleteEverything clears new boxes, permission_handler dep. Round B (next): UI — banner progress, tag-filter grid + batch hide, settings entry.
- Acceptance criteria: (1) idempotent correctly-timestamped ingest, (2) crash recovery, (3) watcher suppression + delta, (4) hide round-trip, (5) bounded search.
- **Subagent failure note**: implementor subagent failed 3× (cancelled once, empty result twice) → per user's standing directive, planner implemented Round A directly with real verification.
- **Round A files (all written/edited by planner)**: NEW lib/services/file_enumerator.dart (ScreenshotFile + FileEnumerator, same 3 folders as watcher, paths normalized to forward slashes); NEW lib/services/ingest_service.dart (Hive 'ingest' box queue machine: per-path {status,attempts,lastError,enqueuedAt,processedAt,screenshotId} + __meta, pending→processing→done|failed|skipped|hidden, crash recovery processing→pending, dead-file→skipped, OCR retry 3× 2s/8s/32s injectable, FileSystemException→skipped, end-of-pass delta scan, onPassComplete hook, progress stream, isIngesting/paused/processedCount/remaining); lib/services/ocr_service.dart (shared lazy recognizers + extractOverride seam); lib/providers/screenshot_provider.dart (_byPath, _visible hidden filter, _searchBlobs with ~2k cap + fileName, _tagIndex, _writeSerialized, _insertSorted, addFromBulkIngest with throttled notify 25, flushBulkNotify, hide/unhideScreenshot + watcher_seen, deleteEverything clears ingest+hidden_paths with isBoxOpen guards, hardened search with min-query gate 2 non-CJK/1 CJK + ≤6 terms, containsPath, isHidden, byTag, deleteScreenshot/addTag/removeTag maintain indexes); lib/services/screenshot_watcher.dart (injectable FileEnumerator, isIngesting early-return, _checking re-entrancy guard, per-tick provider-path merge, scanNow(), ensureNotificationPermission test seam, unused dart:io import removed); lib/services/watcher_service.dart (isIngesting passthrough + scanNow); lib/main.dart (opens 'ingest' + 'hidden_paths' boxes, shared ocrService, wires ingestService.onPassComplete = watcherService.scanNow, SiftApp/MultiProvider gains ingestService). NEW tests: test/ingest_test.dart (4), test/watcher_ingest_test.dart (1), test/hide_test.dart (1), test/search_bounds_test.dart (4).
- **Round A verification (real runs)**: `flutter test` = **33/33 passed** (23 pre-existing + 10 new). `flutter analyze` = **No issues found**.
- **Failures found & fixed during verification**: (1) Windows path-separator mismatch (Directory.list → backslash vs test keys → mixed) broke ingest dedupe/crash-recovery/OCR-map lookups — FIXED in production by normalizing enumerated paths to forward slashes in FileEnumerator (also fixes fileName on Windows; Android unchanged) + tests use normalized paths; (2) watcher hardcoded Android-only FileEnumerator → invisible to tests — FIXED by injectable enumerator param; (3) hide_test didn't open 'actions'/'chat' boxes for deleteEverything — fixed in test; (4) `await watcher.stop()` on a void method + stale 'final' on constructor — fixed.
- **Non-blocking notes**: manual pick on Windows still yields non-normalized paths for fileName (Android app target unaffected); http.Client per-screenshot + unclosed (pre-existing, recorded); debug-log redaction of model output still recommended (pre-existing).

### IMPLEMENTATION — Round B (UI) COMPLETE + VERIFIED (Aug 10 2026)
- Round B built on top of the uncommitted "Warm Paper Recall" redesign using its tokens (SiftColors/SiftType/SiftSpacing/SiftRadii/SiftElevation/MotionTokens). Scope per debater m4/m1: ingest trigger + permission, live progress banner, tag-filter chips, batch hide.
- **lib/services/ingest_service.dart**: now extends ChangeNotifier — notifies on start()/pause()/resume()/per-item progress/pass-finish (the progress Stream<int> is kept); `remaining` is now an O(1) counter (`_totalTarget` synced after each enqueue) instead of a per-call box scan (a 6k-path pass would have done 6k box reads per rebuild at 6k rebuilds); new `estimatedRemaining` Duration? computed from pass start + items done.
- **lib/providers/screenshot_provider.dart**: new `tags` getter — distinct user tags in ORIGINAL casing (filter-chips display), deduped.
- **lib/widgets/ingest_banner.dart** (NEW): pulsing banner (paused = surfaceWarm1 + pause icon, running = surfaceWarm2 + PulsingMark) with "Indexing your library", "N indexed so far", ETA line ("Ns left"/"about M min left") once measurable, and a pause/resume IconButton — driven by `context.watch<IngestService>`.
- **lib/screens/home_screen.dart**: (1) `IngestBanner` sliver while `ingest.isIngesting` + one "Library indexed — N screenshots remembered" SnackBar per pass on the running→done edge (plain-field guard, no setState-in-build); (2) tag-filter chip row (All + tags) under the brand row; active tag feeds `_buildGroupSlivers` via `provider.byTag(tag)`; `_TagFilterEmptyState` (label-off icon + "Show all") when a filter has no hits; (3) batch select: long-press enters selection (medium haptic), tap toggles, selected cards get accent border + bottom-right check badge + dim when unselected, pin hidden during selection; floating `_buildBatchBar` (paper r16, hairline, shadow) with "N selected" / Clear / Hide; `_batchHide` calls `hideScreenshot` per id then SnackBar.
- **lib/screens/settings_screen.dart**: "Index my library" row in the Library section — confirm dialog (states: on-device OCR, nothing uploaded, no photo modified/deleted), then `_ensurePhotoAccess()` (permission_handler `Permission.photos` on Android — manifest already declares READ_MEDIA_IMAGES + READ_EXTERNAL_STORAGE maxSdk 32, so NO manifest change), then fire-and-forget `ingest.start()` (a full pass can take a while; progress via notifier) + "Indexing your library…" SnackBar; while running the row shows a live subtitle (count) and an inline pause/resume IconButton; denial → SnackBar "Sift needs photo access...".
- **lib/main.dart**: ingestService exposed as `ChangeNotifierProvider.value` (was plain Provider).
- **lib/screens/app_shell.dart**: `_AppShellState` now a `WidgetsBindingObserver` — on `AppLifecycleState.paused` pauses the ingest pass if running (persisted via __meta).
- **Verification (real runs)**: `flutter analyze` = No issues found; `flutter test` = 33/33 passed (Round A behavior unchanged — ChangeNotifier/remaining-counter refactor is add-only). One syntax slip fixed during verify (`,` → `;` on a local declaration in settings_screen).
- **Notable facts**: widget_test.dart is still the 1+1 placeholder (no SiftApp pumping, so the new provider wiring can't break it); no new pub dependency added (permission_handler was already in pubspec).

### RELEASE HARDENING + NEW LAUNCHER ICON (Aug 11 2026) — pushed for Codemagic build
- User reported on the released APK: (1) antivirus "virus detected" notification at install, (2) after bypassing, blank screen until the app stopped.
- **Root cause 1 — startup crash (blank screen)**: the redesigned app loads OFL license texts via `rootBundle.loadString` in `main()` before `runApp`, but pubspec.yaml declared NO `assets:` section → `FlutterError: Unable to load asset` on every build (debug AND release). The redesign/ingest work was only ever verified via `flutter test`/`flutter analyze`, never launched on a device. FIXED: `assets:` now bundles `assets/fonts/OFL-SourceSerif4.txt` + `OFL-JetBrainsMono.txt`; `_registerFontLicenses()` is now non-fatal (separate try/catch per load) so a missing license can never blank-screen startup again.
- **Root cause 2 — antivirus flag**: release APK was signed with the DEBUG key (build.gradle.kts carried the stock TODO + `signingConfigs.getByName("debug")`) — the classic heuristic for sideloaded-debug-signed apps; compounded by `READ_CALENDAR`/`WRITE_CALENDAR` (add_2_calendar writes via an ACTION_INSERT intent, needs no calendar permission), `RECEIVE_BOOT_COMPLETED` (no boot receiver in code), and `SCHEDULE_EXACT_ALARM` (reminders used `AndroidScheduleMode.exactAllowWhileIdle`, a textbook adware heuristic). FIXED: those 4 permissions removed from the manifest; reminders now use `AndroidScheduleMode.inexactAllowWhileIdle` (no permission needed; note: unlike exact mode, reminders won't survive a device reboot, and alarm apps lose Android 12+ exact timing — acceptable for a sideloaded fix release).
- **Release signing**: `build.gradle.kts` now consumes `android/key.properties` when present (canonical template) for a real release keystore, else falls back to the debug key with an explicit WARNING. No keystore can be generated on this machine (no JDK/keytool found). Intended path: Codemagic code signing → "Generate keystore" (writes android/key.properties at build time). `android/key.properties` + `*.jks` are gitignored.
- **New launcher icon** ("try another one"): replaced the 6-petal mark with a whisper-paper mark on the terracotta `#D97757` bg: NEW `drawable/ic_launcher_foreground.xml` (vector, adaptive safe zone; old `drawable-nodpi/ic_launcher_foreground.png` deleted — adaptive icon referenced @drawable/ic_launcher_foreground, which now resolves to the XML), legacy `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` regenerated programmatically (GDI+), `ic_stat_sift.xml` (notification) = white silhouette. First pass = hourglass; then reshaped on user request (Aug 11, v1.0.2+2): two triangles whose tips touch at the centre, skewed into an "S" — the down-facing (top) triangle is longer on its left, the up-facing (bottom) triangle longer on its right (TL high, BR low, solid pinch at centre). Legacy PNGs over-drawn with a 1.6px paper stroke to fill GDI+ hairline nicks at the apexes; verified by pixel sampling (bodies/pinch paper, background terracotta, corners transparent) since the model can't view images.
- **Version**: bumped 1.0.1+2 → 1.0.2+1.
- **Verified (real runs)**: `flutter analyze` = No issues found (134.5s); `flutter test` = 33/33 passed. Per user request, NO local APK build (Codemagic builds). Gradle kts edited to the canonical template pattern; not compile-checked locally (would require a build).
- **Repo state discovered this session**: parallel session completed + pushed everything (HEAD now 552bf98 — docs; history includes cb0162f feat(ingest) [our Round A+B], 46e9d28 + c115fe1 [icon], dec817c [GH Releases CI], e2d6fce [Warm Paper Recall redesign], 419bf73 [LAM refactor]); tags v1.0.0 + v1.0.1 exist. The corrupt git index (bad signature 0x00000000) from the parallel session was repaired via `Remove-Item .git/index` + `git read-tree HEAD` (working tree untouched, all changes re-materialized).
