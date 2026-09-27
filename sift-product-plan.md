# SIFT — Product Plan

**Date:** Sep 27, 2026
**Status:** ACTIVE — Phase 0 (measure) not started. Every retrieval claim below
is either read from the code or cited; nothing here is a target.

---

## Vision

A searchable, conversational memory of the user's screenshots. The vision holds.
What changed is the route to it: the app stopped analysing images with a hosted
model, so the understanding layer has to be built on-device or not at all. This
plan is about the part that is currently missing and measurable — retrieval
quality over the screenshots SIFT already holds.

---

## What changed and why

The previous version of this plan was written against an architecture that no
longer exists. Factual changes:

1. **Hosted image analysis is gone.** `lib/services/lam_service.dart` now makes
   one kind of call: `chat()`, a text-only request at
   `lam_service.dart:99` (`:generateContent` on a text prompt). It does not read
   image bytes. Analysis is ML Kit OCR plus ML Kit image labelling, wired in
   `main.dart:62-67`.
2. **The old "Immediate Next Step" is not executable.** It said: *"Improve the
   Gemini prompt: shift from 'extract text' to 'describe what you see'."* There
   is no image prompt left to improve.
3. **`LAMResponse` (`lam_service.dart:270`) is now dead for new records.** It
   still parses `description`, `objects`, `recognitions`, `extracted_data` and
   `search_keywords` out of JSON, but nothing in `lib/` builds a `Screenshot`
   from it. Those `Screenshot` fields are only populated on records written by
   the retired cloud path.
4. **The claimed differentiator did not survive research.** The old plan's edge
   was "the conversational interface", on the reasoning that competitors
   "focus on search/organization". Competitors do not. See §5.
5. **Several old Phase 2/3 items already shipped and should not be re-listed:**
   favorites (`toggleFavorite`), custom tags (`addTag`/`removeTag`), link
   extraction (`web_lookup.dart`), search history (`chat_screen.dart:50`,
   `160-189`, persisted in the `chat_history` preference), light/dark theme,
   opening a link externally (`url_launcher`). **Not built:** collections or
   boards, screenshot-of-the-day, timeline, export-insights, and OS share of a
   screenshot (there is no `Share.share`; the app only launches URLs).

The reason for the rewrite is not that the plan was ambitious. It is that it
described an architecture the code no longer had, and would have sent the next
quarter of work in the wrong direction.

---

## Current state (verified against the code)

| Area | Fact | Where |
|---|---|---|
| Capture | Screenshot folder enumeration + watcher, plus a bulk "index my library" pass | `screenshot_watcher.dart`, `file_enumerator.dart`, `ingest_service.dart` |
| Ingest queue | Hive-backed per-path state machine, pause/resume/stop, crash recovery (entries stuck in `processing` re-queue on start) | `ingest_service.dart:246-268` |
| Analysis | On-device only: ML Kit text recognition + ML Kit image labeling. No image bytes leave the device through app code | `screenshot_analyzer.dart:27-52`, `main.dart:62-67` |
| Labels | Only computed when OCR text is ≤ 200 chars; confidence ≥ 0.5; max 4 labels; deduped, then capped at 12 on store | `screenshot_analyzer.dart:32-38`, `image_labeler.dart:14-15`, `screenshot_provider.dart:640-652` |
| Search | Weighted inverted index, word → {id: score}, rebuilt at load and updated incrementally. Display-only placeholders and the constant `lamType` are excluded from the index | `screenshot_provider.dart:135-163`, `440-479`, `494-535` |
| Query handling | Lowercased, split on non-word/CJK, first 6 terms only, min 2 chars (1 for CJK), exact token match — no stemming, no prefix, no fuzzy, no phrases. The no-prefix half is contested; see §Open issues in search | `screenshot_provider.dart:432-438`, `1089-1102` |
| Chat | Two paths. Cloud: hosted LLM, consent-gated, user's own key. Local-only: zero network, plain local reply as the fallback on every failure mode | `chat_engine.dart:55-110`, `188-209` |
| On-device model | Qwen3-0.6B `.litertlm` bundle via Google's LiteRT-LM runtime (`flutter_gemma` 1.9.0 + `flutter_gemma_litertlm` 1.8.0). 614,236,160 bytes, pinned. Fetched once from a public Hugging Face URL, never bundled, no token, no CI credential. Used only by the local-only chat path | `local_model_spec.dart`, `litert_local_chat_model.dart` |
| Grounding | The on-device model is given a system instruction to answer only from the supplied screenshot context and to say so when the context does not contain the answer | `litert_local_chat_model.dart:195-203` |
| Deletion | "Delete everything" cancels ingest, removes the model file **before** clearing preferences, removes the private import folder before touching any box, and reports failure rather than success when anything survives | `settings_screen.dart:1042-1085`, `screenshot_provider.dart:903-1040` |

