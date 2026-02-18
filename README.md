# The M.A.S.S. Trap

### **M**otion **A**nalysis & **S**peed **S**ystem

[![Firmware](https://img.shields.io/badge/firmware-v2.6.0--beta-blue)](https://github.com/Ryan4n6/MASS-Trap/releases/tag/v2.6.0-beta) [![ESP32-S3](https://img.shields.io/badge/ESP32--S3-N16R8-red)](https://www.espressif.com/en/products/socs/esp32-s3) [![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE) [![Live Demo](https://img.shields.io/badge/demo-live-orange)](https://ryan4n6.github.io/MASS-Trap/#demo)

> *"Respect the Laws of Physics."*

**The M.A.S.S. Trap** is a forensic-grade physics laboratory disguised as a Hot Wheels track speedometer. It utilizes commercial LiDAR and enterprise IoT hardware to enforce the laws of **Mass**, **Momentum**, and **Kinetic Energy** on 1:64 scale traffic.

---

## The Case File (Lore)

This project was engineered by a former **Police Detective** and **Digital Forensics Instructor** to bridge the gap between law enforcement precision and childhood wonder.

* **The Name:** A nod to the creator's past life enforcing speed limits -- and his family name, **Mass**feller. It is a literal "Speed Trap" for Hot Wheels.
* **The Legacy:** Inspired by a grandfather who raced **Formula Vee** in the 70s/80s. In Formula Vee, raw horsepower didn't win races; **efficiency** and **momentum conservation** did.
* **The Mission:** To teach the next generation that **Science is Cool**, **Math is Power**, and while you can't break the laws of physics... you can certainly measure them.

---

## 🌐 Live Demo & Documentation

> **[Try the Interactive Demo →](https://ryan4n6.github.io/MASS-Trap/#demo)** — No hardware needed. All 5 themes. Simulated races.

| Page | Description |
|------|-------------|
| [Project Home](https://ryan4n6.github.io/MASS-Trap/) | Interactive demo, build tiers, roadmap |
| [Parent & Teacher Guide](https://ryan4n6.github.io/MASS-Trap/parents.html) | Step-by-step science fair helper for parents |
| [Judge Showcase](https://ryan4n6.github.io/MASS-Trap/judges.html) | Science fair project page for judges |
| [Parts Store](https://ryan4n6.github.io/MASS-Trap/store.html) | Curated parts lists by budget tier |
| [Build Wizard](https://ryan4n6.github.io/MASS-Trap/wizard.html) | Interactive wiring guide |

---

## Quick Start (5 Minutes to First Race)

> **Already have an ESP32-S3 N16R8 and an IR break-beam sensor? You're 5 minutes from your first race.**

```bash
# 1. Clone & flash
git clone https://github.com/Ryan4n6/MASS-Trap.git && cd MASS-Trap
pio run -t upload                    # Flash firmware via USB
pio run -t uploadfs                  # Upload web UI + audio files

# 2. Configure
# Connect to WiFi: "MASSTrap-Setup-XXXX" → browser opens automatically
# Pick role (finish/start/speedtrap), enter your WiFi creds, save

# 3. Race
# Open http://masstrap.local on any device → ARM → release car → data appears
```

**That's it.** One ESP32 as a finish gate gives you timing, speed, momentum, kinetic energy, a leaderboard, 5 themes, and a full physics dashboard served from the chip itself. Add a second ESP32 as a start gate for precision split timing. Add a third as a speed trap for mid-track velocity profiling. All auto-discover each other via ESP-NOW.

**No internet required. No app to install. No account to create.** Just physics.

→ *Need the full parts list?* **[Parts Store](https://ryan4n6.github.io/MASS-Trap/store.html)** — 3 budget tiers from $25 to $120.
→ *Building with your kid?* **[Parent's Wiring Guide](https://ryan4n6.github.io/MASS-Trap/parents-guide.html)** — Ages 8+ with parent supervision.
→ *Science fair?* **[Parent & Teacher Guide](https://ryan4n6.github.io/MASS-Trap/parents.html)** — Variables, hypothesis, and rubric mapping done for you.

---

## "Interceptor" Architecture (Hardware)

Unlike civilian-grade Arduino projects, The M.A.S.S. Trap runs on the **Interceptor Spec** -- a modified, high-performance stack designed for real-time telemetry, heavy data logging, and audio synthesis.

| Component | Spec | Role |
| --- | --- | --- |
| **The Engine** | **ESP32-S3 (N16R8)** | Modified 16MB Flash / 8MB PSRAM. Dual-core 240MHz "Interceptor" Class. |
| **The LiDAR** | **Benewake TF-Luna** | **UART Solid-State LiDAR.** Performs "Tech Inspection" staging and auto-arms the trap when a vehicle is detected. |
| **The Siren** | **MAX98357A I2S** | Digital Audio Amp. Broadcasts race audio effects -- arm chime, go tone, finish fanfare, new record alert. |
| **The Trap** | **Dual IR Break-beam** | Measures mid-track velocity delta to calculate drag coefficients. |
| **The Comms** | **ESP-NOW** | Encrypted, ultra-low latency (<1ms) tactical link between Start and Finish gates. |

---

## Command Center (The Dashboard)

The system hosts its own web app (no internet required), turning any phone, tablet, or laptop into the **M.A.S.S. Trap Command Center**.

* **5 Selectable Themes:** Interceptor (navy+gold default), Classic (Hot Wheels orange), Daytona (NASCAR racing), Case File (police detective), Cyber (terminal green).
* **Real-Time Telemetry:** Instant display of Scale MPH, Actual MPH, Finish Time (ms), Momentum, KE, G-Force.
* **Suspect Tracking:**
  * **"Staged":** LiDAR confirms vehicle presence at the start gate.
  * **"Clocked":** Speed trap sensors capture mid-track velocity.
  * **"Booked":** Finish gate logs the final time and physics data.
* **The "Lead Sled" Leaderboard:** Tracks new records with an animated podium ceremony.
* **Mechanic's Log:** A digital notebook to correlate car modifications (graphite, weight) with performance gains.
* **Chart.js Visualization:** Speed vs Run and KE vs Weight scatter plots, auto-updating after each race.
* **Ghost Car Comparison:** Personal best delta display with new record/slower indicators.
* **Physics Explainer:** Live formula cards showing actual race values.
* **Speed Profile:** Start/mid/finish velocity comparison when speed trap data is available.
* **Kiosk Mode:** `?kiosk` URL parameter or `Ctrl+K` hides controls for science fair display — judges see data only.
* **Dual-Layout Navigation:** Desktop manila folder tabs + mobile bottom thumb bar. Consistent across all pages.

---

## Features

### Race Timing & Physics
- **Microsecond-precision timing** via hardware interrupts on IR break-beam sensors
- **Thread-safe ISR timing** -- spinlock-protected 64-bit timestamps prevent torn reads on dual-core ESP32-S3
- **ESP-NOW peer-to-peer communication** between gates (sub-millisecond latency)
- **Clock synchronization** between devices with drift-filtered logging
- **Automatic race detection** -- arm the system, release the car, results appear instantly
- **Real-time physics calculations:** elapsed time, speed (mph/km/h), scale speed, momentum (kg*m/s), kinetic energy (Joules), G-force
- **Mid-track velocity profiling** via optional speed trap node (demonstrates acceleration/deceleration)
- **Imperial/Metric units** -- configurable display units with WebSocket broadcast

### LiDAR Staging (Benewake TF-Luna)
- **Automatic car staging** -- solid-state LiDAR detects car at start gate
- **Auto-arm** -- car present > 1 second triggers automatic system arming
- **Dashboard indicator** -- live "LIDAR TARGET ACQUIRED" status on Command Center
- **Configurable threshold** -- adjustable detection distance via web UI
- **UART interface** -- 115200 baud, 9-byte frames with checksum validation
- **Signal strength filtering** -- rejects low-confidence readings
- **Fully optional** -- disabled by default, zero overhead when off

### Audio System (MAX98357A I2S)
- **Non-blocking WAV playback** via ESP32 I2S DMA ring buffer
- **Race event sounds** -- arm chime, countdown, go tone, finish fanfare, new record alert
- **Web-based upload** -- drag-and-drop WAV files to device via config page
- **Volume control** -- adjustable 0-21 levels via web UI
- **Fully optional** -- disabled by default, zero overhead when off

### Speed Trap Node (3rd ESP32)
- **Mid-track velocity measurement** -- dual IR sensors ~10cm apart
- **Microsecond ISR timing** -- hardware interrupt on both sensors
- **ESP-NOW integration** -- sends velocity data to finish gate automatically
- **Dedicated status page** -- shows last speed, peer status, sensor config

### Device Configuration
- **Web-based setup** -- captive portal on first boot, no code editing required
- **WiFi or Standalone mode** -- connect to your router, or create its own network
- **Pin configuration** -- all GPIO assignments configurable via web UI
- **Peer discovery** -- automatically find other M.A.S.S. Trap devices on the network
- **WLED integration** -- LED strip effects for race states (idle, armed, racing, finished)
- **OTA updates** -- flash new firmware over WiFi, no USB cable needed
- **Full system snapshot** -- one-click backup/restore of config + garage + history
- **Clone mode** -- restore snapshot to a new device (strips network identity)
- **5 visual themes** -- switch look-and-feel from Interceptor to Hot Wheels Classic, Daytona, Case File, or Cyber
- **Kiosk mode** -- presentation mode for science fairs hides controls, shows data only
- **Imperial/Metric units** -- configurable display units (mph or km/h) with timezone selection

### Evidence System & NFC
- **Case numbers** — Sequential `MASS26-XXXX` format with chain of custody tracking
- **QR-coded evidence tags** — Printable labels with case number, car info, and scannable QR code
- **NFC auto-identification** — NTAG213 stickers on cars auto-select vehicle and arm track when scanned
- **Photo documentation** — Upload evidence photos linked to case numbers via cloud hosting
- **Forensic-grade logging** — Every data point traceable back to exact car, weight, condition, and trial

### 6-Phase Science Fair Lab Manager
- **Guided testing workflow** — Experiment Setup → Vehicle Intake → Evidence Prep → Pre-Flight → Data Collection → Results
- **Test matrix generation** — Locard's Exchange Principle ordering prevents systematic bias
- **Auto-advance** — System prompts operator through each run with audio cues
- **Sanity checks** — Alerts on suspicious times (too fast, too slow, identical runs) with KEEP/RETRY options
- **CSV export** — Raw data and summary tables formatted for science fair rubric requirements
- **Auto-generated lab report** — Complete science fair report with hypothesis, variables, data tables, analysis, conclusion
- **Persistence** — State saved to localStorage + ESP32 at every transition; full recovery on disconnect

### Browser Firmware Update
- **GitHub-direct OTA** — Download and flash firmware updates directly from GitHub releases
- **MD5 verification** — Integrity check before flashing, dual OTA partition safety net
- **TLS secured** — Embedded root CAs for secure HTTPS downloads
- **Update detection** — Dashboard shows breathing red badge when new firmware is available
- **Manual upload fallback** — Drag-and-drop `.bin` upload with progress bar

### Debug Console
- **Web-based serial monitor** -- view device logs over WiFi at `/console`
- **NTP-stamped log lines** -- `[HH:MM:SS.mmm]` wall-clock timestamps (uptime fallback before NTP sync)
- **Ring buffer capture** -- 8KB of recent serial output, auto-refreshing
- **WiFi diagnostics** -- `/api/wifi-status` with RSSI, connection state, and failure reasons
- **File browser** -- inspect, edit, and manage files on the device filesystem
- **Device info** -- IP, uptime, free memory, peer status at a glance

### Architecture
- **Unified firmware** -- single codebase runs as start gate, finish gate, or speed trap
- **Role-appropriate UI** -- finish gate serves full dashboard; start gate and speed trap serve lightweight status pages
- **LittleFS-first web serving** -- pages served from filesystem with PROGMEM fallback (no upload needed, but LittleFS files take priority when present)
- **Custom 16MB partition** -- 3MB app (with OTA) + ~9.9MB LittleFS for data/audio + 64KB coredump
- **Graceful degradation** -- audio, LiDAR, and speed trap are optional; existing gates work without them
- **Reliable captive portal** -- OS-specific handlers for iOS, Android, and Windows CNA detection

---

## Deployment Protocols

### 1. Hardware Prep

- **Target Board:** ESP32-S3 Dev Module (Enable `USB CDC On Boot`)
- **Flash Size:** Select **16MB (128Mb)**
- **PSRAM:** Select **OPI PSRAM**

### 2. Partitioning (Critical)

The "Interceptor" requires a custom memory map to fit the audio assets and logs.

The `partitions.csv` in the project root defines: **3MB app (with OTA) + ~9.9MB LittleFS + 64KB coredump**.

- **PlatformIO:** Handled automatically via `platformio.ini`
- **Arduino IDE:** Place `partitions.csv` in the sketch folder; select Flash Size **16MB (128Mb)**

### 3. Prerequisites

**PlatformIO (Recommended)**
1. Install [PlatformIO Core](https://platformio.org/install/cli) (Python 3.10+)
2. Clone this repo and run `pio run` — all dependencies install automatically

**Arduino IDE**
1. **Arduino IDE 2.x**
2. **ESP32 Board Package** — Add `https://espressif.github.io/arduino-esp32/package_esp32_index.json` to Board Manager URLs
3. **Required Libraries** (install via Library Manager):
   - `WebSockets` by Markus Sattler
   - `ArduinoJson` by Benoit Blanchon

> No external library needed for the TF-Luna LiDAR — it uses the built-in HardwareSerial UART driver.

### 4. Wiring

**IR Sensor (Start / Finish Gate)**
```
IR Sensor Signal  ->  GPIO 4 (default, configurable)
IR Sensor VCC     ->  5V / 3.3V (check your sensor)
IR Sensor GND     ->  GND
Status LED        ->  GPIO 48 (NeoPixel on ESP32-S3 DevKit)
```

**Benewake TF-Luna LiDAR (optional)**
```
VCC  ->  5V
GND  ->  GND
TX   ->  ESP32 GPIO 39 (RX) (default, configurable)
RX   ->  ESP32 GPIO 38 (TX) (default, configurable)
```
*Note: The TF-Luna runs in UART mode at 115200 baud.*

**MAX98357A I2S Amplifier (optional)**
```
BCLK  ->  GPIO 15 (default, configurable)
LRC   ->  GPIO 16 (default, configurable)
DIN   ->  GPIO 17 (default, configurable)
VIN   ->  5V
GND   ->  GND
```

**Speed Trap Node (dual IR sensors)**
```
Sensor 1 Signal  ->  GPIO 4 (default, configurable)
Sensor 2 Signal  ->  GPIO 5 (default, configurable)
Sensor spacing: ~10cm apart on track
```

### 5. Flash & Race

1. Clone this repository:
   ```bash
   git clone https://github.com/Ryan4n6/MASS-Trap.git
   cd MASS-Trap
   ```
2. **PlatformIO (Recommended):**
   ```bash
   pio run -t upload          # Build + flash via USB
   pio run -t uploadfs        # Upload LittleFS data files (audio, etc.)
   pio run -t monitor         # Serial monitor
   ```
   **Arduino IDE:**
   Open `MASS_Trap.ino`, set board to ESP32S3 Dev Module, Flash Size 16MB, PSRAM OPI, then Upload.

3. After flashing, connect to WiFi SSID: `MASSTrap-Setup-XXXX`
4. Configure role, WiFi, pins via the captive portal at `http://192.168.4.1`
5. Access the Command Center at `http://masstrap.local`
6. **Respect the laws of physics.**

### OTA Updates (After Initial Flash)

Once configured, you never need a USB cable again:

**PlatformIO:**
```bash
pio run -e ota -t upload     # Flash over WiFi
```

**Arduino IDE:**
Go to **Tools → Port**, select the network port (`masstrap.local`), and click Upload.

Web pages update automatically — they're embedded in the firmware.

The OTA password defaults to `admin` — change it in the config page for security.

---

## Web Pages

| URL | Page | Description |
|-----|------|-------------|
| `/` | Command Center | Live race data, garage, physics (finish gate) or status page (start/speed trap) |
| `/history.html` | Evidence Log | Race history with full physics data |
| `/config` | System Config | WiFi, pins, peer, track, audio, LiDAR, WLED, OTA settings |
| `/console` | Debug Console | Timestamped serial log viewer, file browser, device info |
| `/css.html` | CSS Reference Map | Live visual component reference for all 5 themes |
| `/about.html` | The Special K Report™ | Project stats, builders, live device status, commit timeline |

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/info` | GET | Device info (role, IP, uptime, heap, peer status) |
| `/api/wifi-status` | GET | WiFi diagnostics (RSSI, mode, failure reason) |
| `/api/version` | GET | Firmware version, build date, board type |
| `/api/config` | GET/POST | Read or write device configuration |
| `/api/garage` | GET/POST | Read or write car garage data |
| `/api/history` | GET/POST | Read or write race history |
| `/api/scan` | GET | Scan for WiFi networks |
| `/api/mac` | GET | Get device MAC address |
| `/api/peers` | GET | List discovered peer devices |
| `/api/log` | GET/DELETE | Read or clear serial log buffer |
| `/api/files` | GET/POST/DELETE | File browser (list, read, write, delete) |
| `/api/system/backup` | GET | Full system snapshot (config + garage + history) |
| `/api/system/restore` | POST | Restore system snapshot (with optional clone mode) |
| `/api/lidar/status` | GET | Live LiDAR readout (state, distance, threshold) |
| `/api/audio/list` | GET | List audio files on device |
| `/api/audio/upload` | POST | Upload WAV file to device |
| `/api/audio/test` | POST | Play a test sound |
| `/api/wled/info` | GET | Proxy: get WLED controller info |
| `/api/wled/effects` | GET | Proxy: list WLED effects |
| `/api/backup` | GET | Legacy single-config backup |
| `/api/restore` | POST | Legacy single-config restore |
| `/api/firmware/status` | GET | Check for firmware updates against GitHub releases |
| `/api/firmware/update-from-url` | POST | Download and flash firmware from URL |
| `/api/firmware/upload` | POST | Upload firmware binary for manual OTA update |
| `/api/diagnostics` | GET | Hardware diagnostic scan (IR, LiDAR, audio, ESP-NOW, WiFi) |
| `/api/reset` | POST | Factory reset (deletes config, reboots) |

## Project Structure

```
MASS-Trap/
├── platformio.ini             # PlatformIO build configuration (recommended)
├── partitions.csv             # Custom 16MB partition table (3MB OTA + 9.9MB LittleFS + 64KB coredump)
├── MASS_Trap.ino              # Main entry point: WiFi, NTP, OTA, boot logic
├── config.h / .cpp            # Configuration struct, named constants, JSON persistence
├── web_server.h / .cpp        # HTTP routes, WebSocket, API handlers, SerialTee ring buffer
├── espnow_comm.h / .cpp       # ESP-NOW protocol: 14 message types, discovery, clock sync
├── finish_gate.h / .cpp       # Finish gate: spinlock-protected timing, race results, physics
├── start_gate.h / .cpp        # Start gate: IR trigger, LiDAR auto-arm
├── speed_trap.h / .cpp        # Speed trap: dual ISR velocity measurement, ESP-NOW send
├── lidar_sensor.h / .cpp      # TF-Luna UART: frame parsing, presence state machine
├── audio_manager.h / .cpp     # MAX98357A I2S: WAV loading, non-blocking DMA playback
├── wled_integration.h / .cpp  # WLED HTTP API: effect control, auto-sleep
├── html_*.h                   # PROGMEM fallback pages (index, config, console, start, speedtrap, chartjs)
├── push_ui.sh                 # Convert data/*.html to PROGMEM html_*.h headers
├── generate_stats.sh          # Auto-regenerate docs/stats.json from live git data
├── kristina.sh                # Generate The Special K Report (terminal, JSON, HTML modes)
│
├── data/                      # LittleFS files (uploaded via pio run -t uploadfs)
│   ├── dashboard.html         # Command Center — 6-phase lab manager, evidence, all features (~185KB)
│   ├── history.html           # Evidence Log — race history with full physics data
│   ├── system.html            # System Config — WiFi, pins, peers, track, audio, LiDAR, WLED
│   ├── about.html             # The Special K Report™ — project stats, builders, live API status
│   ├── science_fair_report.html  # Auto-generated forensic lab report from experiment data
│   ├── main.js                # Shared JavaScript utilities
│   ├── style.css              # Shared stylesheet (5 themes, dual-layout nav)
│   ├── console.html           # Debug console with NTP-timestamped serial log
│   ├── css.html               # CSS component reference map (all themes, live preview)
│   ├── start_status.html      # Start gate lightweight status page
│   ├── speedtrap_status.html  # Speed trap lightweight status page
│   └── *.wav                  # Audio effect files (8-bit, 16kHz mono)
│
├── docs/                      # GitHub Pages site (https://ryan4n6.github.io/MASS-Trap/)
│   ├── index.html             # Landing page with live interactive dashboard demo
│   ├── wizard.html            # Build Wizard — interactive wiring guide, 3-tier telemetry
│   ├── parents.html           # Parent & Teacher Guide — science fair helper
│   ├── parents-guide.html     # Parent's Wiring Guide — terminal block migration
│   ├── judges.html            # Judge Showcase — science fair project page
│   ├── store.html             # Curated parts store by budget tier
│   ├── stats.js               # Shared auto-populator (data-stat attributes from stats.json)
│   └── stats.json             # Centralized project metrics (auto-generated)
│
├── BACKLOG_PLANS.md           # 14 backlog items with full implementation designs
├── MESH_AUTONOMY_DESIGN.md    # "10-Code" distributed ESP-NOW protocol upgrade design
├── DAYTONA_THEME_BRIEF.md     # Daytona NASCAR theme design specification
├── DAYTONA_NARRATIVE.md       # Personal essay on the Daytona heritage
├── HARDWARE_CATALOG.md        # Hardware inventory reference
├── CHANGELOG.md               # Detailed release notes (Keep a Changelog format)
├── README.md
└── .gitignore
```

## Data Persistence

| File | Storage | Survives OTA? | Purpose |
|------|---------|---------------|---------|
| Web pages | LittleFS + PROGMEM fallback | LittleFS: yes, PROGMEM: updated with firmware | Dashboard, config, console, history UI |
| `/config.json` | LittleFS | Yes | Device configuration (incl. units, timezone) |
| `/garage.json` | LittleFS | Yes | Car database with mechanic's notes |
| `/history.json` | LittleFS | Yes | Race history (last 100) |
| `/runs.csv` | LittleFS | Yes | Race log with full physics data |
| `/*.wav` | LittleFS | Yes | Audio effect files |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Can't find device | Check `http://masstrap.local` or find the IP in your router's DHCP table |
| Peer not connecting | Verify MAC addresses match on both devices (check Peer tab in config) |
| Timing seems wrong | Run clock sync from dashboard, check track length setting |
| OTA upload fails | Verify OTA password matches, ensure device is on same network |
| Firmware too large | Ensure Flash Size is set to 16MB -- the custom partitions.csv gives 3MB per app slot |
| No LiDAR readings | Enable LiDAR in config, verify UART pins (TX/RX), check 5V power to TF-Luna |
| No audio output | Enable audio in config, verify I2S pins, upload WAV files |
| Speed trap no data | Verify speed trap node is connected (check peer status), check sensor spacing |
| Captive portal won't open | Forget the WiFi network and reconnect — v2.5.0 adds OS-specific CNA handlers |
| WiFi connection failing | Check `/api/wifi-status` for diagnostic details (RSSI, failure reason) |

## Roadmap

### Planned
- [ ] **Hub Scoreboard Device** -- Waveshare ESP32 display as the central data authority with SD card storage
- [ ] **Multi-Lane Support** -- Multiple finish sensors for parallel lane timing
- [ ] **Tournament Bracket Mode** -- Head-to-head elimination bracket with automatic advancement

### Completed (v2.6.0-beta)
- [x] **NFC Car Tagging** -- NTAG213 stickers auto-select car and arm track on scan
- [x] **6-Phase Science Fair Lab Manager** -- Guided forensic testing workflow with test matrix generation, auto-advance, and sanity checks
- [x] **Browser Firmware Update** -- GitHub release detection, MD5-verified OTA, breathing badge notification
- [x] **Evidence System** — Case numbers, QR tags, photo documentation, chain of custody
- [x] **Science Fair Report Generator** — Auto-generated forensic lab report from experiment data
- [x] **GitHub Pages Site** — Interactive demo, parent guide, judge showcase, parts store, build wizard
- [x] **Community Feedback (Giscus)** — GitHub Discussions-powered comments and reactions on all pages
- [x] **Google Analytics** — GA4 tracking across all GitHub Pages
- [x] **XSS Hardening & CSP** — Quote-aware escHtml(), Content-Security-Policy meta tags on all pages, API key hygiene

### Completed (v2.5.0)
- [x] **Theme Engine** -- 5 selectable themes (Interceptor, Classic, Daytona, Case File, Cyber) with localStorage persistence
- [x] **Dual-Layout Navigation** -- Desktop manila folder tabs + mobile bottom thumb bar across all pages
- [x] **Kiosk Mode** -- Science fair presentation mode via `?kiosk` or `Ctrl+K` (hides controls, shows data only)
- [x] **Modular Web UI** -- LittleFS-first serving with PROGMEM fallback; new dashboard, history, and system pages
- [x] **Thread-Safe Timing** -- Spinlock protection for all 64-bit ISR timing variables across dual-core ESP32-S3
- [x] **NTP Timestamps** -- Wall-clock time in serial log ring buffer with timezone support
- [x] **Captive Portal Fix** -- OS-specific handlers for iOS/Android/Windows CNA detection
- [x] **Regional Settings** -- Imperial/metric units and configurable timezone
- [x] **WiFi Diagnostics** -- `/api/wifi-status` endpoint, RSSI logging, human-readable failure reasons
- [x] **Peer Hotlinks** -- Clickable `hostname.local` links for peer devices in all status pages
- [x] **Named Constants** -- 20+ magic numbers extracted to `#define` constants
- [x] **Dead Code Cleanup** -- Removed unused functions from lidar, WLED, and ESP-NOW modules

### Completed (v2.4.0)
- [x] **M.A.S.S. Trap Rebrand** -- Full project rebrand with police shield/badge themed Command Center
- [x] **Custom 16MB Partition Table** -- 3MB app (with OTA) + 10MB LittleFS for audio and data
- [x] **Full System Snapshot** -- One-click backup/restore of config + garage + history with clone mode
- [x] **TF-Luna LiDAR** -- UART solid-state LiDAR for car staging detection and auto-arm
- [x] **Audio System** -- MAX98357A I2S amplifier with non-blocking WAV playback via DMA
- [x] **Speed Trap Node** -- 3rd ESP32 role with dual IR sensors for mid-track velocity measurement
- [x] **Leaderboard Podium Overlay** -- Animated ranking display after each race
- [x] **Mechanic's Log** -- Per-car notes with timestamps for tracking modifications
- [x] **Speed Profile** -- Start/mid/finish velocity comparison when speed trap data available

### Completed (v2.3.0)
- [x] Chart.js Data Visualization, Ghost Car Comparison, Physics Explainer Panel
- [x] LED Visualizer Bar, API Authentication, WLED Auto-Sleep, XSS Protection

### Completed (v2.2.0)
- [x] Unified firmware, Captive portal config, ESP-NOW, Embedded web UI
- [x] WLED integration, Google Sheets, OTA, Backup/restore, Web console

## Design Documents

| Document | Purpose |
|----------|---------|
| [CHANGELOG.md](CHANGELOG.md) | Detailed release notes for every version (Keep a Changelog format) |
| [BACKLOG_PLANS.md](BACKLOG_PLANS.md) | 15 backlog items with full implementation designs — security, mesh networking, fleet updates |
| [MESH_AUTONOMY_DESIGN.md](MESH_AUTONOMY_DESIGN.md) | "10-Code" distributed ESP-NOW protocol — removes finish gate as single authority |
| [DAYTONA_THEME_BRIEF.md](DAYTONA_THEME_BRIEF.md) | NASCAR-inspired theme design spec — typography, colors, personal easter eggs |
| [HARDWARE_CATALOG.md](HARDWARE_CATALOG.md) | Complete hardware inventory with ASINs, costs, and role assignments |
| [TECH_ASSESSMENT.md](TECH_ASSESSMENT.md) | Honest architecture review, tech stack recommendations, and the Human/AI Magna Carta |

## License

MIT License -- use it, modify it, teach with it.

---

### Dedication

*Built for my sons. May you always find the thrill in the data.*

*In memory of Richard Massfeller — General Contractor, Formula Vee racer, and the original builder. He built a 7ft pencil for a science fair. We built this.*

*In memory of Sam Troia and Stephen "Beaver" Massfeller — the uncles who shaped who we are.*

---

🏠 [Project Site](https://ryan4n6.github.io/MASS-Trap/) · 📦 [GitHub](https://github.com/Ryan4n6/MASS-Trap) · 📥 [Releases](https://github.com/Ryan4n6/MASS-Trap/releases) · 🛒 [Parts Store](https://ryan4n6.github.io/MASS-Trap/store.html)

Firmware assistance by Claude (Anthropic).
