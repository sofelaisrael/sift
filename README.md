# Sift

**Screenshot → AI understands → Takes action**

[![Latest release](https://img.shields.io/github/v/release/sofelaisrael/sift?label=latest)](https://github.com/sofelaisrael/sift/releases/latest)

[Download the latest Android APK](https://github.com/sofelaisrael/sift/releases/latest) — auto-published on every version tag.

---

## The Story

I take screenshots constantly. Flight confirmations. Recipes from Instagram. Deadline reminders. Interesting articles I'll "read later."

They pile up. I never look at them again.

Sift was built to change that. Not by organizing screenshots — by *understanding* them and *doing something* about them.

You take a screenshot. Sift reads it, understands what it is, and creates the relevant action. A flight becomes a calendar event. A recipe becomes a shopping list. A deadline becomes a reminder.

No more digital hoarding.

---

## How It Works

```
Screenshot → ML Kit (on-device OCR) → Gemini (LAM) → Actions
                                                    ↓
                                              ┌─────────────┐
                                              │  Calendar   │
                                              │  Reminders  │
                                              │  Shopping   │
                                              └─────────────┘
```

1. **Capture** — Take or select a screenshot
2. **Extract** — ML Kit reads text on-device (no cloud upload)
3. **Understand** — Gemini Pro classifies the content and extracts structured data
4. **Act** — Calendar events, reminders, shopping lists created automatically

---

## The Decisions

Every technical choice was deliberate:

**On-device OCR** — Screenshots contain sensitive information (boarding passes, medical appointments, financial data). ML Kit runs locally. Nothing leaves the phone.

**Gemini Function Calling** — Not just "describe this image." Gemini returns structured data I can programmatically act on. Confidence scores, extracted fields, action types.

**Hive over SQLite** — I needed fast key-value storage for screenshot metadata. No relational complexity, no SQL overhead. Just fast reads.

**Provider over Bloc/Riverpod** — Simplicity. The state tree is shallow. Provider matched the problem without over-engineering.

**Codemagic CI/CD** — Every `v*` tag triggers an automated build and APK publish to GitHub Releases. No manual builds. No "works on my machine."

---

## The Build

This isn't a weekend prototype. It's a real product:

- **63 tests** passing across unit, widget, and integration layers
- **80KB+ of design documentation** (DESIGNSTATE.md, WORKFLOWSTATE.md) — every decision recorded
- **Custom launcher icons** with adaptive icon support for Android
- **CI/CD pipeline** — Codemagic auto-builds and publishes APKs
- **Privacy-first architecture** — images discarded after extraction, user confirms every action

---

## What I Learned

**Mobile AI integration is different from web AI.** On mobile, you're managing battery, memory, and connectivity. Every API call is a design decision.

**OCR quality varies wildly.** Screenshots from different apps, different resolutions, different languages — ML Kit handles most of it, but edge cases are everywhere.

**CI/CD for mobile is harder than web.** Web is `git push → deploy`. Mobile is `sign → build → test → publish → hope the Play Store doesn't reject you`.

**Design docs pay off.** The 80KB of DESIGNSTATE.md caught three architecture bugs before they became production bugs. Recording decisions forces you to actually make them.

**Testing mobile is worth the effort.** 63 tests caught two regressions during the Codemagic migration that would have shipped silently.

---

## What I'd Do Differently

- Start with a formal state management pattern earlier (Provider worked, but the transition was painful)
- Add crash reporting from day one (Firebase Crashlytics, not custom)
- Design the action pipeline as a plugin system from the start (adding new action types shouldn't require touching core code)

---

## Privacy

- **On-device processing** — Your screenshots never leave your phone
- **Ephemeral by default** — Images are discarded after extracting actions
- **User confirmation** — Every action requires your approval
- **Your API key** — Add your own Gemini key in Settings. We never see it.

---

## Setup

```bash
# Install Flutter
flutter doctor

# Clone and get dependencies
git clone https://github.com/sofelaisrael/sift.git
cd sift
flutter pub get

# Configure API keys
# Add your Gemini API key in the app's Settings → AI Provider screen
# Or set GEMINI_API_KEY in Codemagic environment for CI builds

# Run
flutter run
```

---

## Tech Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Framework | Flutter (Dart) | Cross-platform, hot reload, strong mobile ecosystem |
| OCR | Google ML Kit | On-device, free, supports multiple languages |
| LAM | Gemini Pro + Function Calling | Structured output, confidence scores, function calling |
| Storage | Hive | Fast key-value, no SQL overhead |
| State | Provider | Simple, matches the shallow state tree |
| CI/CD | Codemagic | Flutter-native, auto-publish to GitHub Releases |
| Fonts | Source Serif 4 + JetBrains Mono | Readability + code aesthetics |

---

## Project Structure

```
lib/
├── main.dart
├── config.example.dart
├── models/
│   └── screenshot.dart
├── providers/
│   └── ScreenshotProvider
├── screens/
│   ├── Home, Detail, Chat, Settings, Onboarding
├── services/
│   ├── OCR, LAM, Action, Chat, Ingest, Watcher
├── theme/
│   └── Custom light/dark theme
└── widgets/
    └── Reusable UI components
```

---

## FAQ

**Q: How do you handle sensitive info?**
> On-device processing. Images discarded after extraction. User confirms every action.

**Q: What if LAM misinterprets?**
> Confidence threshold + user confirmation. We're conservative by design.

**Q: Why not Siri/Google Assistant?**
> They're reactive (you tell them). Sift is proactive (it understands what you're looking at).

**Q: What's the unfair advantage?**
> We're the only screenshot app that ACTS. Others just categorize.

**Q: Is this just a wrapper around Gemini?**
> No. Gemini handles understanding. The hard parts are on-device OCR preprocessing, structured data extraction, action pipeline design, and the mobile UX around confirmation and error recovery. The LAM is one component in a larger system.

---

## License

MIT License

---

*Built because I was tired of screenshot hoarding. Shipped because I believe in solving problems with code.*