Two precision points that the marketing version of "on-device" usually drops:

- **Local-only chat answers make no network call, but the model download does.**
  The download is an explicit Settings action
  (`local_model_service.dart:83`), independent of the local-only flag, and it
  reaches `huggingface.co`. Once installed, `ensureLoaded()` never downloads
  (`litert_local_chat_model.dart:405-458`).
- **ML Kit may fetch the small image-labelling model on first use.** That is the
  one fetch made on the user's behalf, and it is Play services, not SIFT.

---

## The actual gap: the ranking weights do not match the data

This is the measurable defect, and it is the core of the plan. For any
screenshot written by the local analyzer, `_indexScreenshot`
(`screenshot_provider.dart:494-535`) assigns these weights:

| Field | Weight | What the local path actually puts there |
|---|---|---|
| `summary` | 5 | First 80 chars of the OCR text, or the literal string `"No text found"` when there is none (`:346-352`, `:601-605`). The placeholder is stored and displayed; it is **not indexed** (see below) |
| `description` | 4 | `null`. Always. (`:353`, `:606`) |
| `searchKeywords` | 4 | `[]`. Always. Not passed at either local write site; the field defaults to `const []` (`screenshot.dart:89`) |
| `tags` | 3 | Empty until the user adds a tag (`:362`, `:615`) |
| `objects` | 2 | ML Kit labels — **already indexed, real signal** (`:354`, `:607`, deduped and capped at 12 by `:640-652`) |
| `recognitions` | 2 | `[]`. Always. (`:355`, `:608`) |
| `lamType` | — | **Not indexed.** Stored as the constant `"document"` on every record (`:345`, `:600`), so it can never discriminate. The field, the Hive adapter, `TypeBadge` and the detail view's `typeLabel` are untouched |
| `ocrText` | 1 | First 2,000 chars (`_ocrBlobCap`, `:53`; applied at `:525-529`) |
| `fileName` | 1 | `path.split('/').last`, extension included (`:341`, `:596`) |
| `extractedData` | 1 | `null`. Always. Not passed at either local write site |

**The indexed weight budget is 23 units, down from 25.** `lamType`'s 2 units were
removed from the index. It was the same constant on every record, so it could
never break a tie between two results — but it did give the bare query
"document" every screenshot in the library at 2 points, and after the removal
that query returns nothing at all. Of the 23, **11 can never fire** for a
locally analysed screenshot: `description` 4 + `searchKeywords` 4 +
`recognitions` 2 + `extractedData` 1. **A further 5 are a re-weighted copy** of
the single unit on `ocrText`, because `summary` is the first 80 characters of the
same text scored at 5 instead of 1. So **16 of 23 weight units carry no
independent signal**, leaving **7**: `tags` 3, `objects` 2, `ocrText` 1,
`fileName` 1. The OCR-and-visual part of that is 3 units — `ocrText` 1 and
`objects` 2 — against 5 units of OCR text that is already counted, and given the
per-occurrence rule below.

