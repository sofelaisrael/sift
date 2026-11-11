# Sift

**Screenshot → On-device OCR + visual labels → Local index and search**

[![Latest release](https://img.shields.io/github/v/release/sofelaisrael/sift?label=latest)](https://github.com/sofelaisrael/sift/releases/latest)

[Download the latest Android APK](https://github.com/sofelaisrael/sift/releases/latest) — auto-published on every version tag.

Install the APK on your phone (allow "install from unknown sources"). Screenshot OCR and visual labels run on-device. Cloud text chat uses your own saved key and only when you turn it on, and optional source lookup can query the web.

---

## The Story

I take screenshots constantly. Flight confirmations. Recipes from Instagram. Deadline reminders. Interesting articles I'll "read later."

They pile up. I never look at them again.

Sift was built to change that. Not by organizing screenshots — by making them searchable again and, where a record carries one, *acting* on it.

You take a screenshot. Sift reads the text and the visual labels on-device, indexes them locally, and gets the screenshot back out when you need it. When a record happens to carry a suggested action, Sift offers it and you decide.

No more digital hoarding.

---

## How It Works

```
Screenshot → On-device OCR + visual labels → Local library and search
                                                 ├→ Local chat: on-device model (LiteRT-LM), or a plain keyword reply
                                                 ├→ Cloud chat: opt-in, your own key → selected provider
                                                 ├→ Optional source lookup: the web
                                                 └→ Suggested action: only when the record has one
```

1. **Capture** — Take or select a screenshot, or index your whole library in one pass
2. **Read** — on-device OCR and visual labels run through ML Kit, which still catches screenshots with little or no text
3. **Index** — a local inverted index over that text and those labels
4. **Search and ask** — local search over the index; chat is answered on-device when a model is set up, and cloud chat is optional and off by default
5. **Act** — a suggested action is offered only when a record already has one, and only after you approve it

---

## The Decisions

Every technical choice was deliberate:

**On-device OCR and visual labels** — Screenshots carry sensitive things: boarding passes, medical appointments, financial details. Screenshot images and OCR text are not uploaded for analysis. ML Kit runs locally. Google Play services may download the small image-labeling model on first use, and that is the only thing fetched on your behalf.

**A local index instead of a hosted brain** — Search runs against an inverted index built on-device from OCR text and visual labels. No round trip to understand what you already saved.

**Chat that says who answered** — Local-only questions are answered by the on-device model when one is set up, and by a plain keyword reply when it is not. `ChatAnswerSource` names which path ran on every reply, so a model answer can never render as though it were a keyword list.

**No automatic action extraction** — The old version scored every screenshot and invented a calendar event or reminder for you. That is gone. Actions are available only when a record includes a suggested action, and every one of them waits for your approval. Fewer surprises, fewer wrong entries.

**Cloud chat is opt-in and yours** — When you enable it and save your own provider key, cloud chat sends derived text and context only. Screenshot images are not attached. No CI or release key is baked into the app, and CI copies only the non-secret config template.

**Hive over SQLite** — I needed fast key-value storage for screenshot metadata. No relational complexity, no SQL overhead. Just fast reads.

**Provider over Bloc/Riverpod** — Simplicity. The state tree is shallow. Provider matched the problem without over-engineering.

**Codemagic CI/CD** — Every `v*` tag triggers an automated build and APK publish to GitHub Releases. No manual builds. No "works on my machine."

---

## The Build

This isn't a weekend prototype. It's a real product:

- **440+ test cases** across unit, widget, and source-contract layers
- **228KB of design documentation** (DESIGN-BRUTALIST.md, DESIGNSTATE.md, WORKFLOWSTATE.md) — every decision recorded
- **Custom launcher icons** with adaptive icon support for Android
- **CI/CD pipeline** — Codemagic auto-builds and publishes APKs
- **Privacy-first architecture** — screenshot images and OCR text are not uploaded for analysis, and every action needs your approval

---

## What I Learned

**Mobile AI integration is different from web AI.** On mobile, you're managing battery, memory, and connectivity. Every network call is a design decision, and every one of them is a promise you have to keep.

**OCR quality varies wildly.** Screenshots from different apps, different resolutions, different languages — ML Kit handles most of it, but edge cases are everywhere. Visual labels help on the screenshots that have no text at all.

**Local-first shrinks the product.** Moving understanding on-device meant deleting confidence scores, automatic action extraction, and the hosted "understanding" step. What is left is smaller and honest about what it can and cannot know.

**CI/CD for mobile is harder than web.** Web is `git push → deploy`. Mobile is `sign → build → test → publish → hope the Play Store doesn't reject you`.

**Design docs pay off.** The design documentation caught three architecture bugs before they became production bugs, and the search index has been recalibrated repeatedly against a measured recall harness rather than by taste. Recording decisions forces you to actually make them.

**Testing mobile is worth the effort.** The suite caught regressions during the Codemagic migration and again during the on-device migration that would have shipped silently.

---

## What I'd Do Differently

- Start with a formal state management pattern earlier (Provider worked, but the transition was painful)
- Add crash reporting from day one (Firebase Crashlytics, not custom)
- Design the action pipeline as a plugin system from the start (adding new action types shouldn't require touching core code)
- Decide the privacy boundary before the features. I built the automatic actions first and had to take them out later

---

## Privacy

- **On-device analysis** — Screenshot images and OCR text are not uploaded for analysis. Google Play services may download the small image-labeling model on first use
- **On-device chat** — The optional chat model is not bundled. SIFT downloads it once from Hugging Face when you set it up, then runs it on this device with LiteRT-LM. A question never triggers a download
- **Local records** — Screenshot records, the index, and chat history stay on-device. Local-only mode blocks cloud chat and source lookup, and leaves local search and local actions working
- **Cloud chat** — Sends derived text and context, and only when you enable it and supply your own key. Without a key, Sift makes no hosted request
- **Actions** — Only records with a suggested action can offer one, and every action requires your approval
- **No shipped keys** — No CI or release key is baked into the app. `lib/config.dart` is gitignored and carries non-secret metadata only, and Codemagic copies the committed template verbatim

---

## Setup

```bash
# Install Flutter
flutter doctor

# Clone and get dependencies
git clone https://github.com/sofelaisrael/sift.git
cd sift
# lib/config.dart is gitignored; the committed template holds non-secret
# metadata only.
cp lib/config.example.dart lib/config.dart
flutter pub get

# Run
flutter run
```

Keys are never committed and never baked into a build. Cloud chat and source lookup run only against a key you save in the app's **Settings** screen; without one, Sift makes no hosted request.

---

## Tech Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Framework | Flutter (Dart) | Cross-platform, hot reload, strong mobile ecosystem |
| On-device analysis | ML Kit Text Recognition + Image Labeling | Runs locally, no upload, multiple languages |
| Search | Local inverted index over text and labels | Instant, offline, no network hop |
| On-device chat | LiteRT-LM via flutter_gemma | Optional model, downloaded on demand, never bundled |
| Cloud chat | Optional: Google Gemini, NVIDIA, or Groq | Only used when you enable it with your own key |
| Storage | Hive | Fast key-value, no SQL overhead |
| State | Provider | Simple, matches the shallow state tree |
| CI/CD | Codemagic | Flutter-native, auto-publish to GitHub Releases |
| Fonts | Source Serif 4 + JetBrains Mono | Readability + code aesthetics |

---

## Project Structure

```
lib/
├── main.dart                  # composition root, onboarding gate, auto-index
├── config.example.dart        # non-secret metadata template
├── models/
│   ├── screenshot.dart        # Hive record (typeId 0)
│   └── chat_message.dart
├── providers/
│   ├── screenshot_provider.dart   # library, local index, search, import, deletion
│   └── theme_controller.dart
├── screens/
│   ├── app_shell.dart, home_screen.dart, detail_screen.dart
│   ├── chat_screen.dart, settings_screen.dart, onboarding_screen.dart
│   └── actions_history_screen.dart, shopping_list_screen.dart
├── services/
│   ├── ocr_service.dart, image_labeler.dart    # ML Kit, on-device
│   ├── screenshot_analyzer.dart   # OCR + labels, no hosted provider
│   ├── ingest_service.dart        # bulk "index my library" pass
│   ├── screenshot_watcher.dart, watcher_service.dart
│   ├── chat_engine.dart           # routing + grounding, unit-testable
│   ├── local_chat_model.dart      # provider-neutral on-device contract
│   ├── litert_local_chat_model.dart, local_model_service.dart
│   ├── lam_service.dart           # optional hosted chat
│   ├── web_lookup.dart            # optional source lookup
│   └── action_service.dart, action_model.dart, file_enumerator.dart
├── theme/
│   ├── app_theme.dart, brutal_tokens.dart, motion_tokens.dart
└── widgets/
    ├── widgets.dart, chat_atoms.dart, sift_mark.dart, skeleton.dart
    ├── bottom_sheet.dart, about_dialog.dart, privacy_gate.dart, ingest_banner.dart
    └── brutal_{button,chip,field,activate}.dart
```

---

## FAQ

**Q: How do you handle sensitive info?**
> Screenshot analysis is on-device. Screenshot images and OCR text are not uploaded for analysis, and cloud chat only sends derived text and context when you enable it with your own key.

**Q: What if the on-device analysis misinterprets a screenshot?**
> OCR text and visual labels are aids, not guarantees. Read the saved text yourself, and confirm any suggested action before it runs. Sift no longer guesses and acts on its own.

**Q: Why not Siri/Google Assistant?**
> They're reactive (you tell them). Sift builds a local index of your screenshots once, so it can answer "what was that flight number?" later without you re-explaining it.

**Q: Is this just a wrapper around a cloud model?**
> No, not any more. OCR, visual labels, the index, search, and chat are all on-device — chat runs on a local LiteRT-LM model when you set one up. Cloud chat is an optional extra that needs your own key, and the app works fully without it.

**Q: Why do I not see any suggested actions?**
> The local analyzer never invents one. Actions exist for records that already carry a suggested action — typically written by an earlier version of Sift — and every one waits for your approval. New screenshots are indexed and searchable, but nothing is guessed on your behalf.

**Q: What's the unfair advantage?**
> The index is local and permanent. Nothing about your screenshots has to leave the device to be findable.

---

## License

MIT License

---

*Built because I was tired of screenshot hoarding. Shipped because I believe in solving problems with code.*
