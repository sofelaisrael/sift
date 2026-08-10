# Sift + LAM

**Screenshot → AI understands → Takes action**

## Download

[![Latest release](https://img.shields.io/github/v/release/sofelaisrael/sift?label=latest)](https://github.com/sofelaisrael/sift/releases/latest)

Grab the latest **Android APK** from the [Releases page](https://github.com/sofelaisrael/sift/releases/latest) — a new build is published automatically for every `v*` tag.

Install the APK on your phone (allow "install from unknown sources"). Everything runs on-device; AI analysis uses your own Gemini API key, added in Settings.

## The Problem

Screenshots are digital junk. You take them, you forget them. They sit in your gallery forever.

## The Solution

Sift uses a **Large Action Model (LAM)** to:
1. **Understand** what you're looking at
2. **Extract** key information
3. **Take action** (calendar, reminders, shopping lists)

## Demo Flow

### 1. Take a Screenshot
- Flight confirmation
- Recipe from Instagram
- Deadline reminder

### 2. AI Analyzes
- "I see a flight to NYC on Dec 15 at 3pm"
- "I see a recipe for Chicken Tikka Masala"
- "I see a deadline for Dec 20"

### 3. Action Taken
- ✓ Calendar event created
- ✓ Shopping list with 12 ingredients
- ✓ Reminder set for 3 days before

## How It Works

```
Screenshot → ML Kit (OCR) → Gemini (LAM) → Actions
                          ↓
                    ┌─────────────┐
                    │  Calendar   │
                    │  Reminders  │
                    │  Shopping   │
                    └─────────────┘
```

## Tech Stack

- **Framework**: Flutter (Android + iOS)
- **OCR**: ML Kit Text Recognition (on-device)
- **LAM**: Gemini Pro + Function Calling
- **Calendar**: device_calendar plugin
- **Storage**: Hive (local-first)

## Privacy

- **On-device processing**: Your screenshots never leave your phone
- **Ephemeral by default**: We discard images after extracting actions
- **User confirmation**: Every action requires your approval

## Setup

1. **Install Flutter**
   ```bash
   flutter doctor
   ```

2. **Get Dependencies**
   ```bash
   cd ScreenSort-LAM
   flutter pub get
   ```

3. **Configure API keys** — keys are not committed. Add a free provider key in the app's **Settings → AI Provider** screen (or set `GROQ_API_KEY` / `GEMINI_API_KEY` in your Codemagic environment for CI builds).

4. **Run**
   ```bash
   flutter run
   ```

## Project Structure

```
lib/
├── main.dart
├── models/
│   └── screenshot.dart
├── services/
│   ├── ocr_service.dart      # ML Kit OCR
│   ├── lam_service.dart      # Gemini LAM
│   └── action_service.dart   # Calendar, reminders, etc.
├── providers/
│   └── screenshot_provider.dart
└── screens/
    ├── home_screen.dart
    └── detail_screen.dart
```

## Judge-Proof Answers

**Q: How do you handle sensitive info?**
> On-device processing. Images discarded after extraction. User confirms every action.

**Q: What if LAM misinterprets?**
> Confidence threshold + user confirmation. We're conservative by design.

**Q: Why not Siri/Google Assistant?**
> They're reactive (you tell them). We're proactive (we understand what you're looking at).

**Q: What's your unfair advantage?**
> We're the only screenshot app that ACTS. Others just categorize.

## License

MIT License
