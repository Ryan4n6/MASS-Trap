# M.A.S.S. Trap — Technical Assessment & Roadmap

> An honest evaluation of where this project stands, where the cracks are forming, and what to do about them.
> Written 2026-02-16 (Session 4) as a collaborative Human + AI architecture review.

---

## Table of Contents

1. [What's Working](#whats-working)
2. [Where the Cracks Are](#where-the-cracks-are)
3. [Recommended Tech Stack Changes](#recommended-tech-stack-changes)
4. [The Companion App Path](#the-companion-app-path)
5. [Prioritized Action Items](#prioritized-action-items)
6. [The Magna Carta — Human/AI Collaboration Principles](#the-magna-carta)

---

## What's Working

### Firmware Architecture — Genuinely Impressive

- **Spinlock-protected ISRs** with `portMUX_TYPE` on dual-core ESP32-S3 — correct approach to torn 64-bit reads
- **ESP-NOW auto-discovery** with role-based pairing — devices find each other without configuration
- **Microsecond clock sync** across devices — `MSG_SYNC_REQ`/`MSG_OFFSET` protocol with drift suppression
- **Non-blocking state machines** — zero `delay()` calls, everything is `millis()`/`micros()` driven
- **Two external dependencies** (WebSockets + ArduinoJson) — everything else is built on ESP32 native APIs
- **Custom partition table** — 3MB per OTA slot, ~9.9MB LittleFS, 64KB coredump. Deliberate allocation.
- **Graceful degradation** — Audio, LiDAR, speed trap, WLED all optional, zero overhead when disabled

### Deployment Pipeline — Better Than Most IoT Companies

- **LittleFS hot-push** via `curl` — update HTML/JS/CSS on live devices without recompiling firmware
- **OTA fleet updates** — push firmware to 3 devices over WiFi in ~3 minutes total
- **LittleFS-first, PROGMEM fallback** — web files served from filesystem with compiled-in safety net
- **GitHub Releases** with `.bin` assets — proper firmware distribution with MD5 verification

### Project Identity — The Differentiator

- **Forensic philosophy** throughout: case numbers, evidence tags, chain of custody, NFC intake
- **Kid-first UX** — audio prompts, big buttons, kiosk mode, 5 CSS themes
- **Documentation IS the product** for judges and parents — not an afterthought
- **Family story woven into the architecture** — Daytona theme, The Special K Report, Builder credits

### Documentation & Context System

- **CLAUDE.md** — one of the most thorough project briefs for AI collaboration, covering architecture, conventions, boot sequence, thread safety patterns
- **MEMORY.md** — running memory log that allows session continuity across context windows
- **Design documents** — BACKLOG_PLANS, MESH_AUTONOMY, DAYTONA_THEME_BRIEF, HARDWARE_CATALOG all in-repo

---

## Where the Cracks Are

### 1. The `docs/` Directory Is Becoming a Second Application

**Current state:** `docs/` contains a landing page with interactive dashboard demo, a parts store with affiliate links, a parents' guide, a judges' page, a build wizard, a photo punchlist app, and a stats system.

**The problem:** That's not documentation — that's a web app suite sharing a directory with firmware source code. Today it works because one human + one AI maintain perfect mental context. Six months from now:

- Updating the wizard independently of the firmware requires touching the same repo
- A fork for the ESP32 code carries 40KB+ of Amazon affiliate HTML
- No shared components — each page reinvents CSS variables, JS state management, localStorage keys
- Bus factor is 1 human + 1 AI

### 2. Single-File HTML Pages Don't Scale

**Symptom:** `dashboard.html` is 8,000+ lines. `docs/index.html` is 1,500+ with the embedded demo. Each page is its own universe.

**The cost:**
- The emoji bug in `parents-guide.html` required knowing that CSS `content:` properties don't parse HTML entities — knowledge trapped in one file's context
- No shared component library means every UI pattern (theme switcher, progress bar, filter tabs) is reimplemented per page
- Style changes require touching N files instead of 1 shared stylesheet
- A contributor who isn't us would drown trying to understand 12 independent HTML monoliths

### 3. No Test Framework Is a Time Bomb

**Current approach:** "Tested on hardware" via serial monitor and web console.

**The risk:** Three production devices are OTA-flashed simultaneously. One bad physics calculation, one broken semver comparison, one malformed WebSocket message — and the fleet bricks.

**What's testable WITHOUT hardware:**
- Physics calculations (time → velocity → momentum → kinetic energy)
- Semver comparison logic (the `-rc1` NaN bug would have been caught)
- CSV export formatting
- WebSocket message parsing/serialization
- Clock offset calculation
- ESP-NOW message encoding/decoding (fixed-point speed values)
- Config JSON validation

These are all pure functions. They can run on a host machine in PlatformIO's native test environment.

### 4. No CI/CD Pipeline

Every push goes straight to `main` without automated checks. A compile failure isn't caught until someone runs `pio run` manually. GitHub Actions is free for public repos and would take 20 minutes to set up.

### 5. GitHub Wiki Is Dead — But Hand-Coded HTML Docs Are 1998

The instinct to reject GitHub Wiki is correct — it's a markdown-only ghetto with no customization, no components, no build pipeline. But the replacement (hand-rolled HTML in `docs/`) trades one set of limitations for another: no search, no versioning, no markdown authoring, no component reuse.

---

## Recommended Tech Stack Changes

### Documentation Site: Astro + Starlight

**What it is:** Astro is a static site generator that ships zero JavaScript by default. Starlight is their documentation theme.

**Why it fits this project:**

| Need | Current Approach | Astro/Starlight |
|------|-----------------|-----------------|
| Write content | Edit 1500-line HTML files | Write `.md` files |
| Interactive components | Embedded in HTML monoliths | "Component islands" — hydrate only where needed |
| Search | None | Full-text search, zero config |
| Versioned docs | Manually maintain old pages | Built-in version selector |
| Themes | Per-file CSS variables | Global theme system with component support |
| Build output | Raw HTML files | Static HTML to `docs/` — same GitHub Pages hosting |
| JavaScript shipped | Everything or nothing | Zero by default, opt-in per component |

**Migration path:**
1. Existing HTML content becomes markdown files
2. Interactive components (dashboard demo, punchlist, wizard) become Astro "islands"
3. Build output is still static HTML in `docs/` — same hosting, same URLs
4. CSS themes become a shared design token system

**The dependency tradeoff:** Requires Node.js (`brew install node`). This is the only new system dependency. It's a real cost — acknowledge it, decide if the benefits justify it.

**Alternative if Node.js is a dealbreaker:** Zola (Rust-based, single binary, no runtime dependencies). Less ecosystem, fewer components, but zero dependency footprint. Markdown-first with Tera templates.

### Firmware: Keep What Works, Add Safety Nets

The PlatformIO + Arduino framework on ESP32-S3 is the right choice. Don't change it. Add:

**PlatformIO Native Unit Tests:**
```ini
; In platformio.ini
[env:test]
platform = native
test_framework = unity
build_flags = -DUNIT_TEST
```

Test pure functions on the host machine — no hardware needed:
```
test/
  test_physics/    — velocity, momentum, KE calculations
  test_semver/     — version comparison logic
  test_csv/        — export format validation
  test_protocol/   — ESP-NOW message encoding/decoding
  test_clock/      — offset calculation, drift detection
```

**GitHub Actions CI:**
```yaml
# .github/workflows/build.yml
name: Build
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with: { path: ~/.platformio, key: pio }
      - run: pip install platformio
      - run: pio run          # compile check
      - run: pio test -e test # unit tests
```

Free. Runs on every push. Catches compile failures and logic regressions before they hit the fleet.

### Web Serving on ESP32: No Change

The LittleFS-first + PROGMEM fallback pattern is solid for embedded. The ESP32's web server handles the dashboard, config, and API endpoints. This doesn't need framework changes — it needs the documentation site to move OUT so the device serves only what devices should serve.

---

## The Companion App Path

### Phase 1: PWA-ify What Exists (30 minutes)

Add `manifest.json` and a service worker to `punchlist.html`. It installs on iPhone home screen as an app icon. Works offline via cache. This is not a rewrite — it's 2 files added to `docs/`.

```json
// docs/manifest.json
{
  "name": "M.A.S.S. Trap",
  "short_name": "MASS",
  "start_url": "/MASS-Trap/punchlist.html",
  "display": "standalone",
  "background_color": "#091B2F",
  "theme_color": "#D4AF37"
}
```

### Phase 2: Dedicated Mobile Dashboard (When Ready)

A proper mobile-first dashboard using **Preact** (3KB, React-compatible API):
- Separate repo: `MASS-Trap-App`
- Talks to existing ESP32 REST API + WebSocket
- Deploys to GitHub Pages or Netlify
- Works offline via service worker cache
- mDNS device discovery or QR code pairing

### Phase 3: The Flip (The Dream)

The app becomes the primary interface. The ESP32's built-in web server becomes a fallback for LAN-only access without a phone. The firmware API is the stable contract — the UI layer is swappable.

### Why NOT Build a Custom Framework

Building a framework from scratch is how projects die. The ESP32 already HAS a REST API + WebSocket — that IS the backend. The question is only "what renders the frontend?" and for that, proven lightweight tools (Preact, Astro, vanilla JS PWA) beat custom solutions every time.

---

## Prioritized Action Items

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| 1 | Add `manifest.json` + service worker to punchlist | 30 min | iPhone home screen app, offline support |
| 2 | Set up GitHub Actions CI (compile check) | 20 min | Catch build failures before OTA |
| 3 | Add PlatformIO unit tests for pure functions | 1-2 hrs | Regression protection for physics, parsing |
| 4 | Evaluate Astro/Starlight for docs | Half day | Decide: is Node.js worth the benefits? |
| 5 | Separate `docs/` into its own build pipeline | 1-2 days | Docs site becomes maintainable long-term |
| 6 | Write the Magna Carta as CONTRIBUTING.md | 1 hr | Codify the collaboration principles |

---

## The Magna Carta

### Human/AI Collaboration Principles for Engineering Partnerships

> Written from direct experience building M.A.S.S. Trap — 52 commits, 36,164 lines, 6 days, $830K COCOMO equivalent.

#### Article I — Division of Labor

**The human owns the "why" and the "what." The AI owns the "how."**

The human decides that Ben needs a science fair workflow. The AI decides it needs 6 phases with Locard's Exchange Principle ordering. Both are right calls by the right party. The human brings domain expertise, user empathy, and taste. The AI brings implementation speed, pattern recognition, and tireless consistency.

Neither party overrides the other's domain. The human doesn't dictate CSS properties. The AI doesn't dictate what photos to take.

#### Article II — Context Is Sacred

**Invest in context transfer. It's not overhead — it's infrastructure.**

Every project needs:
- **A machine-readable brief** (CLAUDE.md) — architecture, conventions, build commands, module relationships
- **A running memory log** (MEMORY.md) — decisions, discoveries, session history, fleet status, lessons learned

These documents are why session 4 is productive instead of starting from zero. They are the most important files in the project. Maintain them with the same rigor as source code.

#### Article III — Ship to Production

**Nothing is real until it runs on hardware or serves to a browser.**

Push to `main`. OTA-flash real devices. Check GitHub Pages. Feature branches exist for multi-day work only. Short feedback loops (write, push, verify live) create flow state. Protect that momentum — it's a feature, not an accident.

#### Article IV — Honest Technical Debt Accounting

**The AI must be the project's biggest critic, not its biggest cheerleader.**

It is the AI's responsibility to flag:
- Patterns that work today but won't scale
- Missing test coverage for critical paths
- Architecture decisions that increase maintenance burden
- Tech debt that's accumulating silently

"Ship it" mode is valuable. But a good collaborator says "this works now AND we need to talk about what happens at 20 pages" — both halves, in the same breath.

#### Article V — Irreversible Decisions Belong to the Human

**The AI presents options with tradeoffs. The human decides.**

BFG history rewrite? Human's call. What stays public about the family? Human's call. Which WiFi password to rotate? Human's call. Promoting a pre-release to full release? Human's call.

The AI never makes irreversible changes without explicit human approval. The AI never assumes consent from context.

#### Article VI — Tests Are for What the AI Writes

**If the AI generates logic, there should be tests. If the AI generates UI, the human verifies on real devices.**

Trust but verify, in both directions:
- AI-generated physics calculations get unit tests
- AI-generated HTML gets verified on real browsers by the human
- AI-generated deployment scripts get dry-run confirmation before execution

The human is the QA department. The AI writes its own test harness.

#### Article VII — Documentation Is a First-Class Product

**For half the audience (judges, parents, contributors), the docs ARE the deliverable.**

Documentation deserves:
- Its own build pipeline
- The same engineering rigor as firmware
- Design review and iteration cycles
- Versioning that tracks the project it documents

A parents' guide with broken emoji rendering is as much a bug as a broken ISR.

#### Article VIII — The Human Sets the Pace

**The AI matches the human's energy and schedule, not the other way around.**

When the human says "let's VibeDoc while Ben rests" — we document. When Ben is ready to wire terminal blocks — we guide. When it's 5:30am and momentum is a freight train — we ride. When the human says "save it all for now" — we save it.

The AI never creates artificial urgency. The AI never guilt-trips about unfinished backlog. The project serves the family, not the other way around.

---

*This document is a living assessment. Update it as the project evolves, as new patterns emerge, and as the Human/AI partnership matures.*

*"Because Dad built it that way." — And because his kid is going to build it better.*
