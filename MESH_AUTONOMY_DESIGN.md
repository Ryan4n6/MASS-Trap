# M.A.S.S. Trap — Mesh Autonomy Design Document

## "10-Code" ESP-NOW Protocol Upgrade

### Vision

Inspired by police radio operations and HAM/Meshtastic mesh networking:
nodes communicate like cops on the radio — compact status codes, situational
awareness built passively by listening, mutual aid when a brother is stressed,
and coordinated operations across the fleet.

Currently beacons are "I'm alive" pings (identity + timestamp only). The peers
UI is a legacy manual-MAC-entry screen with a scan button bolted on. Neither
reflects the reality that auto-discovery already handles pairing — the UI should
show the squad, not a search tool.

---

## Current State (What We Have)

### Beacon Protocol
- **ESPMessage struct**: 64 bytes — `type`, `senderId`, `timestamp`, `offset`, `role[16]`, `hostname[32]`
- **Beacon cycle**: Every 3s broadcast to `FF:FF:FF:FF:FF:FF`
- **Auto-pairing**: Hear beacon → check role compatibility → MSG_PAIR_REQ → MSG_PAIR_ACK → persisted
- **Payload**: Identity only (senderId, role, hostname). No status data.

### Peer Registry
- **KnownPeer struct**: MAC, role, hostname, deviceId, lastSeen, espnowRegistered, paired
- **Thresholds**: ONLINE <15s, STALE <60s, OFFLINE >60s
- **Persistence**: Only paired peers saved to `/peers.json`
- **Capacity**: MAX_PEERS = 8

### Peers UI (data/system.html)
- Manual MAC entry field (legacy, pre-dates auto-discovery)
- "Scan for Devices" button → fetches `/api/peers` → flat list
- No live status indicators (online/stale/offline)
- No auto-refresh
- No firmware version, signal, or health display

### Key Files
| File | Key Lines | What's There |
|------|-----------|--------------|
| `espnow_comm.h:31-38` | ESPMessage struct (64 bytes) |
| `espnow_comm.h:55-71` | KnownPeer struct, PeerStatus enum |
| `espnow_comm.cpp:360-385` | Beacon receive handler |
| `espnow_comm.cpp:576-602` | discoveryLoop() — broadcast + health check |
| `config.h:47-57` | Timing constants (BEACON=3s, ONLINE=15s, etc.) |
| `system.html:167-181` | Peer tab HTML (manual MAC entry) |
| `system.html:563-586` | discoverDevices() JS |

---

## Phase 1: Squad Awareness (UI + Enriched Beacons)

**Goal**: Every node passively knows its brothers' status. The UI shows the
squad roster, not a search tool. Scan becomes a troubleshooting action.

### 1A. Enrich Beacon Payload

The `offset` field (int64_t, currently unused in beacons) can carry a packed
status word. No struct changes needed — just encode/decode the 8 bytes:

```
Byte layout of offset field in MSG_BEACON / MSG_BEACON_ACK:
  Bits 0-7:   Race state (IDLE=0, ARMED=1, RACING=2, FINISHED=3)
  Bits 8-15:  WiFi RSSI (signed, -127 to 0 dBm, stored as uint8_t + 128)
  Bits 16-31: Free heap in KB (uint16_t, max 65535 KB = 64MB, plenty)
  Bits 32-47: Uptime in minutes (uint16_t, max 65535 min = ~45 days)
  Bits 48-55: Firmware version packed (major<<4 | minor) — enough for v15.15
  Bits 56-63: Flags byte:
              bit 0: audio enabled
              bit 1: lidar enabled
              bit 2: wled enabled
              bit 3: speedtrap paired
              bit 4: start gate paired
              bit 5: finish gate paired
              bit 6: has update available
              bit 7: reserved
```

**Total: 64 bits = 8 bytes.** Fits perfectly in the existing `int64_t offset`
field. Zero struct changes, zero protocol version bump, backward compatible
(old firmware sees offset as a large number and ignores it).

### 1B. Update KnownPeer Struct

Add decoded status fields to KnownPeer:

