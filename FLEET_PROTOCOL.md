# M.A.S.S. Trap — Fleet Protocol Reference

> Everything a future-us needs to know about how these nodes talk to each other.

## ESP-NOW Message Types (0-19)

| Type | Name | Direction | Size | Purpose |
|------|------|-----------|------|---------|
| 0 | `MSG_PING` | Any → Any | 56B | Keepalive |
| 1 | `MSG_START` | Start → Finish | 56B | Race start trigger (with µs timestamp) |
| 2 | `MSG_CONFIRM` | Finish → Start | 56B | Start signal acknowledged |
| 3 | `MSG_PONG` | Any → Any | 56B | Keepalive reply |
| 4 | `MSG_SYNC_REQ` | Finish → Start | 56B | Request clock sync |
| 5 | `MSG_OFFSET` | Start → Finish | 56B | Clock offset response |
| 6 | `MSG_ARM_CMD` | Finish → Start | 56B | Arm the track |
| 7 | `MSG_DISARM_CMD` | Finish → Start | 56B | Disarm the track |
| 8 | `MSG_BEACON` | Broadcast | 56B | "I'm here" heartbeat (every 2s, with diagnostics) |
| 9 | `MSG_BEACON_ACK` | Direct reply | 56B | Beacon acknowledgment (with diagnostics) |
| 10 | `MSG_SPEED_DATA` | Speedtrap → Finish | 56B | Mid-track velocity |
| 11 | `MSG_SPEED_ACK` | Finish → Speedtrap | 56B | Speed data acknowledged |
| 12 | `MSG_PAIR_REQ` | Any → Compatible | 56B | Pairing request |
| 13 | `MSG_PAIR_ACK` | Reply | 56B | Pairing confirmed |
| 14 | `MSG_TELEM_HEADER` | XIAO → Finish | ~26B | IMU run metadata |
| 15 | `MSG_TELEM_CHUNK` | XIAO → Finish | 232B | IMU data chunk (14 samples) |
| 16 | `MSG_TELEM_END` | XIAO → Finish | 10B | End marker + CRC16 |
| 17 | `MSG_TELEM_ACK` | Finish → XIAO | 56B | Telemetry received OK |
| 18 | `MSG_REMOTE_CMD` | Finish → Peer | 24B | Remote command (reboot, identify, etc.) |
| 19 | `MSG_WIFI_CONFIG` | Finish → Peer | 116B | Push WiFi credentials |

## Beacon Diagnostics — Bit-Packing Format

Every beacon and beacon ACK carries live node diagnostics in the `offset` field (int64_t, 8 bytes) at zero additional radio cost. Previously this field was always `0` for beacons.

```
Bit 63                                    Bit 0
┌──────────┬──────────┬─────┬──────┬──────┬──────┐
│ uptime   │ heapKB   │rssi │state │fwMaj │fwMin │
│ (16 bit) │ (16 bit) │(8b) │ (8b) │ (8b) │ (8b) │
└──────────┴──────────┴─────┴──────┴──────┴──────┘
```

| Field | Bits | Range | Encoding |
|-------|------|-------|----------|
| `uptimeMinutes` | 63-48 | 0-65535 min (~45 days) | Raw minutes |
| `freeHeapKB` | 47-32 | 0-65535 KB | `ESP.getFreeHeap() / 1024` |
| `rssiEncoded` | 31-24 | -128 to +127 dBm | `WiFi.RSSI() + 128` |
| `raceState` | 23-16 | 0-3 | IDLE=0, ARMED=1, RACING=2, FINISHED=3 |
| `fwMajor` | 15-8 | 0-255 | Parsed from `FIRMWARE_VERSION` |
| `fwMinor` | 7-0 | 0-255 | Parsed from `FIRMWARE_VERSION` |

**Visible on `/api/peers`** — each peer now includes a `diag` object with decoded values.

## WiFi Credential Sharing

**Problem**: If you change your WiFi password, every node needs to be reconfigured manually.

**Solution**: Finish gate pushes WiFi creds to all paired peers with a single API call.

### Struct: `WiFiConfigMsg` (116 bytes)
```cpp
struct WiFiConfigMsg {
    uint8_t type;           // 19 (MSG_WIFI_CONFIG)
    uint8_t senderId;
    char ssid[33];
    char pass[65];
    char senderRole[16];
};
```

### API: `POST /api/peers/share-wifi`
- **Auth**: `X-API-Key: admin`
- **Body**: `{"mac":"AA:BB:CC:DD:EE:FF"}` (specific peer) or empty `{}` (broadcast to all)
- **Response**: `{"ok":true,"sent":3}`

