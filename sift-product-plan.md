# SIFT — Product Plan

## Vision
An app that turns your screenshot folder into a searchable, conversational memory — not just OCR, but real understanding of what's in each image, accessible through chat.

## Current State
- Watches phone screenshot folder, uses Gemini for image analysis
- Core gap: analysis is closer to OCR extraction than true image understanding
- No conversational recall yet

## Differentiator
Most competitors (Screenshots.AI, PixelShot, Voda, ScreenshotAI) focus on search/organization. SIFT's edge is the **conversational interface** — asking about your screenshot history like you'd ask a person, plus deeper visual understanding (recognizing movies, scenes, context — not just text).

---

## Phase 1 — Core Upgrade (MVP)
Goal: nail the fundamental experience before adding extras.

1. **Auto-detect + notify** — background watcher pings user when a new screenshot is taken, offers instant analysis
2. **Deeper image understanding** — prompt Gemini to describe scene/context/objects, not just extract text (movie recognition, app/UI recognition, etc.)
3. **Smart summaries** — auto-generate a short natural-language description per screenshot
4. **AI chat interface** — let users ask about past screenshots conversationally ("that TikTok with the link from last week")

## Phase 2 — Organization Layer
Goal: help users manage the growing screenshot library.

5. **Collections/boards** — group screenshots by theme or project
6. **Favorites/pin system** — mark important ones for quick access
7. **Link extraction** — auto-pull and list all URLs found in screenshots
8. **Custom tags** — manual tagging for extra structure
9. **Search history** — revisit past queries

## Phase 3 — Polish & Delight
Goal: retention and daily-use hooks.

10. **Screenshot of the day** — resurface a forgotten old screenshot
11. **Screenshot timeline** — visualize screenshot activity over time
12. **Batch analysis** — analyze multiple screenshots at once, grouped insights
13. **Export insights** — generate reports ("movies I saved," "links from last month")
14. **Dark mode**
15. **Sharing** — share analyzed screenshots/collections

## Deferred / Future
- **Cross-device sync** — parked for now; adds upload/storage complexity and cost. Revisit once there's a user base to justify infrastructure investment.
- **Large Action Model integration** — e.g. auto-ordering from a restaurant screenshot. High complexity (payments, restaurant APIs, liability). Not worth pursuing until core product is validated.

---

## Immediate Next Step
Improve the Gemini prompt: shift from "extract text" to "describe what you see — objects, context, setting, notable details" before layering text extraction back in. This directly targets the image-understanding gap and sets up Phase 1 cleanly.