**A weight is added once per occurrence of a term, not once per term.** Scoring
in `_addTerms` (`:470-479`) adds the field weight for every token the splitter
emits, so a word repeated three times in an 80-character `summary` scores 15, not
5. "Weight 5" is therefore not a ceiling on a term's contribution from that
field, and the effective per-field weight of a record grows with repetition
rather than with importance. Any future recalibration has to read the weight as
a per-occurrence multiplier, not as a fixed field score. This is stated here as
read from the code; it has not been measured.

Three consequences, all verifiable:

1. **The product's own stated goal is not being met.** "Deeper image
   understanding" and "smart summaries" are not partially served; the weight-4
   field that would carry them is `null` on every locally written record, and the
   weight-5 field is a truncated string slice of the weight-1 field.
2. **The weight-5 placeholder bug is FIXED — kept here as the evidence for why
   the phase gates exist.** `summary` was set to the literal `"No text found"`
   when OCR text is empty, and that string was indexed at weight 5, so the tokens
   `no`, `text` and `found` scored 5 points against *every* text-free screenshot
   in the library. **Measured before the fix:** a text-free screenshot ranked
   first for the query "text" with score 5, above a genuine OCR match at score
   1. The fix gates the single indexing entry point — `_searchableText`
   (`:460-465`) feeding `_addTerms` — against a named registry of display-only
   values (`:442-450`), so no placeholder can reach the index regardless of which
   field it came from. `lamType` was removed from the index in the same pass.
   Two deliberate non-changes: the stored `summary` still holds the placeholder,
   because nulling it would render finished analyses as "Processing…"
   (`home_screen.dart:1184`, `detail_screen.dart:162`) and would kill the
   special case in `chat_engine.dart:163`; and the `lamType` field itself is
   untouched, so cards and the detail view still read it. Only the index changed.
   `test/search_placeholder_test.dart` exercises the production write path and
   fails if this regresses.
3. **The weights themselves are still hand-set and still unmeasured.** Removing
   the two dead entries was a correctness fix, not a calibration. `_wSummary`
   through `_wSearchKeywords` are constants nobody has tuned. The weight comment
   at `screenshot_provider.dart:137-152` and `DESIGNSTATE.md:158` both now list
   all nine indexed weights and both state that nothing populates
   `searchKeywords`; the stale claim that `searchKeywords` is "generated by LLM
   prompt" is gone. The documentation is in sync. The values are not.

`objects` is indexed at weight 2 and works. **Do not propose adding label
indexing; it is already there.** The problem is what it is outranked by, not its
absence.

Two more limits worth measuring before tuning anything, both from the same
function: query terms are truncated to the first six
(`screenshot_provider.dart:52`, `1100-1102`), and candidate→record resolution
is a linear scan per candidate with no id→screenshot map
(`screenshot_provider.dart:1120-1123`).

---

## Open issues in search

Two defects in the tokenizer itself, confirmed by reading the code. Neither is
fixed. They are separate from the weight problem above: the weights can be
calibrated perfectly and still miss these.

**1. Underscores are not word separators. Confirmed defect, higher priority.**
The splitter is `[^\w\u4e00-\u9fff]+` (`screenshot_provider.dart:163`) and `\w`
includes `_`, so `receipt_0312` is a single token. Screenshot filenames are
exactly that shape — `Screenshot_20260927_143012.png` — so the `fileName` field
at weight 1 is largely unsearchable: a query for `receipt` does not find
`receipt_0312.png`. It is also inconsistent, since hyphens *do* split and
underscores do not. This is the cause of the two pre-existing failures in
`test/search_bounds_test.dart`: line 75 (`search('receipt')` against
`/g/receipt_0312.png`) and line 54 (see item 2, which fails for a second
reason). The fix is a one-character regex change, and it is cheap enough that
gating it behind a measurement is not obviously right — but the harness should
still record how often a query fails only because of the separator, so the size
of the win is a number and not an assertion.