### Safety Rules
- Only the **finish gate** can push WiFi creds (it's the hub)
- Receiving nodes **only accept from paired "finish" peers** (security)
- If creds are identical to current config → ignored (idempotent)
- If a race is in progress → **deferred until IDLE** (no mid-race reboots)
- After applying new creds → `saveConfig()` + reboot

### FNG (Fucking New Guy) Onboarding
Unconfigured devices now start ESP-NOW in setup mode (AP_STA), broadcasting "fng" beacons. The finish gate can push WiFi creds to an FNG over ESP-NOW before it even has WiFi. The FNG applies the creds, reboots, and joins the network.

## Remote Commands

**Problem**: A node on the ceiling needs rebooting and you don't feel like getting a ladder.

**Solution**: Finish gate sends commands to any paired peer via ESP-NOW.

### Struct: `RemoteCmdMsg` (24 bytes)
```cpp
struct RemoteCmdMsg {
    uint8_t type;           // 18 (MSG_REMOTE_CMD)
    uint8_t senderId;
    uint8_t command;        // CMD_* subtype
    uint8_t reserved;
    uint32_t param;
    char senderRole[16];
};
```

### Command Subtypes
| CMD | Value | What it does |
|-----|-------|-------------|
| `CMD_REBOOT` | 1 | `ESP.restart()` after 1s delay |
| `CMD_IDENTIFY` | 2 | Rapid LED blink for 10 seconds (find the device) |
| `CMD_DIAG_REPORT` | 3 | Responds with packed diagnostics in a PONG |
| `CMD_WIFI_RECONNECT` | 4 | `WiFi.disconnect()` + `WiFi.begin()` with saved creds |

### API: `POST /api/peers/command`
- **Auth**: `X-API-Key: admin`
- **Body**: `{"mac":"AA:BB:CC:DD:EE:FF","cmd":"reboot"}`
- **Commands**: `reboot`, `identify`, `diag`, `wifi-reconnect`

## Hostname Convention

| Role | Hostname | mDNS URL |
|------|----------|----------|
| Finish gate | `mass-finish` | `http://mass-finish.local` |
| Start gate | `mass-start` | `http://mass-start.local` |
| Speedtrap | `mass-trap` | `http://mass-trap.local` |
| XIAO Telemetry | `mass-telem` | `http://mass-telem.local` (separate firmware) |

- **No MAC suffix** on configured hostnames — clean and memorable
- MAC suffix only appears in **setup mode AP SSID**: `👮 MassTrap Setup A7B2`
- Existing devices keep their old hostname until reconfigured

## BOOT Button — Physical WiFi Toggle

**GPIO 0** (BOOT button on ESP32-S3) repurposed as a WiFi mode toggle at runtime.

| Action | When | Result |
|--------|------|--------|
| Hold 3+ seconds (normal mode) | WiFi connected | Disconnects WiFi, enters AP-only + ESP-NOW mode. 3 slow blinks. |
| Hold 3+ seconds (AP-only mode) | WiFi disabled | Reconnects to saved WiFi. 3 fast blinks. |
| Hold during power-on | Before boot | Download mode (ROM bootloader, NOT our code) |
| Quick tap | Anytime | Nothing (debounced, requires 3s hold) |

**Not persisted** — power cycle always tries WiFi first.

## WiFi Resilience

| Phase | Behavior |
|-------|----------|
| Boot | Try saved WiFi for 20s → if fail, AP_STA fallback (ESP-NOW works) |
| Runtime | Every 60s, if WiFi disconnected and not manually disabled, try `WiFi.begin()` non-blocking |
| Recovery | When WiFi reconnects: switch to AP_STA, pin AP channel, re-sync NTP |
| Manual override | BOOT button disables auto-reconnect until pressed again or power cycled |

## XIAO Telemetry Logger Battery Life

Battery: 300mAh 3.7V LiPo

| Mode | Current Draw | Runtime |
|------|-------------|---------|
| Active (WiFi + IMU + ESP-NOW) | ~100mA | ~3 hours |
| Deep sleep (wake every 2s) | ~5-10mA avg | 30-60 hours |
| Science fair day (~50 runs) | Mixed | 6-8+ hours |

Low-battery shutdown at 3.3V protects the LiPo from deep discharge.

## Build Stats

- **Binary**: 1,800,208 bytes (57.2% of 3MB partition)
- **RAM**: 65,856 bytes (20.1% of 320KB)
- **Added by fleet management**: ~56KB over v2.6.0-beta baseline