```cpp
struct KnownPeer {
  // Existing fields (unchanged)
  uint8_t mac[6];
  char role[16];
  char hostname[32];
  uint8_t deviceId;
  unsigned long lastSeen;
  bool espnowRegistered;
  bool paired;

  // New: decoded from beacon offset
  uint8_t raceState;       // IDLE/ARMED/RACING/FINISHED
  int8_t wifiRSSI;         // dBm (-127 to 0)
  uint16_t freeHeapKB;     // Free heap in KB
  uint16_t uptimeMin;      // Uptime in minutes
  uint8_t fwMajor;         // Firmware major version
  uint8_t fwMinor;         // Firmware minor version
  uint8_t flags;           // Capability/status flags
};
```

### 1C. Update `/api/peers` JSON Response

```json
[
  {
    "mac": "AA:BB:CC:DD:EE:FF",
    "role": "start",
    "hostname": "masstrap-start",
    "id": 2,
    "paired": true,
    "status": "online",
    "lastSeen": 3,
    "state": "IDLE",
    "rssi": -42,
    "heapKB": 180,
    "uptimeMin": 1440,
    "firmware": "2.5.0",
    "audio": false,
    "lidar": true,
    "wled": false,
    "updateAvailable": false
  }
]
```

### 1D. Peers Tab UI Overhaul

**Remove:**
- Manual MAC entry field (`peerMac` input)
- "Give this MAC to your partner" hint
- Flat device list

**Replace with:**

**Squad Roster** (always visible, auto-refreshing every 5s):
```
┌─────────────────────────────────────────────┐
│  ★ SQUAD ROSTER                             │
├─────────────────────────────────────────────┤
│  🟢 START GATE — masstrap-start             │
│     FW v2.5.0 · IDLE · RSSI -42 · 24h up   │
│     [Open Dashboard ↗]                      │
│                                             │
│  🟢 SPEEDTRAP — masstrap-speed              │
│     FW v2.4.0 ⚠ · IDLE · RSSI -58 · 2h up  │
│     [Open Dashboard ↗]                      │
│                                             │
│  🔴 WLED — (not an ESP-NOW brother)         │
│     Separate integration · 192.168.1.159    │
├─────────────────────────────────────────────┤
│  This Device: FINISH GATE — masstrap-finish │
│  MAC: AA:BB:CC:DD:EE:FF · FW v2.5.0        │
│  Uptime: 3 days · Heap: 180KB free          │
├─────────────────────────────────────────────┤
│  ▸ Troubleshooting (collapsed)              │
│    [Roll Call] [Force Scan] [Unpair All]    │
│    Raw peer registry table...               │
└─────────────────────────────────────────────┘
```

**Status indicators:**
- 🟢 Green dot = ONLINE (heard within 15s)
- 🟡 Yellow dot = STALE (heard within 60s)
- 🔴 Red dot = OFFLINE (>60s since last heard)
- ⚠ next to firmware version = running older version than this device

**Auto-refresh**: Poll `/api/peers` every 5 seconds (matches PEER_HEALTH_CHECK_MS).
Use WebSocket if already connected, fall back to polling.

### 1E. Roll Call

New button in troubleshooting section. Sends a `MSG_PING` to all known peers.
Each peer responds with `MSG_PONG`. UI shows results:

```
Roll Call Results:
  ✓ masstrap-start responded in 4ms
  ✓ masstrap-speed responded in 12ms
  ✗ masstrap-test — no response (3s timeout)
```

Firmware side: `MSG_PONG` handler already exists. Just need a `/api/peers/rollcall`
endpoint that triggers pings and collects responses with round-trip time.

---

## Phase 2: 10-Code Protocol (Mesh Intelligence)

**Goal**: Nodes coordinate operations via compact status codes. Config changes
propagate. Fleet updates flow through the mesh.

### 2A. 10-Code Status Messages

New message types (extend existing MSG_* enum):

| Code | Name | Meaning | Payload (offset field) |
|------|------|---------|----------------------|
| 14 | MSG_STATUS_10_8 | In service (ready) | Status word (same as beacon) |
| 15 | MSG_STATUS_10_7 | Out of service (shutting down) | Reason code |
| 16 | MSG_STATUS_10_42 | End of tour (coordinated shutdown) | ETA in seconds |
| 17 | MSG_CONFIG_PUSH | Config update broadcast | Config key + value |
| 18 | MSG_CONFIG_ACK | Config received | Echo key |
| 19 | MSG_UPDATE_AVAIL | New firmware available | Version packed |
| 20 | MSG_UPDATE_PULL | Request firmware binary | Offset (for chunked transfer) |
| 21 | MSG_UPDATE_CHUNK | Firmware data chunk | Chunk data |

