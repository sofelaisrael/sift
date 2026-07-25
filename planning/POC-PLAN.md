# ScreenSort - POC Planning & Decision Framework

**Date:** June 23, 2026  
**Status:** Awaiting user decisions to proceed

---

## Executive Summary

ScreenSort is a privacy-first screenshot manager that uses AI to automatically organize, classify, and resurface screenshots at the right moment. The concept is solid (9/10 problem definition) but critical decisions on AI architecture, category selection, and notification UX are needed before building.

---

## Research Findings

### 1. Cloud AI Costs (2026 Pricing)

| Provider | Model | Cost/Image | 100 imgs/day | 10K imgs/month |
|----------|-------|------------|--------------|----------------|
| Google | Gemini 2.0 Flash-Lite | $0.00002 | $0.06 | $0.20 |
| Google | Gemini 3.1 Flash | $0.00006 | $0.18 | $0.60 |
| OpenAI | GPT-4o mini | $0.00011 | $0.33 | $1.10 |
| OpenAI | GPT-4o | $0.00256 | $7.68 | $25.60 |
| Anthropic | Claude 3.5 Haiku | $0.00107 | $3.21 | $10.70 |

**Verdict:** Cloud costs are negligible at POC scale. Even at 10K images/month, Gemini Flash-Lite costs ~$0.20. Not a blocker.

### 2. On-Device AI (Now Viable)

| Project | Stack | Approach |
|---------|-------|----------|
| **ScreenMind** | Gemma 4 E2B (2.4GB) | On-device screenshot analysis, auto-tags + daily recap |
| **Vellum** | Gemma 4 on Android | Screenshot summarization, privacy-first |
| **AetherLens** | Gemma 4 E2B + Flutter | Auto-captures + curates screenshots |
| **Google ML Kit** | Gemini Nano | Built-in Android/iOS, multimodal |

**Key insight:** Gemma 4 E2B (2.4GB) runs on modern phones, processes ~25 screenshots before throttling, costs $0 cloud fees. Already used by multiple production apps.

### 3. Existing Similar Projects (Competitive Landscape)

- **ScreenMind** (GitHub) - Exact same concept: on-device screenshot analysis with Gemma 4
- **Vellum** (Medium) - Screenshot assistant using Gemma 4 on Android
- **AetherLens** (Medium) - Auto-capture + curation with Gemma 4 E2B

**Verdict:** The concept is validated by multiple existing implementations. Differentiation needed via category focus, notification UX, or target audience.

---

## Critical Decisions Required

### Decision 1: AI Architecture

| Option | Privacy | Cost | Reliability | Complexity |
|--------|---------|------|-------------|------------|
| **A. Cloud-only (Gemini Flash-Lite)** | Low | ~$0.20/month | High | Low |
| **B. On-device only (Gemma 4 E2B)** | High | $0 | Medium | Medium |
| **C. Hybrid** | High | ~$0.20/month | High | High |

**Recommendation:** Option C (Hybrid) - Use on-device for privacy-sensitive categories (repos, passwords), cloud for complex extraction (events, recipes).

### Decision 2: POC Categories (Pick 3-4)

| Category | Complexity | Value | Existing Support |
|----------|------------|-------|------------------|
| **Deadlines** | Low | High | Strong (dates, times, urgency) |
| **Recipes** | Medium | Medium | Good (structured extraction) |
| **Repos/Code** | Low | High | Good (GitHub URLs, code patterns) |
| **Gift Ideas** | High | Medium | Weak (subjective, needs context) |
| **Travel** | High | High | Medium (addresses, dates, maps) |
| **Shopping** | Medium | Medium | Good (prices, links, reviews) |

**Recommendation:** Start with **Deadlines + Recipes + Repos** (lowest complexity, highest value, best AI support).

### Decision 3: Notification/Resurfacing UX

| Option | User Effort | Relevance | Annoyance Risk |
|--------|-------------|-----------|----------------|
| **A. Daily digest (morning)** | Low | Medium | Low |
| **B. Deadline-only alerts** | Low | High | Low |
| **C. Weekly summary** | Low | Low | Very low |
| **D. Context-aware (location/time)** | Zero | High | Medium |

**Recommendation:** Option B (Deadline-only) for POC, with Option A as Phase 2.

### Decision 4: Monetization Path

| Path | Revenue | Complexity | Timeline |
|------|---------|------------|----------|
| **Freemium** | $5-10/month | Medium | 3-6 months |
| **One-time purchase** | $5-15 | Low | Launch |
| **API/B2B** | Custom | High | 6-12 months |

**Recommendation:** One-time purchase ($9.99) for POC, freemium for v1.0.

---

## POC Scope (Recommended)

### Phase 1: Core POC (2-3 weeks)
- Screenshot capture service (Android/iOS)
- On-device classification (Gemma 4 E2B)
- 3 categories: Deadlines, Recipes, Repos
- Basic notification system (deadline alerts)
- Local storage (no cloud)

### Phase 2: Enhanced POC (2-3 weeks)
- Cloud AI integration (Gemini Flash-Lite) for complex extraction
- Daily digest notifications
- Resurfacing engine (location/time-aware)
- Export/sharing features

### Phase 3: Production (4-6 weeks)
- Polish UI/UX
- Monetization integration
- App Store submission
- Privacy audit

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Cloud costs spiral | Cap at $10/month, use Gemini Flash-Lite |
| On-device too slow | Fallback to cloud for complex images |
| Privacy breach | Local-first, explicit consent, no PII storage |
| Low resurfacing relevance | User feedback loop, category tuning |
| Competing with ScreenMind | Focus on notification UX + category depth |

---

## Next Steps

**Awaiting user decisions on:**
1. AI architecture (Cloud / On-device / Hybrid)
2. POC categories (3-4 from list)
3. Notification approach (Daily digest / Deadline-only / Weekly)
4. Monetization path (Freemium / One-time / API)

Once decisions are made, proceed to project setup and Phase 1 implementation.