**2. No prefix matching. Open decision, not a defect.** `search('bag')` does not
match "Bagel…". The spec as written is exact-token match with no stemming, no
prefix and no fuzzy, so this is arguably working as designed — but the search
box is an as-you-type box, and a user who types the first three letters of a
word and gets nothing will read it as broken search, not as a design decision.
`test/search_bounds_test.dart:54` asserts the opposite behaviour to the spec
(`expect(provider.search('bag').length, 1)` against "Bagel shop order total 12
dollars"), so the plan and the test currently contradict each other. **This needs
a product call and is not resolved here.** Either:

- **Adopt prefix matching.** Matches user expectation for an incremental search
  box, and the fix is confined to query-side prefix lookup over the posting
  keys. The cost is real: every term becomes a prefix scan over the vocabulary
  instead of an O(1) hash hit, and it widens recall for terms that are prefixes
  of unrelated words. `test/search_bounds_test.dart:54` then passes as written,
  and the spec line in §Current state has to change with it.
- **Keep exact match.** No cost, no new failure mode, and the vocabulary stays
  O(1) per term. The user-visible cost is that partial words return nothing
  until the word is complete. `test/search_bounds_test.dart:54` must then be
  changed to assert the exact-match behaviour, because leaving it as-is means
  the suite asserts a spec the product does not have.

Whichever way it goes, the test and the spec line in §Current state must be
changed in the same commit as the behaviour. They currently disagree.

**Not part of the problem: CJK.** There is no whitespace between CJK
characters, so the `\u4e00-\u9fff` range in the splitter is what keeps
`咖啡店的菜单` tokenizing at all. The CJK path in `search_bounds_test.dart:55-56`
is sound. The defect is specifically `\w` swallowing `_`.

---

## Competitive reality

External research, cited. Not measured in this repository.

**Conversational recall over screenshots is table stakes, with a poor track
record.** It is not a differentiator.

| Product | What it ships |
|---|---|
| Google Photos "Ask Photos" | Conversational over the library. Had to ship an opt-out after being paused (June 2025) for latency and quality |
| Pixel Screenshots | On-device Gemini Nano, conversational, multimodal. A platform vendor doing exactly this |
| screenshots.ai (DE) | The one indie product that shipped full-library chat. Dead — reported that "almost nobody kept using it past the first session" (user report) |
| Limitless | Best recall UX in the market. Users report it answering from outside its own corpus — base-model hallucination (user report) |
| Microsoft Recall | Search + timeline, **not** chat. Shipped dual text+visual matching |
| iOS | No screenshot-library recall feature at all |

**What serious products actually ship:** OCR text search, *and* visual/semantic
matching, *and* a per-item visual description. Plus on-capture indexing with
bulk backfill — which SIFT already has.

**Corpus size is not the bottleneck.** Mottelson (CHI 2023, n=52) measured a mean
of 498.8 and a median of 195 screenshots; Avast telemetry reported 86 per
device. Median user is roughly 200–500 screenshots; a heavy user is 1,500–5,000.
Retrieval quality and trust are the constraints, not scale.

**Cloud LLM indexing is cheap.** Gemini 2.5 Flash-Lite at $0.10 / 1M input
tokens puts a 4,000-screenshot backfill at roughly $0.40 one-time and about
$0.19/year at five new screenshots a day. Cost is not the reason to stay
on-device. Privacy is. This distinction matters: the next phase should not be
justified with a cost argument, because the cost argument does not hold.

**The one product that lost users lost them on retention, not capability.** Any
plan that optimises a feature the user reaches once is optimising the wrong
thing.

---

## The differentiators we actually have

**The privacy boundary — this is the defensible one.** No competitor keeps
screenshot images and OCR text on-device by default. Microsoft Recall drew
privacy refusals, carried two exploited CVEs, and used an unencrypted-at-rest
database that was dumpable post-authentication. SIFT's on-device analysis is
real, it is the default, and it is not matched. It is also load-bearing for the
retention lesson above: a screenshot library is exactly the corpus a user is
least willing to hand to a server.

**Grounded recall — a real asset, currently unmeasured.** `ChatEngine` builds a
screenshot block and hands it to a model under an explicit grounding
instruction (`litert_local_chat_model.dart:195-203`), and falls back to a plain
local reply whenever that is not available. "It only answers from your
screenshots" is a claim SIFT can actually back. It is not a claim anyone can
check until there is a recall number — which is Phase 0.

**The one we gave up: conversational chat as an edge.** It ships everywhere, it
is executed badly by at least two well-funded teams, and the sole indie entrant
in this space is dead. Keep it. Do not market it as the reason to switch.

---

## Phase 0 — Measure first

**Duration:** a few days. **New dependencies:** none.

1. **Build a 200-image recall harness.** Take ~200 real screenshots. Write the
   queries a user would actually type for those screenshots — not keyword
   variants, the phrases people use. Measure **recall@10 against the current
   weighted index**. This number is the baseline every later change is judged
   against. Without it, "the weights are wrong" is an opinion.
2. **Attribute hits per field.** For each query, log which fields produced the
   hit. The point is to find out which fields carry recall and which are
   decoration.
3. **Count the queries that fail at the tokenizer, not the weights.** Log every
   query that returns nothing and check it against a split on `_`. §Open issues
   in search item 1 says the `fileName` field is largely unsearchable because of
   it; the harness is what turns that into a measured recall loss.
4. **Recalibrate weights from the measurement, not from intuition.** Fix at
   minimum: the `summary`/`ocrText` duplication, the weight-4 `description` and
   `searchKeywords` that are always empty, and the per-occurrence scoring rule
   from §The actual gap, which changes what any weight means. A weight assigned
   to a field that is always `null` is not a ranking decision, it is a comment.
   The `"No text found"` placeholder is no longer on this list — it is fixed and
   covered by `test/search_placeholder_test.dart`. Keep it in the harness anyway
   as a regression check that the fix holds on real data.

**Deliverable:** a written recall@10 for today, and a ranked list of which
fields actually produce hits. Nothing in Phase 1 is worth building without it.

---

## Phase 1 — Fill the empty field honestly

**Gate to enter:** Phase 0 measured.

**No new ML. No network. No inference cost.**

1. **Generate a real per-screenshot description locally and deterministically**
   from signals that are already computed: ML Kit labels, OCR text, and layout
   position. Target shapes:
   - `"Receipt from <merchant>, total <amount>, paid by card"`
   - `"Chat screenshot with <app name>"`
   - `"Screenshot with no readable text — <labels>"`
   This is string composition over data the app has. It is not a model, it does
   not hallucinate, it costs nothing, and it is deterministic — the same
   screenshot always produces the same sentence. It fills the weight-4 field
   that is currently `null` on every record.
2. **Make it user-editable.** A generated description of a context-free
   screenshot is wrong in ways the user is the only one who can fix, and
   research on PixelShot found users actively harmed by an uneditable AI
   description they could not correct. An editable field is also the cheapest
   possible escape hatch if the generation is wrong.
3. **Backfill.** Existing records have `null` descriptions. Filling them
   deterministically means the improvement applies to the whole library, not
   just new captures.

**Honest limit:** this is templated composition, not comprehension. It will
produce a good description for a receipt and a mediocre one for a photo of a
street. That is still strictly better than `null`, and it is measurable in
Phase 0's harness.

---

## Phase 2 — Gate: image similarity, only if Phase 0 says text-free screenshots are unfindable

**Gate to enter:** Phase 0 shows that screenshots with no OCR text are
effectively unfindable. Note that `objects` already exists to cover them, so
this gate should be read strictly: if ML Kit labels are already recovering
those screenshots, **this phase does not run.**

**Before writing any embedding code**, run a 200-image experiment on SIFT's own
screenshots comparing:

- **(a)** the current index — the Phase 0 baseline
- **(b)** + DINOv2 ViT-S/14, int8, ~21 MB, 384-dim, Apache-2.0. Self-supervised,
  so it does not inherit the caption-alignment failure that hurts CLIP on UI
  screenshots
- **(c)** + SigLIP2 ViT-B/16 fp16, 185 MB — only if someone is willing to accept
  a 185 MB on-demand download

**Ship none of them unless one measurably beats (a) on recall@10.**

Two things to be clear about:

- **DINOv2 does image→image similarity, not text→image.** Dedup, clustering and
  "more like this" are in scope. Free-text search is not — users phrase queries
  in words, and OCR FTS already covers that.
- **Storage and search cost are not a constraint here.** 5,000 × 384-dim float32
  is about 7 MB, and brute-force cosine is roughly 2–10 ms in Dart on a
  mid-range phone (estimate, not measured on device). **Do not build HNSW,
  FAISS, or any vector index at this corpus size.** If embeddings are ever
  added, fuse them with text search using Reciprocal Rank Fusion at k=60 — the
  pattern used by memsearch — so exact strings (order numbers, app names, error
  codes) still win.

An image→image capability enables dedup, clustering and "more like this". Those
may be worth more than search, and they are cheap. That is a reason to run the
experiment, not a reason to skip the gate.

---

## Phase 3 — Only if the Phase 2 gate passes: real image understanding

`SmolVLM2-500M` exists as a `.litertlm` bundle in the same litert-community
Hugging Face repository, and LiteRT-LM supports vision. It would reuse the exact
download and registration pattern already built for Qwen3-0.6B — the same URL
shape, the same file-name-keyed store, the same cancellation, the same removal
reporting. 361 MB, ~0.8 GB RAM (published figures, not measured here).

**Record the trade-off honestly:** it roughly doubles the user's download for a
feature most users will not use. It is too heavy for 2 GB devices and must be
opt-in, like the current model. This phase is the only honest route to "describe
what you see" on-device, and it is expensive enough that it needs the Phase 2
number to justify it.

---

## Constraints register

- **Play Store 200 MB AAB limit.** The current on-device text model is a 614 MB
  *runtime download, not a bundle* (`local_model_spec.dart`). Keep it that way.
  Nothing large goes into the AAB.
- **LiteRT-LM ships Android arm64-v8a binaries only.**
  `LiteRtLocalChatModel.isSupportedDevice` checks `Abi.androidArm64` and refuses
  before any byte moves. On x86_64 and 32-bit the app installs and runs fine;
  only the model is unavailable and Settings says so.
  **Do not re-add an `ndk.abiFilters` restriction.** It was removed
  (`android/app/build.gradle.kts:35-42`) because it applied to every build type
  and cost x86_64/32-bit users the entire app — capture, OCR, search, cloud chat
  — for a feature that is not on those devices. The plugin's build hook emits no
  native asset for `android_x86_64` and still succeeds.
- **Low-end devices are a real audience.** 2–4 GB RAM is not an edge case. A
  0.6B model at 614 MB, plus KV cache, plus ML Kit, plus a screenshot library is
  tight. Consider a smaller model tier (a 350M-class bundle) and scale the
  context window down on `ActivityManager.isLowRamDevice()`.
  *Proposal — there is no `isLowRamDevice` call in `lib/` today; the engine's
  context is a fixed 2048 tokens (`litert_local_chat_model.dart:155`).*
- **On-device multimodal on Android is effectively Pixel-class hardware only.**
  ML Kit GenAI Image Description is Android-only, API 26+, needs its own model
  download, and is restricted to a Pixel-class device list. It is not a general
  path and must not be planned as one.
- **Cloud inference requires the user's own API key.** There is no app-funded
  backend, and adding one is deferred. Do not design a feature that assumes one.
- **A field weight is a per-occurrence multiplier, not a per-field score.**
  `_addTerms` (`screenshot_provider.dart:470-479`) adds the weight for every
  token emitted, so a term repeated *n* times scores *n* × weight from that
  field. A word appearing three times in an 80-character `summary` scores 15, not
  5. Do not reason about a weight as a cap, and do not compare two fields by
  their weight values alone — a repeated term in a heavy field outranks a term
  in a light one by repetition alone. Read from the code, not measured.
- **`lamType` is display-only and must stay out of the index.** Both local write
  paths store the constant `"document"` (`screenshot_provider.dart:345`, `:600`),
  so it can never discriminate between results. The field itself is still read —
  `TypeBadge` (`home_screen.dart:1192`, `detail_screen.dart:155`),
  `AppTheme.typeLabel` (`detail_screen.dart:236`) and the chat context dump
  (`chat_engine.dart:254`) — and the `byType` getter
  (`screenshot_provider.dart:185-192`) groups by it. **But `byType` has no
  callers in `lib/`, and there is no type filter in the app.** The UI filters by
  tag (`byTag`, `:199-204`) and by favourites (`_showFavoritesOnly`). Do not
  write "the type filter reads it" — nothing in the product does.

---

## Do not

- Do not add a CLIP or CLIP-successor image embedder without a measured win on
  SIFT's own screenshots. The published evidence is against it: UIClip (UIST
  '24, arXiv:2404.12500) measured MRR 0.25 (BetterApp) / 0.147 (JitterWeb) on
  real UI screenshots — the right answer lands in the top few, not first — and
  states that CLIP-family models "are not well-suited for judging UI quality and
  relevance" and "fall short in accurately analyzing UI screenshots."
- Do not escape via a bigger CLIP. MetaCLIP H/12, roughly 6× larger, gained
  about +0.02 MRR.
- Do not fine-tune CLIP on a public UI screenshot dataset. Fine-tuning on
  Screen2Words, the largest public screenshot-plus-caption set, made JitterWeb
  *worse*: 0.147 → 0.113.
- Do not add a vector index (HNSW, FAISS) at this corpus size. Brute force is
  2–10 ms.
- Do not bundle a 100+ MB vision model in the base AAB. SigLIP2 ViT-B/16 fp16 is
  185 MB, 92.5% of the AAB budget on its own, and 185 MB resident is not
  acceptable on a 2–4 GB device. Play Feature Delivery is the only viable
  route, and it still does not solve residency.
- Do not restore an ABI filter on the Android build.
- Do not re-introduce hosted image analysis without an explicit, visible user
  decision. It was removed deliberately.
- Do not trust a TFLite GPU delegate's residency report. A ViT on the GPU
  delegate can report 100% residency and return silently wrong output — there
  is a documented fp16 LayerNorm overflow in the SigLIP2 conversion. NNAPI is
  deprecated upstream, and `tflite_flutter` is ~11 months stale and raises
  minSdk to 26, which would exclude the low-end target.
- Do not let the answer layer respond from model knowledge instead of the
  user's own screenshots. Always ground in retrieved screenshots. Limitless
  users noticed exactly this failure, and it is the fastest way to lose trust in
  a feature whose entire promise is that it is about *your* screenshots.
- Do not cite a benchmark for SigLIP2, MobileCLIP2 or DINOv2 on screenshot
  retrieval. No such published benchmark was found. That measurement does not
  exist, which is exactly why Phase 0 has to build it.

---

## Deferred / explicitly not now

Carried forward from the previous plan, still valid:

- **Cross-device sync.** Adds upload, storage and cost. Revisit when there is a
  user base to justify the infrastructure — and note it directly contradicts the
  privacy boundary, so it needs its own decision, not a phase slot.
- **Action model / auto-ordering.** High complexity (payments, third-party
  APIs, liability). Not worth pursuing until the core product is validated.
  Current behaviour is correct and should not change: an action is offered only
  when a record carries one, and every one waits for approval.

Added:

- **Image embeddings and any vector index** until the Phase 2 gate passes.
- **A funded cloud backend.** Cloud chat stays BYO-key.
- **On-device multimodal on non-Pixel Android.** Not a general path (see
  constraints).
- **Collections/boards, screenshot-of-the-day, timeline, export-insights, OS
  share.** Carried from the old Phase 2/3 lists, unbuilt, and with no evidence
  yet that they move retention.
- **TFLite / TFLite-based vision runtime on device**, on the delegate and
  staleness evidence above.