### 2B. Coordinated Shutdown (10-42)

When a node is powering down (or user hits a "Shut Down" button):

1. Node broadcasts `MSG_STATUS_10_42` to all brothers
2. Brothers acknowledge (stop sending to this node)
3. Node flushes pending data (logs, CSV)
4. Node sends final `MSG_STATUS_10_7` (out of service)
5. Node enters deep sleep or halts

Brothers update their roster: "masstrap-start is 10-42 (end of tour)"

### 2C. Auto-Config Propagation

When finish gate changes track length, units, or scale factor:

1. Finish broadcasts `MSG_CONFIG_PUSH` with key-value pair
2. Start/speedtrap receive, validate (is this a config I care about?)
3. If relevant: apply to local config, save, send `MSG_CONFIG_ACK`
4. Finish UI shows: "Track length updated on 2/2 brothers"

**Config keys that propagate:**
- `track_length` — all nodes need this for speed calculations
- `units` — imperial/metric display preference
- `scale_factor` — 1:64, 1:43, etc.
- `timezone` — NTP display

**Config keys that DON'T propagate (node-specific):**
- `role`, `hostname`, `device_id` — identity
- `wled_host`, `wled_effect_*` — finish gate only
- `wifi_ssid`, `wifi_pass` — security (use FNG module instead)
- `ota_password` — security

### 2D. Fleet Firmware Update (LAN Distribution)

See existing design in MEMORY.md backlog. Summary:
1. One node (finish gate) downloads `.bin` from GitHub, caches in PSRAM (8MB)
2. Broadcasts `MSG_UPDATE_AVAIL` with new version to brothers
3. Brothers request chunks via `MSG_UPDATE_PULL`
4. Finish gate streams firmware via ESP-NOW (250-byte chunks) or HTTP
5. HTTP is faster: brother hits `http://finish-ip/api/firmware/serve`
6. Verify MD5, write to OTA partition, reboot

ESP-NOW max payload is 250 bytes — firmware is ~1.7MB = ~6800 chunks.
At 3ms per chunk that's ~20 seconds. HTTP over WiFi would be ~5 seconds.
**Recommendation: Use HTTP for bulk transfer, ESP-NOW for coordination only.**

---

## Phase 3: Mutual Aid (HAM-Inspired Mesh Resilience)

**Goal**: Nodes actively help each other. Store-and-forward for reliability.
Load shedding under stress. Multi-hop for range extension.

### 3A. Load Shedding / Backup

During a race, the finish gate is the busiest node (ISR timing, physics calcs,
WebSocket broadcast, WLED commands, CSV logging). The start gate is idle after
sending MSG_START.

