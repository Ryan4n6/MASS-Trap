# Changelog

All notable changes to The M.A.S.S. Trap (Motion Analysis & Speed System) will be documented in this file.

## [2.6.0-beta] - 2026-02-16

### The Forensic Lab Manager Update

The 3-phase playlist workflow (Setup → Active → Completed) has been replaced with a **6-phase forensic intake workflow** that mirrors real forensic lab procedures. In real forensics, evidence tags and photographs are prepared BEFORE testing — not after. Case numbers must exist before a single car rolls. The system now acts as a virtual forensic lab manager guiding the operator (Ben, age 10) through proper chain of custody at every step.

Normal (non-playlist) race mode is completely untouched — NFC scan, arm, race, leaderboard, casual play all work exactly as before.

### Added — 6-Phase Science Fair Testing Workflow (`dashboard.html`)

**Phase 1: Experiment Setup** — Define variables, pick template or custom experiment
- Three experiment templates: "Mass vs Speed" (Ben's science fair), "Car vs Car", "Custom Experiment"
- Templates auto-fill independent/dependent/controlled variable definitions and weight conditions
- Manual override for any pre-filled value
- Weight conditions list with trials-per-condition config

**Phase 2: Vehicle Intake** — Select cars, verify weights, check NFC tags
- Car selector grid with per-car verification rows
- NFC status check per vehicle (✅ tagged / ⚠️ no tag)
- Weight display with milligram precision (0.001g step)
- Matrix generation using Locard's Exchange Principle ordering (condition → trial → car)
- Case numbers assigned on transition to Phase 3 via `evNextCaseNumber()`

**Phase 3: Evidence Prep** — The forensically critical phase (BEFORE any racing)
- Case assignment table: Run # | Case Number | Car | Condition | Trial
- **PRINT EVIDENCE TAGS** button — prints partial tags (case#, car, weight, QR — no time/speed yet)
- **📷 CAPTURE SETUP PHOTO** button with auto-assignment to next unphoto'd case number
- Photo tap-to-override: tap a case row to re-target photos for redo scenarios
- Photo checklist (advisory): scale readings, test setup, weight additions

**Phase 4: Pre-Flight Check** — Final review before testing begins
- Full test plan table with case numbers, car names, conditions, trials
- Step-by-step directions for Ben ("Place car at top", "Wait for Armed", "Release", "Catch at bottom")
- Auto-detected readiness checklist: WebSocket status, garage count, track length, tags printed, photos taken
- **BEGIN DATA COLLECTION** button

**Phase 5: Data Collection** — Racing with sanity checks
- Case number shown in race banner alongside run label
- Results table includes Case column
- Sanity checks on every race finish:
  - Time < 0.1s → "Sensor glitch? Keep or retry?"
  - Time > 15s → "Car may have stalled. Keep or retry?"
  - Speed = 0 → "Sensor didn't trigger. Keep or retry?"
  - 3 identical times in a row → "Possible malfunction"
- Yellow alert with KEEP RESULT / DISCARD & RETRY buttons
- Auto-advance pauses during sanity warnings
- `evRecordRun()` UPDATES pre-assigned evidence entries (doesn't create new ones)
- Audio prompts: "Run 5 of 20. Blue F-150, plus 7 grams, trial 2 of 3. Release when armed."

**Phase 6: Results & Report** — Summary, export, report generation
- Summary tables with averages per condition
- CSV + Summary text export
- **REPRINT TAGS (WITH RESULTS)** — full evidence tags with time/speed filled in
- **SCIENCE FAIR REPORT** link to `science_fair_report.html`
- Report persistence to ESP32 as JSON (configurable max saved reports, never auto-deleted)

### Added — Science Fair Laboratory Report (`science_fair_report.html`)
- **2,008-line standalone forensic evidence report page** served from ESP32 LittleFS
- Loads race data from `/api/history`, `/api/garage`, `/api/config` automatically
- Formatted for both screen (navy/gold M.A.S.S. Trap theme) and print (clean B&W, `@page` rules)
- Sections: Title Page, Abstract, Hypothesis, Variables, Materials, Procedure, Data Tables, Analysis, Conclusion
- Auto-calculated statistics: mean, standard deviation, percent difference between conditions
- Evidence chain of custody section with case numbers and timestamps
- Physics formula cards with live-substituted values from actual test data
- Print-optimized: page breaks, no-break sections, grayscale charts

### Added — About / Special K Report Page (`about.html`)
- **"The Special K Report"** — comprehensive project status page named after the stakeholder who needed it most
- Live device status: fetches `/api/info`, `/api/version`, `/api/wifi-status` in real time
- Project statistics: lines of code, features, API endpoints, race count, uptime
- Feature inventory with status indicators (complete / in progress / planned)
- **The Builders** section: credits for Ryan, Ben, Claude, Uncle Sam, and Kristina
- Closing remarks / dedication section
- Version badge now links to About page instead of GitHub releases

### Added — GitHub Pages Site (`docs/`)
- **`docs/index.html`** — Project landing page with feature highlights, architecture overview, and quick-start guide
- **`docs/store.html`** — Curated parts store with 3 budget tiers (Starter ~$25, Science Fair ~$60, Full Send ~$120)
- All Amazon links use real ASINs from actual purchase history with affiliate tag `ryanmassfelle-20`
- **"The Real Numbers" transparency section** — exact category spending breakdown (~$1,200 total project cost)
- AliExpress origin story: 15× ESP32-S3 N16R8 boards at $5.61 each, ordered August 17, 2023

### Changed — Evidence System Overhaul (`dashboard.html`)
- Evidence tags redesigned: smaller, more compact layout with max-width constraint
- Tag label size configuration bar: select preset sizes or custom dimensions
- `evRecordRun()` now has two code paths: playlist mode (update pre-assigned entry by case number) vs normal mode (create new entry — unchanged)
- Photo capture integrated into pre-race workflow (Phase 3) instead of post-race
- Setup photo bar added above dry-run controls

### Changed — Version Badge Routing (`main.js`)
- Version badge in footer now links to `/about.html` instead of GitHub releases or `/config#firmware-update`
- Update-available badge text updated to link to About page
- Consistent "About M.A.S.S. Trap" title text across all badge states

### Changed — UI Push Script (`push_ui.sh`)
- Added `about.html` and `science_fair_report.html` to file push list
- Zero-byte file safety check: refuses to push empty files (prevents bricking a UI page with 0-byte LittleFS write)

### Technical Notes
- **No firmware changes.** All modifications are in LittleFS-served HTML/JS/CSS files. The ESP32 binary from v2.5.0 (commit `58d8137`) is unchanged. Dashboard updates are hot-pushed via the file API.
- 6-phase workflow adds ~600 lines of JavaScript and ~130 lines of HTML (replacing ~130 lines of the old 3-phase UI)
- Phase state persisted to both `localStorage` AND ESP32 (`/experiment.json`) at every phase transition and after every race result. Power loss recovery uses whichever has the more recent `savedAt` timestamp.
- All new JavaScript continues to use ES5 (`var`, not `let`/`const`) for embedded browser compatibility.
- `dashboard.html` grows from ~3,200 lines to ~4,500 lines (~146KB → ~170KB) — well within ESP32 LittleFS capacity (9.3MB free).
- Normal race mode decision point in `handleStateUpdate()` unchanged: `playlistMode.active` is only `true` during Phase 5.
- GitHub Pages served from `docs/` directory (separate from `data/` which contains ESP32 LittleFS files).

### Status
- ⚠️ **Beta**: 6-phase workflow implemented but not yet field-tested with Ben. Normal mode verified working.

---

## [2.5.0] - 2026-02-13

### Thread Safety & Timing Integrity (Critical)
- **Spinlock protection for 64-bit timing variables** — All `startTime_us`, `finishTime_us`, `triggerTime_us`, and speed trap timestamps are now protected by `portMUX_TYPE` spinlocks. On the dual-core ESP32-S3, ISRs, the main loop, and the ESP-NOW receive callback run on different cores — without locking, 64-bit reads/writes can be torn (half-old, half-new), causing phantom timing errors. Affected modules: `finish_gate`, `start_gate`, `speed_trap`.
- **Atomic snapshots in `broadcastState()`** — WebSocket state broadcast now takes a consistent snapshot of both timing variables under lock before calculating elapsed time, preventing inconsistent reads during active races.
- **`nowUs()` marked `IRAM_ATTR`** — The microsecond timer function is now safe to call from ISR context (previously relied on compiler inlining).

### Added
- **NTP Wall-Clock Timestamps in Serial Log** — The `SerialTee` ring buffer now prepends `[HH:MM:SS.mmm]` timestamps to every log line using NTP time. Before NTP sync completes, uses uptime with `+` prefix (e.g., `[+01:23.456]`) to distinguish from wall-clock. Timestamps appear in the ring buffer (web console) only — UART output is unmodified. NTP sync is non-blocking and best-effort via `pool.ntp.org`.
- **Regional/Display Preferences** — Two new config fields:
  - `units`: `"imperial"` (mph, ft) or `"metric"` (km/h, m) — broadcast in WebSocket state for client-side unit switching
  - `timezone`: POSIX TZ string (e.g., `"EST5EDT,M3.2.0,M11.1.0"`) — drives NTP local time and log timestamps
- **WiFi Diagnostic Endpoint** — `GET /api/wifi-status` returns connection state, SSID, IP, RSSI, WiFi mode, and human-readable failure reason (e.g., "Wrong password", "SSID not found").
- **Captive Portal OS-Specific Handlers** — Explicit redirect handlers for iOS (`/hotspot-detect.html`), Android (`/generate_204`), and Windows (`/connecttest.txt`, `/fwlink`) probe URLs. Uses absolute `http://192.168.4.1/` Location headers and no-cache directives to prevent CNA caching issues.
- **Modular Web UI (LittleFS-first)** — New file-based UI architecture:
  - `dashboard.html` — Redesigned command center (replaces monolithic `index.html`)
  - `history.html` — Dedicated evidence log page
  - `system.html` — Redesigned system configuration (replaces `config.html`)
  - `main.js` — Shared JavaScript utilities
  - `style.css` — Shared stylesheet
  - All page routes now prefer LittleFS files, falling back to PROGMEM if missing. Existing PROGMEM pages remain as firmware-embedded fallback.
- **Theme Engine (5 Themes)** — Selectable via dropdown in footer, persisted to `localStorage`:
  - **Interceptor** (default) — Navy + gold, monospace fonts, forensic graph paper grid background
  - **Classic** — Hot Wheels branding: vibrant orange gradient, Hot Wheels yellow/blue, Arial Black/Impact font
  - **Daytona** — NASCAR-inspired: Impact font, yellow/red colors, checkered flag + tire skid CSS background
  - **Case File** — Police detective aesthetic: aged paper background with ruled lines and coffee stain ring, Courier typewriter font, red margin line, pushpin dots, auto-prepends "CASE #2026-" to subtitle
  - **Cyber** — Terminal green on black, CRT scan lines + green glow background
- **Dual-Layout Navigation** — Responsive nav system replaces inconsistent per-page links:
  - Desktop (>768px): Sticky top manila folder tabs
  - Mobile (<768px): Fixed bottom thumb bar (48px min touch targets)
  - Four sections: Live Monitor, Evidence Log, System Config, Terminal
- **Kiosk / Display-Only Mode** — For science fair presentation to judges:
  - Activate via `?kiosk` URL parameter or `Ctrl+K` keyboard toggle
  - Hides interactive controls (ARM/RESET/SYNC, garage, operations, navigation, theme selector)
  - Keeps visible: state banner, LED bar, race stats, physics, leaderboard, speed profile, charts, formulas, history
  - Tiny "Ctrl+K to exit" hint in bottom-right corner
- **Peer Hotlinks** — Peer hostnames are now clickable `http://{hostname}.local/` links in config, dashboard, start gate, and speed trap status pages. Speed trap status page now includes a peer network section (was missing).
- **`push_ui.sh`** — Shell script to convert `data/*.html` files into PROGMEM `html_*.h` headers.
- **Static asset routes** — `/style.css` and `/main.js` served with 1-hour cache headers. `/history.html` route for the evidence log page.

### Changed
- **Named Constants** — 20+ magic numbers extracted to `#define` constants in `config.h`: unit conversions (`MPS_TO_MPH`, `MPS_TO_KPH`, `METERS_TO_FEET`), timing limits (`MAX_RACE_DURATION_US`, `MAX_TRAP_DURATION_US`, `TRAP_SENSOR_TIMEOUT_US`), reset delays (`FINISH_RESET_DELAY_MS`, `START_RESET_DELAY_MS`), ESP-NOW intervals (`PING_INTERVAL_MS`, `PING_BACKOFF_MS`, `CLOCK_SYNC_INTERVAL_MS`, `PEER_HEALTH_CHECK_MS`, `BEACON_INTERVAL_MS`), peer thresholds (`PEER_ONLINE_THRESH_MS`, `PEER_STALE_THRESH_MS`, `PEER_SAVE_DEBOUNCE_MS`).
- **Clock sync drift filtering** — Finish gate only logs clock sync updates when drift exceeds 500µs or on first sync, reducing console noise during stable operation.
- **WiFi AP channel pinning** — After STA connection, `softAP()` is called with the STA channel to prevent channel-hopping that disrupts ESP-NOW.
- **WiFi failure diagnostics** — Human-readable failure reasons ("SSID not found", "Wrong password", "Connection timeout") logged and exposed via `/api/wifi-status`.
- **Default device_id from MAC** — `device_id` now defaults to `(mac[5] % 253) + 1` instead of hardcoded `1`, avoiding ID collisions when multiple unconfigured devices power up.
- **Non-blocking speed trap LED** — Replaced blocking `delay()` loop with millis-based 500ms blink pattern.
- **OTA auth flag** — Added `--auth=admin` to PlatformIO OTA upload flags in `platformio.ini`.
- **`broadcastState()` JSON** — Buffer increased 768 → 1024 bytes; now includes `units`, `midTrack_mps`, and `speed_mps` fields.
- **Config JSON buffer** — Increased 1536 → 2048 bytes to accommodate regional settings.
- **Cache-Control headers** — All dynamic HTML pages served with `no-cache, no-store, must-revalidate`; static assets cached appropriately.
- **Reboot reliability** — All reboot paths (`/api/config` POST, `/api/reset`, `/api/system/restore`, `/api/restore`) now flush TCP, disconnect AP clients, then delay before `ESP.restart()` — fixes CNA "config saved but page hangs" issue.
- **Version bump** — Firmware: 2.4.0 → 2.5.0

### Fixed
- **Peer discovery "Discovery failed" error** — JavaScript called non-existent `/api/discover` endpoint; corrected to `/api/peers` in config page, system page, and PROGMEM headers.
- **Track length initialization race condition** — Dashboard showed hardcoded "2.0 M" default until WebSocket connected. Now fetches `/api/config` on page load to get the real track length immediately.
- **Connection badge hidden behind nav** — Badge z-index bumped above navigation layer; desktop position adjusted to clear sticky header.
- **Config page content hidden behind save bar** — Added bottom padding to page container so fixed-position save bar doesn't cover the last config section.
- **CSS/JS externalization** — Extracted all inline styles (~1,200 lines) and scripts (~180 lines) from monolithic HTML files into shared `style.css` and `main.js`, eliminating duplication across 5 pages.

### Removed
- **Dead code cleanup** — `isCarPresent()`, `getLidarJson()` (lidar_sensor), `resetWLEDActivity()`, `testWLEDConnection()` (wled_integration), `sendToRole()` (espnow_comm).
- **Redundant includes** — `#include <esp_now.h>`, `#include <ArduinoJson.h>`, `#include <esp_mac.h>`, `#include <WiFi.h>` removed from files that get them transitively through headers.

### Technical Notes
- All spinlocks use `portENTER_CRITICAL` / `portENTER_CRITICAL_ISR` as appropriate for the calling context (main loop vs ISR). This is the ESP-IDF prescribed pattern for protecting shared state on dual-core chips.
- `SerialTee::writeTimestamp()` writes to the ring buffer only (not UART), so physical serial output format is unchanged.
- NTP uses `configTzTime()` which is non-blocking — the first call fires off a UDP request, and `getLocalTime()` returns false until a response arrives. The `ntpSynced` flag latches true once `tm_year > 100` (year 2000+).
- Config struct grows by 52 bytes (`units[12]` + `timezone[40]`) — well within the JSON document budget.
- New LittleFS UI files add ~180KB to the filesystem but remain within the 9.9MB partition. PROGMEM fallbacks ensure the device works even without uploading the new data files.
- Captive portal handlers use absolute URLs (`http://192.168.4.1/`) instead of relative (`/`) because some CNA implementations cache relative redirects incorrectly.
- All JavaScript uses ES5 (`var`, not `let`/`const`) for maximum browser compatibility on embedded web servers.
- Theme selection persists to `localStorage` and applies on page load before first paint.

---

## [2.4.0] - 2026-02-11

### The M.A.S.S. Trap Rebrand
The project has been renamed from "Hot Wheels Race Gate" to **The M.A.S.S. Trap** (Motion Analysis & Speed System). The name carries three meanings: "speed trap" from law enforcement, "mass" from physics, and "Massfeller" -- the family name. The entire UI has been redesigned with a police shield/badge authority aesthetic using navy + gold colors.

### Added
- **PlatformIO Support** -- Full `platformio.ini` configuration for the pioarduino platform (Arduino Core 3.x / ESP-IDF 5.x). One-command build, flash, OTA, and LittleFS upload. All board settings (flash size, PSRAM, partition table) are defined in config — no manual dropdown hunting.
- **Custom 16MB Partition Table** (`partitions.csv`) -- Fixes the v2.3.0 compile blocker where firmware (1.53MB) exceeded the default 1.25MB partition. New layout: 3MB per app slot (with OTA) + ~9.9MB LittleFS for data and audio files + 64KB coredump partition for crash diagnostics. PlatformIO handles this automatically; Arduino IDE auto-detects the CSV when Flash Size is set to 16MB.
- **Full System Snapshot** -- One-click backup/restore of the entire device state:
  - `GET /api/system/backup` returns a JSON envelope with config, garage, and history
  - `POST /api/system/restore` restores all three files and reboots
  - Clone mode (`?skip_network=true`) strips WiFi/hostname for flashing to a new device
  - UI in config page with Export/Import/Clone buttons
- **Audio System** (`audio_manager.h/.cpp`) -- MAX98357A I2S amplifier integration:
  - Non-blocking WAV playback via ESP32 I2S DMA ring buffer
  - Format: 8-bit unsigned, 16kHz mono WAV files stored in LittleFS
  - Sound slots: `armed.wav`, `go.wav`, `finish.wav`, `record.wav`, `countdown3/2/1.wav`
  - Web upload: `POST /api/audio/upload`, list: `GET /api/audio/list`, test: `POST /api/audio/test`
  - Configurable pins (BCLK, LRC, DOUT) and volume (0-21) via web UI
  - Disabled by default -- zero overhead when `audio_enabled = false`
- **LiDAR Car Presence Detection** (`lidar_sensor.h/.cpp`) -- Benewake TF-Luna solid-state LiDAR:
  - UART interface at 115200 baud, 9-byte frames with checksum validation
  - Signal strength filtering rejects low-confidence readings
  - State machine: NO_CAR -> CAR_STAGED -> CAR_LAUNCHED
  - Auto-arm: car present > 1 second at start gate triggers automatic ARM
  - WebSocket broadcast: `{"lidar": {"state": "staged", "distance_mm": 32}}`
  - Dashboard indicator: "LIDAR TARGET ACQUIRED" near ARM button
  - Configurable UART pins (RX=GPIO39, TX=GPIO38) and threshold distance
  - Disabled by default -- no UART init when `lidar_enabled = false`
  - No external library needed -- uses ESP32 built-in HardwareSerial
- **Speed Trap Node** (`speed_trap.h/.cpp`) -- New "speedtrap" ESP32 role:
  - Dual IR break-beam sensors ~10cm apart for mid-track velocity measurement
  - Microsecond ISR timing on both sensor pins
  - Calculates instantaneous velocity and sends to finish gate via ESP-NOW
  - New ESP-NOW message types: `MSG_SPEED_DATA` (10) and `MSG_SPEED_ACK` (11)
  - Dedicated status page at `/` showing last speed, peer status, sensor config
  - Dashboard "Speed Profile" card comparing start/mid/finish velocity
  - New PROGMEM page: `html_speedtrap_status.h`
- **Leaderboard Podium Overlay** -- Animated CSS overlay after each race:
  - Shows car ranking among all tested cars
  - "SUSPECT RANKED #1 -- NEW TRACK RECORD" style callouts
  - Slide-in animation, 3-second hold, fade out
- **Mechanic's Log** -- Per-car notes with timestamps:
  - Each car in garage JSON can have a `notes` array
  - Expandable accordion under each car in the garage section
  - "Add Note" button for tracking modifications (weight changes, lube, etc.)
  - Correlate modifications with performance trends
- **Speed Profile Card** -- Start/mid/finish velocity comparison visualization when speed trap data is available

### Changed
- **Full UI Rebrand** -- Every web page updated with M.A.S.S. Trap branding:
  - Dashboard: "M.A.S.S. TRAP COMMAND CENTER" with CSS shield badge
  - Color scheme: Dark navy (#1a1a2e) + gold (#d4af37) + white accents
  - State banners: AWAITING SUSPECTS / TRAP SET / IN PURSUIT / SUSPECT CLOCKED
  - Config page: "M.A.S.S. Trap - Configuration"
  - Console page: "M.A.S.S. Trap - Console"
  - Start gate: "M.A.S.S. TRAP SYSTEM"
- **Boot sequence** -- Prints M.A.S.S. Trap banner with version and "ALL SYSTEMS OPERATIONAL"
- **Default hostname** -- `masstrap` (was `hotwheels`), mDNS at `http://masstrap.local`
- **AP naming** -- `MASSTrap-Setup-XXXX` (was `HotWheels-Setup-XXXX`)
- **Config struct** -- 13 new fields for audio, LiDAR, and speed trap configuration
- **ESP-NOW protocol** -- Extended from 9 to 12 message types (added speed data, speed ack, reserved)
- **DeviceConfig role** -- Now supports `"start"`, `"finish"`, and `"speedtrap"`
- **Version bump** -- Firmware and Web UI: 2.3.0 -> 2.4.0
- **All PROGMEM headers rebuilt** -- `html_index.h`, `html_config.h`, `html_console.h`, `html_start_status.h`, `html_speedtrap_status.h`

### Changed (Repo Structure)
- **Flattened repository** -- All source files moved from `MASS_Trap/` subfolder to repo root. Clone and build directly — no nested directories.
- **Git tags for releases** -- Version history tracked via git tags (e.g., `v2.4.0`) and GitHub Releases instead of version folders.
- **Improved .gitignore** -- Added PlatformIO directories, `*.env` for secrets.

### Technical Notes
- **PlatformIO is the recommended build system.** `platformio.ini` pins all board settings (`board_build.flash_size = 16MB`, `qio_opi` memory type, partition table) — eliminates the class of Arduino IDE misconfiguration bugs where wrong dropdown selections cause flash detection failures.
- All new hardware features (audio, LiDAR, speed trap) are **off by default** and guarded by config flags. Existing two-gate setups work identically to v2.3.0 with no configuration changes needed.
- Custom partition table includes a 64KB coredump partition for crash diagnostics.
- Changing partitions erases LittleFS -- use system snapshot to backup before upgrading from a different partition layout.
- LiDAR sensor uses UART (HardwareSerial) instead of I2C -- no external library required. TF-Luna 9-byte frame protocol with checksum validation and signal strength filtering.
- Audio uses ESP32 built-in I2S driver (`driver/i2s.h`) -- no external library required.
- Only 2 external libraries needed: `WebSockets` and `ArduinoJson` (was 3 in early development -- removed `Adafruit_VL53L0X` dependency).
- Config JSON uses `"lidar"` key (backwards-compatible: reads old `"tof"` key if present).
- Resource budget: PROGMEM ~340KB (of 3MB), LittleFS ~250KB with audio (of ~9.9MB), heap ~130KB free (of 320KB).

---

## [2.3.0] - 2026-02-11

### Added
- **Chart.js Data Visualization** -- Two live-updating charts on the dashboard:
  - Speed vs Run Number (line chart) -- tracks speed progression across races
  - Kinetic Energy vs Weight (scatter plot) -- visualizes KE = 1/2 mv^2 relationship
  - Charts populate from history on page load and update in real time after each race
  - Chart.js v4.4.7 embedded as PROGMEM (~206KB) -- works offline in standalone mode
- **Ghost Car Comparison** -- After each race, shows time delta vs the active car's personal best:
  - Green "NEW PERSONAL BEST!" with negative delta for new records
  - Red "+X.XXXs" for slower runs
  - "FIRST RUN!" indicator for a car's inaugural race
- **Physics Explainer Panel** -- Collapsible "HOW THE MATH WORKS" section with four formula cards:
  - Speed: v = d/t
  - Momentum: p = mv
  - Kinetic Energy: KE = 1/2 mv^2
  - G-Force: a = v/t / 9.8
  - Each formula shows actual values from the last race, substituted live
- **LED Visualizer Bar** -- Animated CSS bar below the state banner mirrors WLED states:
  - Idle: Breathing green glow
  - Armed: Fast-pulsing red (F1 start lights)
  - Racing: Yellow chase effect
  - Finished: Rainbow gradient flow
- **API Authentication** -- Simple `X-API-Key` header check on destructive endpoints:
  - Protected: POST `/api/config`, POST `/api/restore`, POST `/api/reset`, POST/DELETE `/api/files`, DELETE `/api/log`
  - Reuses existing OTA password as the API key
  - Read-only endpoints and dashboard data (garage/history) remain open
  - Config page auto-includes key from OTA password field
  - Console page prompts for key on first destructive action, caches in localStorage
- **WLED Auto-Sleep Timer** -- Turns off WLED after 5 minutes of inactivity
  - Automatically wakes WLED back to idle state on next race activity
  - New functions: `setWLEDOff()`, `checkWLEDTimeout()`, `resetWLEDActivity()`

### Changed
- **WLED Timeout Reduction** -- `setWLEDState()` HTTP timeout reduced from 500ms to 100ms (LAN is fast; don't block race timing). WLED proxy endpoints reduced from 2000ms to 1000ms.
- **Version bump** -- Firmware and Web UI version: 2.2.0 -> 2.3.0

### Fixed
- **XSS Vulnerability** -- Car names rendered via `innerHTML` could execute injected scripts. All user-generated content now uses a safe `setCurrentCarDisplay()` helper with `textContent` and DOM API.

### Technical Notes
- Total PROGMEM flash usage: ~315KB (up from ~94KB in v2.2.0). ESP32-S3 with 8MB flash has ample headroom.
- Chart.js served at `/chart.min.js` with 24-hour cache header for browser caching efficiency.
- `window.onload` converted to async to ensure history is loaded before chart initialization.
- Ghost comparison reads previous best BEFORE `updateGarageStats()` overwrites it (correct sequencing).

---

## [2.2.0] - 2026-02-10

### Added
- Unified firmware -- single codebase runs as start gate OR finish gate (configured via web UI)
- Web-based captive portal configuration on first boot
- ESP-NOW peer-to-peer communication with clock synchronization
- Embedded web UI via PROGMEM -- OTA updates deliver code AND web pages in one shot
- Version tracking: `FIRMWARE_VERSION`, `WEB_UI_VERSION`, `BUILD_DATE`, `BUILD_TIME`
- `/api/version` endpoint for future GitHub update checking
- Role-appropriate web pages -- finish gate serves full dashboard; start gate serves lightweight status page
- Smart peer connection backoff -- ping rate drops from 2s to 10s when peer is disconnected
- Full physics data in CSV log (Run, Car, Weight, Time, Speed, Scale Speed, Momentum, KE)
- WLED integration for visual race state effects (idle, armed, racing, finished)
- Google Sheets auto-upload after each race via webhook
- OTA firmware updates with configurable password
- Backup/restore device configuration as JSON
- Web-based serial console with file browser at `/console`
- Car Garage with persistent database (name, color, weight, per-car stats)
- Race History with last 100 races and full physics data
- CSV export for spreadsheet analysis

### Fixed
- ESP32-S3 compile error (`HWCDC*` to `HardwareSerial*`) -- changed to `Print*` base class
- WiFi mode dropdown defaulting issue in captive portal
- Clock sync spam when peer disconnected
- Start gate serving full dashboard (now has its own lightweight status page)
- Duplicate race history entries (only finish gate records data now)
- Joules column missing from history table display