**Offloadable tasks:**
- WLED state changes (start gate could send HTTP to WLED directly)
- CSV log backup (start gate stores duplicate race data)
- WebSocket relay (if a client is connected to start gate's IP)

**Implementation**: Finish gate includes a "load" metric in beacons. If load >
threshold, it sets a BACKUP_REQUESTED flag. Start gate sees flag, activates
backup mode for specific tasks.

### 3B. Store-and-Forward

ESP-NOW is fire-and-forget — no delivery guarantee. For critical messages
(MSG_START, MSG_SPEED_DATA), add a simple retry queue:

```cpp
struct PendingMessage {
  ESPMessage msg;
  uint8_t destMac[6];
  uint8_t retries;       // Max 3
  unsigned long sentAt;  // millis() of last attempt
  bool acked;
};

#define MAX_PENDING 8
PendingMessage pendingQueue[MAX_PENDING];
```

On send: push to queue. On ACK: mark acked. Every 100ms: retry unacked
messages up to 3 times. After 3 failures: log error, alert UI.

**Only for critical messages** — beacons don't need guaranteed delivery.

### 3C. Multi-Hop Relay

If a 4th+ node is added (e.g., remote display, timing tower, pit lane sensor):
- Nodes can relay messages for peers they can't directly reach
- Each ESPMessage gets a TTL field (use 1 bit of flags, max 2 hops)
- Relay logic: if I receive a message not addressed to me AND TTL > 0,
  decrement TTL and rebroadcast

**When needed**: Only matters for physical setups where nodes are >200m apart
(ESP-NOW range limit). Current Hot Wheels track setups are <10m. This is
future-proofing for outdoor events or multi-room setups.

### 3D. Mesh Health Dashboard

A dedicated page (or section of the peers tab) showing:

```
┌─────────────────────────────────────────────┐
│  MESH TOPOLOGY                              │
│                                             │
│   [START] ←──ESP-NOW──→ [FINISH]            │
│      │                     │  ↕              │
│      ×                  [SPEEDTRAP]          │
│  (not paired)              │                │
│                          [WLED]              │
│                        (HTTP only)           │
│                                             │
│  Link Quality:                              │
│    START↔FINISH:  -42 dBm ████████░░ 84%    │
│    FINISH↔SPEED:  -58 dBm █████░░░░░ 52%   │
│                                             │
│  Fleet Health:                              │
│    Total heap: 540KB / 720KB (75%)          │
│    Firmware: 2/3 on v2.5.0, 1 outdated     │
│    Uptime: all >1hr                         │
└─────────────────────────────────────────────┘
```

---

## Implementation Priority

| Item | Effort | Impact | Dependencies |
|------|--------|--------|-------------|
| **1A** Enrich beacon offset | Small (encode/decode) | High | None |
| **1B** Update KnownPeer struct | Small | High | 1A |
| **1C** Update /api/peers JSON | Small | High | 1B |
| **1D** Peers tab UI overhaul | Medium | High | 1C |
| **1E** Roll Call | Small | Medium | None |
| **2A** 10-Code messages | Medium | Medium | 1A |
| **2B** Coordinated shutdown | Small | Low | 2A |
| **2C** Config propagation | Medium | High | 2A |
| **2D** Fleet firmware update | Large | High | Firmware update (done) |
| **3A** Load shedding | Medium | Low | 2A |
| **3B** Store-and-forward | Medium | Medium | None |
| **3C** Multi-hop relay | Large | Low | 3B |
| **3D** Mesh health dashboard | Medium | Medium | 1A-1D |

**Recommended order**: 1A → 1B → 1C → 1D → 1E → 2C → 2D → 2A → 3B → 3D

---

## Constraints & Notes

- ESPMessage struct is 64 bytes — CANNOT grow without breaking protocol compat
  with devices running older firmware. All new data must fit in existing fields.
- ESP-NOW max payload: 250 bytes (enough for ESPMessage at 64 bytes)
- ESP-NOW max peers: 20 registered (ESP-IDF limit, we cap at MAX_PEERS=8)
- Beacon broadcast is to FF:FF:FF:FF:FF:FF (all), not peer-specific
- Auto-pairing is already automatic — Phase 1 is mostly UI + beacon enrichment
- Ben (10yo) is the primary user — UI must be immediately understandable
- "Brother" terminology preferred over "peer" (police radio theme)
- All JS must be ES5 (var, not let/const) for embedded browser compatibility
- User is a licensed HAM (KI-?????) and Meshtastic enthusiast — mesh concepts
  are familiar, store-and-forward and relay are natural mental models

---

## Open Questions

1. Should the beacon offset encoding be versioned? (e.g., first byte = schema
   version, so future firmware can decode correctly even if layout changes)
2. Config propagation: should it require explicit "accept" on receiving node,
   or auto-apply? Previous session noted "map not a destination" philosophy
   for restored peer lists — same principle may apply to pushed configs.
3. Fleet update: ESP-NOW chunked transfer vs HTTP pull from LAN cache —
   HTTP is faster but requires WiFi connectivity. ESP-NOW works even without
   WiFi (AP_STA mode). Support both?
4. Should WLED be treated as a "brother" in the mesh topology? It's HTTP-only,
   not ESP-NOW, but it's part of the fleet. Maybe a different category:
   "auxiliary" vs "brother."
