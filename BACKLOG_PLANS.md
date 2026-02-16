# M.A.S.S. Trap — Backlog Implementation Plans (Items 1–14)

*Drafted 2026-02-14 by Claude, following the cadence of the firmware update plan.*
*These are design-complete proposals. Review, approve, or punch holes before implementation.*

---

## Table of Contents

1. [#1 — Server-Side Auth Gate](#1--server-side-auth-gate)
2. [#2 — Hidden SSIDs](#2--hidden-ssids)
3. [#3 — PMK Encryption for ESP-NOW](#3--pmk-encryption-for-esp-now)
4. [#4 — Auth Show/Hide Password Toggle](#4--auth-showhide-password-toggle)
5. [#5 — "Brother" Rename from "Peer"](#5--brother-rename-from-peer)
6. [#6 — Fix OG Setup Wizard Visuals](#6--fix-og-setup-wizard-visuals)
7. [#7 — Node ID Collision Detection](#7--node-id-collision-detection)
8. [#8 — Clone Peer Safety](#8--clone-peer-safety)
9. [#9 — FNG Module (Auto-Onboard via ESP-NOW)](#9--fng-module-auto-onboard-via-esp-now)
10. [#10 — Soft AP Password Option](#10--soft-ap-password-option)
11. [#11 — Speedtrap Update (v2.4.0 → v2.5.0)](#11--speedtrap-update-v240--v250)
12. [#12 — WLED Update (v0.14.4 → v0.15.x)](#12--wled-update-v0144--v015x)
13. [#13 — Fleet Update Phase 2 (LAN-Cached .bin)](#13--fleet-update-phase-2-lan-cached-bin)
14. [#14 — Google Sheets AppScript Debugging](#14--google-sheets-appscript-debugging)

---

## #1 — Server-Side Auth Gate

### Problem

Authentication is **client-side CSS overlay only**. The overlay creates a full-screen `<div>` over the page content, but:

1. **iOS Safari "Distraction Control"** can hide the overlay, revealing the page underneath (our "CVE" from the v2.5.0 session — fixed with `background:#000` but still fundamentally client-side)
2. **DevTools**: Any user can `document.getElementById('authGate').remove()` or just inspect-element to delete the overlay
3. **API endpoints are unprotected** for reads — `GET /api/config`, `GET /api/garage`, `GET /api/history` all respond without auth
4. **WebSocket has zero auth** — anyone connected can send `{"cmd":"arm"}`, `{"cmd":"reset"}`, `{"cmd":"setCar",...}`
5. **In a gym full of middle schoolers** (user's exact use case), this is insufficient

### Current State

- `requireAuth()` in `web_server.cpp:116-122` checks `X-API-Key` header against `cfg.ota_password`
- Only `POST` endpoints use `requireAuth()` — all `GET` endpoints are open
- `checkAuthGate()` in `main.js:543-630` creates a DOM overlay with password input
- Two tiers: `viewer` (badge reader) and `admin` (internal affairs)
- `cfg.viewer_password[32]` exists in config but the **viewer tier is never enforced server-side** — it only gates the CSS overlay
- `/api/auth/info` tells the client whether passwords are set (so JS knows whether to show the overlay)
- `/api/auth/check` validates passwords but returns JSON, not a session token

### Security Model

**Three tiers, server-enforced:**

| Tier | Access | Auth Method |
|------|--------|-------------|
| **Public** | Version badge, firmware update check, captive portal probes | None |
| **Viewer** | Dashboard (read-only race data), leaderboard, garage view | Session cookie or token |
| **Admin** | Config changes, file management, firmware update, arm/reset | Session cookie or token + X-API-Key for API |

### Architecture: Session Token Approach

HTTP digest/basic auth won't work cleanly with WebSocket (port 81 has no HTTP headers after upgrade). Instead:

1. **Login endpoint** `POST /api/auth/login` — accepts `{password, tier}`, returns `{ok, token}` where token is a random 16-byte hex string stored in a server-side array
2. **Token validation** — all protected endpoints check for `Authorization: Bearer <token>` header OR `?token=<token>` query parameter (for WebSocket upgrade URL)
3. **Session storage** — ESP32 stores up to 8 active sessions in RAM (no flash wear). Each session has: `token[33]`, `tier` (viewer/admin), `createdAt` (millis), `lastSeen` (millis)
4. **Session expiry** — 4 hours idle timeout, checked lazily on each request. Max 8 sessions; overflow evicts oldest
5. **WebSocket auth** — client connects to `ws://host:81/?token=<token>`. WebSocket `onConnect` callback validates token before accepting. Invalid token → immediate disconnect

### Implementation Plan

#### A. Server-Side Session Manager (`web_server.cpp`, ~80 lines)

```
// After firmware update state variables (line 97)
#define MAX_SESSIONS 8
#define SESSION_TIMEOUT_MS  (4UL * 60 * 60 * 1000)  // 4 hours

struct AuthSession {
  char token[33];     // 32 hex chars + null
  char tier[8];       // "viewer" or "admin"
  unsigned long createdAt;
  unsigned long lastSeen;
};

static AuthSession sessions[MAX_SESSIONS];
static int sessionCount = 0;

// Generate random hex token using ESP32 hardware RNG
static void generateToken(char* buf) {
  for (int i = 0; i < 16; i++) {
    uint8_t b = esp_random() & 0xFF;
    sprintf(buf + i*2, "%02x", b);
  }
  buf[32] = '\0';
}

// Create session, return token. Evicts oldest if full.
static const char* createSession(const char* tier);

// Validate token, return tier string or NULL if invalid/expired
static const char* validateToken(const String& token);

// Clean expired sessions (lazy, called from validateToken)
static void cleanExpiredSessions();
```

#### B. `requireTier(const char* minTier)` — Replaces `requireAuth()` (~20 lines)

```cpp
// Returns true if request has valid session at required tier.
// Checks: Authorization header, query param, X-API-Key (legacy)
static bool requireTier(const char* minTier) {
  // Legacy: X-API-Key still works for admin (backward compat with push_ui.sh etc.)
  String apiKey = server.header("X-API-Key");
  if (apiKey.length() > 0 && strcmp(apiKey.c_str(), cfg.ota_password) == 0) {
    return true; // Admin via API key
  }

  // Token auth
  String token = "";
  String authHeader = server.header("Authorization");
  if (authHeader.startsWith("Bearer ")) {
    token = authHeader.substring(7);
  }
  if (token.length() == 0) {
    token = server.arg("token");
  }

  const char* tier = validateToken(token);
  if (!tier) {
    server.send(401, "application/json", "{\"error\":\"Authentication required\"}");
    return false;
  }

  // Tier hierarchy: admin > viewer > public
  if (strcmp(minTier, "viewer") == 0) return true; // Both viewer and admin pass
  if (strcmp(minTier, "admin") == 0 && strcmp(tier, "admin") == 0) return true;

  server.send(403, "application/json", "{\"error\":\"Insufficient privileges\"}");
  return false;
}
```

#### C. Updated Auth Endpoints

**`POST /api/auth/login`** — replaces `/api/auth/check`:
```cpp
// Validates password, creates session, returns token
// Request:  {"password":"admin","tier":"admin"}
// Response: {"ok":true,"token":"a1b2c3...","tier":"admin"}
//      or:  {"ok":false}
```

**`POST /api/auth/logout`** — new:
```cpp
// Invalidates session token
// Request: Authorization: Bearer <token>
// Response: {"ok":true}
```

**`GET /api/auth/info`** — unchanged (tells client which gates to show)

**`GET /api/auth/check`** (GET, not POST) — new convenience:
```cpp
// Validates current token without login
// Returns: {"authenticated":true,"tier":"admin"} or {"authenticated":false}
```

#### D. Endpoint Protection Matrix

| Endpoint | Current | New |
|----------|---------|-----|
| `GET /` (dashboard) | Open | Viewer |
| `GET /config` (system) | Open | Admin |
| `GET /console` | Open | Admin |
| `GET /api/config` | Open | **Viewer** (hide passwords) |
| `GET /api/info` | Open | Viewer |
| `GET /api/garage` | Open | Viewer |
| `GET /api/history` | Open | Viewer |
| `GET /api/peers` | Open | Viewer |
| `GET /api/version` | Open | **Public** (firmware check needs this) |
| `GET /api/auth/info` | Open | **Public** (login page needs this) |
| `GET /api/wifi-status` | Open | Viewer |
| `POST /api/config` | Admin (X-API-Key) | Admin |
| `POST /api/firmware/*` | Admin (X-API-Key) | Admin |
| WebSocket port 81 | **Open** | **Viewer** (token in URL) |
| Static files (JS/CSS) | Open | **Public** (needed for login page) |

#### E. WebSocket Authentication

```cpp
static void webSocketEvent(uint8_t num, WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED: {
      // Extract token from URL query: ws://host:81/?token=abc123
      String url = String((char*)payload);
      int tokenIdx = url.indexOf("token=");
      if (tokenIdx < 0) {
        webSocket.disconnect(num);
        return;
      }
      String token = url.substring(tokenIdx + 6);
      token = token.substring(0, 32); // Exactly 32 hex chars
      const char* tier = validateToken(token);
      if (!tier) {
        webSocket.disconnect(num);
        return;
      }
      // Token valid — allow connection
      broadcastState();
      break;
    }
    // ... rest unchanged
  }
}
```

#### F. Client-Side Changes (`main.js`)

Replace `checkAuthGate()` with `initAuth()`:

1. On page load: check `sessionStorage` for saved token
2. If token exists: validate via `GET /api/auth/check?token=...`
3. If valid: proceed, store token, connect WebSocket with `?token=...`
4. If invalid/missing: show login overlay (same styling as current)
5. On successful login: store token in `sessionStorage`, reload page
6. WebSocket connect URL: `ws://${host}:81/?token=${sessionStorage.getItem('mass_token')}`

The overlay itself stays as a UI element (it's nicely styled), but now it's backed by server-side enforcement. Even if the overlay is removed, API calls fail without a valid token.

#### G. HTML Page Serving with Auth Gate

For HTML pages themselves (dashboard, config), we can't easily do token-in-URL for the initial page load. Two approaches:

**Approach A — Redirect to login page (preferred):**
- Create a minimal `login.html` (served without auth, ~30 lines)
- All other pages redirect to `/login` if no valid session cookie
- ESP32 `WebServer` doesn't support cookies natively, but we can set `Set-Cookie` header manually and read it back via `server.header("Cookie")`

**Approach B — Keep client-side overlay, server protects APIs only:**
- HTML pages served without auth (they're just shells)
- All data comes from authenticated API calls
- WebSocket requires token
- CSS overlay remains as UX convenience, not security boundary

**Recommendation: Approach B** — it's simpler, the APIs are what matter, and the overlay provides clean UX. The key fix is that even without the overlay, you see an empty page because APIs reject unauthenticated requests.

### Files to Modify

| File | Changes |
|------|---------|
| `web_server.cpp` | Session manager (~80 lines), `requireTier()` (~20 lines), updated auth endpoints, WebSocket auth, endpoint protection |
| `web_server.h` | No changes needed (session manager is static to web_server.cpp) |
| `data/main.js` | `initAuth()` replaces `checkAuthGate()`, token management, WebSocket URL with token |
| `data/system.html` | Logout button in admin UI |

### Estimated Size

~150 lines C++, ~40 lines JS. No new libraries. RAM cost: 8 sessions × ~50 bytes = ~400 bytes.

### Edge Cases

- **No password set**: All endpoints open (current behavior preserved). `GET /api/auth/info` returns `{hasViewerPassword:false, hasAdminPassword:false}` → client skips login
- **Token in URL security**: WebSocket URL with token is visible in browser devtools but NOT in HTTP referrer headers (WebSocket upgrade). Acceptable for LAN use
- **Multiple tabs**: All tabs share `sessionStorage` within same browser session — single login
- **ESP32 reboot**: All sessions lost (RAM only). Client detects via WebSocket disconnect → re-shows login overlay
- **push_ui.sh and curl**: X-API-Key header still works for admin tier (backward compat)

---

## #2 — Hidden SSIDs

### Problem

Every M.A.S.S. Trap device broadcasts an open WiFi AP visible to anyone scanning. In `WIFI_AP_STA` mode, the finish gate, start gate, and speedtrap all show SSIDs like "🏁 masstrap-finish-a7b2" to every phone and laptop in range. In a gym full of middle schoolers, this invites unwanted connections.

### Current State

Three places create APs in `MASS_Trap.ino`:

1. **Setup mode** (line 236): `WiFi.softAP(apName);` — open, visible
2. **Standalone mode** (line 262): `WiFi.softAP(standaloneAP);` — open, visible
3. **WiFi+AP mode** (line 127): `WiFi.softAP(hostname, NULL, WiFi.channel());` — open, visible, pinned to STA channel

### Solution

Add a `bool ap_hidden` config field. When enabled, pass `true` as the 4th argument to `WiFi.softAP()`.

```cpp
// WiFi.softAP(ssid, password, channel, hidden, max_connections)
WiFi.softAP(hostname, apPassword, WiFi.channel(), cfg.ap_hidden, 4);
```

**Note:** Setup mode AP should NEVER be hidden — users need to find it on first boot.

### Implementation

#### A. Config (`config.h`, `config.cpp`)

```cpp
// In DeviceConfig struct (config.h):
bool ap_hidden;       // Hide the soft AP SSID from WiFi scans

// In setDefaults() (config.cpp):
c.ap_hidden = false;  // Visible by default — hidden is opt-in

// In configToJson() and configFromJson(): serialize/deserialize
```

#### B. Boot Code (`MASS_Trap.ino`)

```cpp
// Standalone mode (line 262):
WiFi.softAP(standaloneAP, apPassword, 1, cfg.ap_hidden, 4);

// WiFi+AP mode (line 127):
WiFi.softAP(hostname, apPassword, WiFi.channel(), cfg.ap_hidden, 4);

// Setup mode: ALWAYS visible (don't use cfg.ap_hidden)
WiFi.softAP(apName);  // unchanged
```

#### C. Config UI (`data/system.html`)

Add checkbox in the Network tab:
```html
<label><input type="checkbox" id="apHidden"> Hide AP from WiFi scans</label>
<div class="hint">When enabled, the device's access point won't appear in WiFi network lists.
Devices that already know the SSID can still connect. Setup mode AP is always visible.</div>
```

### Files to Modify

| File | Changes |
|------|---------|
| `config.h` | Add `bool ap_hidden` to `DeviceConfig` |
| `config.cpp` | Default, serialize, deserialize (~6 lines) |
| `MASS_Trap.ino` | Pass `cfg.ap_hidden` to `softAP()` calls (~3 lines) |
| `data/system.html` | Checkbox in Network section (~5 lines) |
| `html_config.h` | Mirror checkbox (PROGMEM fallback) |

### Estimated Size

~15 lines total. Trivial change.

### Interaction with #10 (Soft AP Password)

These two features work together. Both modify the same `WiFi.softAP()` calls. Implement them together or #10 first.

---

## #3 — PMK Encryption for ESP-NOW

### Problem

All ESP-NOW messages are **unencrypted broadcast**. Anyone with an ESP32 in range can:
- Sniff race timing data, peer hostnames, device IDs
- Inject fake `MSG_START` / `MSG_ARM_CMD` messages to sabotage races
- Impersonate a start gate and send false timestamps

### Current State

- `espnow_comm.cpp:102` — `peerInfo.encrypt = false` (explicit)
- `espnow_comm.cpp:493` — broadcast peer also `encrypt = false`
- No calls to `esp_now_set_pmk()` anywhere

### ESP-NOW Encryption Primer

ESP-NOW supports **CCMP encryption** (AES-128-CCM, same as WPA2):

- **PMK (Primary Master Key)**: 16-byte key set once via `esp_now_set_pmk()`. All devices in the mesh share this key. It's the "network password" for ESP-NOW.
- **LMK (Local Master Key)**: 16-byte per-peer key set in `esp_now_peer_info_t.lmk`. Derives session keys with each peer individually. Optional — PMK alone provides encryption.
- **Encrypted flag**: `peerInfo.encrypt = true` enables encryption for that peer's unicast traffic.
- **Broadcast**: ESP-NOW encryption does NOT apply to broadcast frames. Broadcasts are always unencrypted. This means **beacons remain in the clear** (by design — otherwise nobody could discover new devices).

### Security Model

**PMK-only approach** (simpler, sufficient for our threat model):

1. All M.A.S.S. Trap devices share one PMK (configurable, derived from OTA password or a dedicated field)
2. Unicast messages (everything except beacons) are encrypted with CCMP
3. Beacons remain unencrypted (necessary for discovery, contain only role + hostname — not sensitive)
4. The PMK is stored in config and must match across all paired devices

**Threat model**: We're defending against middle-schoolers with smartphones, not state-level adversaries. PMK shared across the mesh is fine. The beacons leaking hostname/role is acceptable — they can already see the WiFi SSIDs.

### Implementation

#### A. Config (`config.h`, `config.cpp`)

```cpp
// In DeviceConfig struct:
char espnow_pmk[17];  // 16-byte PMK as hex string + null (or raw bytes)

// In setDefaults():
memset(c.espnow_pmk, 0, sizeof(c.espnow_pmk));  // Empty = no encryption (backward compat)
```

#### B. ESP-NOW Init (`espnow_comm.cpp`)

```cpp
void initESPNow() {
  if (esp_now_init() != ESP_OK) {
    LOG.println("[ESP-NOW] Init FAILED!");
    return;
  }

  // Set PMK if configured
  if (strlen(cfg.espnow_pmk) >= 16) {
    esp_err_t err = esp_now_set_pmk((const uint8_t*)cfg.espnow_pmk);
    if (err == ESP_OK) {
      LOG.println("[ESP-NOW] PMK encryption enabled");
    } else {
      LOG.printf("[ESP-NOW] PMK set failed: %d\n", err);
    }
  } else {
    LOG.println("[ESP-NOW] No PMK — encryption disabled (open mesh)");
  }

  esp_now_register_recv_cb(onDataRecv);
  // ... rest unchanged
}
```

#### C. Peer Registration (`espnow_comm.cpp`)

```cpp
static bool ensureESPNowPeer(const uint8_t* mac) {
  if (esp_now_is_peer_exist(mac)) return true;

  esp_now_peer_info_t peerInfo = {};
  memcpy(peerInfo.peer_addr, mac, 6);
  peerInfo.channel = 0;

  // Enable encryption if PMK is configured
  if (strlen(cfg.espnow_pmk) >= 16) {
    peerInfo.encrypt = true;
    // LMK can optionally be set per-peer for additional isolation
    // For now, PMK-only encryption is sufficient
  } else {
    peerInfo.encrypt = false;
  }

  return esp_now_add_peer(&peerInfo) == ESP_OK;
}
```

#### D. Broadcast Peer (unchanged)

Broadcast peer (`FF:FF:FF:FF:FF:FF`) keeps `encrypt = false` — this is an ESP-NOW limitation. Broadcasts cannot be encrypted. Beacons will remain in the clear.

#### E. Config UI (`data/system.html`)

In the Network or Security section:
```html
<div class="card-label">ESP-NOW Encryption Key</div>
<input type="text" id="espnowPmk" placeholder="16 characters (blank = no encryption)" maxlength="16">
<div class="hint">All devices must share the same key. Leave blank for open mesh (no encryption).</div>
```

#### F. PMK Derivation Option

Instead of a manual key, derive from OTA password:

```cpp
// In initESPNow(), if espnow_pmk is empty but ota_password is set:
if (strlen(cfg.espnow_pmk) == 0 && strlen(cfg.ota_password) > 0) {
  // Derive PMK from OTA password (pad/truncate to 16 bytes)
  memset(cfg.espnow_pmk, 0, 17);
  strncpy(cfg.espnow_pmk, cfg.ota_password, 16);
  // Not cryptographically ideal but sufficient for our threat model
}
```

**Open question for user**: Should PMK auto-derive from OTA password (zero config, just set the same OTA password on all devices) or require explicit key entry? I recommend auto-derive for simplicity.

### Files to Modify

| File | Changes |
|------|---------|
| `config.h` | Add `char espnow_pmk[17]` |
| `config.cpp` | Default, serialize, deserialize (~8 lines) |
| `espnow_comm.cpp` | PMK init (~10 lines), encrypt flag in peer registration (~5 lines) |
| `data/system.html` | PMK input field (~8 lines) |

### Estimated Size

~30 lines C++, ~8 lines HTML/JS.

### Critical Constraint

**All devices in the mesh must have the same PMK.** If you change the PMK on the finish gate, you must change it on the start gate and speedtrap too, or they won't be able to communicate. The FNG module (#9) should auto-distribute the PMK during onboarding.

### Rollback

If encryption causes issues (e.g., beacons work but unicast doesn't on a specific board): set `espnow_pmk` to empty string → reverts to unencrypted. No firmware change needed.

---

## #4 — Auth Show/Hide Password Toggle

### Problem

Password fields on the config/system page have no visibility toggle. When entering long passwords on a phone, it's hard to verify what you typed.

### Current State

The setup wizard (`html_config.h`) already has a toggle at line 802:
```javascript
input.type = input.type === 'password' ? 'text' : 'password';
```

But `system.html` (Internal Affairs) doesn't have toggles for:
- OTA password field (`#otaPassword`)
- Viewer password field (`#viewerPassword`)

The auth gate overlay (`main.js:572`) has no toggle either.

### Implementation

#### A. Reusable Toggle Component (`main.js`)

Add a utility function that any page can call:

```javascript
function addPasswordToggle(inputId) {
  var input = document.getElementById(inputId);
  if (!input) return;
  var wrapper = document.createElement('div');
  wrapper.style.cssText = 'position:relative;display:flex;align-items:center;';
  input.parentNode.insertBefore(wrapper, input);
  wrapper.appendChild(input);

  var btn = document.createElement('button');
  btn.type = 'button';
  btn.textContent = '👁';
  btn.title = 'Show/hide password';
  btn.style.cssText = 'position:absolute;right:8px;background:none;border:none;cursor:pointer;font-size:1.2rem;opacity:0.6;padding:4px;';
  btn.onclick = function() {
    input.type = input.type === 'password' ? 'text' : 'password';
    btn.style.opacity = input.type === 'text' ? '1' : '0.6';
  };
  wrapper.appendChild(btn);
}
```

#### B. Apply on Init

In `system.html`'s init function:
```javascript
addPasswordToggle('otaPassword');
addPasswordToggle('viewerPassword');
```

In `main.js`'s auth gate overlay builder:
```javascript
// After creating the password input, add toggle
addPasswordToggle('authGateInput');
```

### Files to Modify

| File | Changes |
|------|---------|
| `data/main.js` | Add `addPasswordToggle()` utility (~20 lines) |
| `data/system.html` | Call toggle on OTA + viewer password fields (~2 lines) |
| `data/style.css` | Optional: subtle hover effect on toggle button (~3 lines) |

### Estimated Size

~25 lines total. Trivial.

---

## #5 — "Brother" Rename from "Peer"

### Problem

The user uses the term "Brother" (from the "Brother's Six" protocol naming) for paired devices, but the UI and API still say "Peer" everywhere. This is a cosmetic/branding alignment.

### Current State

The codebase uses "peer" in:
- API endpoints: `/api/peers`, `/api/peers/forget`
- JSON keys: `"paired"`, peer objects
- C++ variable names: `KnownPeer`, `peers[]`, `peerCount`, `peerConnected`
- UI strings: "Peer Status", "Connected Peers", "Forget Peer"
- Log messages: `[PEERS]` prefix
- Comments: references to "peer" throughout

### Approach

**UI-only rename** — change what the user sees, not the code internals:

1. **API endpoints stay as `/api/peers`** — changing URL paths breaks `push_ui.sh` and any external integrations
2. **JSON keys stay as-is** — backward compat with backup/restore
3. **C++ variable names stay as-is** — refactoring for no functional benefit is risky
4. **UI labels change** — "Peer" → "Brother" in HTML display text
5. **Log messages stay** — `[PEERS]` prefix is for developer eyes, not users

### Implementation

#### A. Dashboard (`data/index.html` / `data/dashboard.html`)

Search and replace display text only:
- "Peer Status" → "Brother Status"
- "Connected Peers" → "Connected Brothers"
- "No peers found" → "No brothers found"
- "Peer Offline" → "Brother Offline"

#### B. System Config (`data/system.html`)

- "Peer MAC" → "Brother MAC"
- "Forget Peer" → "Forget Brother"
- "Peer Discovery" → "Brother Discovery"
- Tooltip/hint text updates

#### C. Start/Speedtrap Status Pages

- `data/start_status.html` — update peer indicator text
- `data/speedtrap_status.html` — update peer indicator text

### Files to Modify

| File | Changes |
|------|---------|
| `data/dashboard.html` | ~5 string replacements |
| `data/index.html` | ~5 string replacements |
| `data/system.html` | ~8 string replacements |
| `data/start_status.html` | ~3 string replacements |
| `data/speedtrap_status.html` | ~3 string replacements |
| PROGMEM headers | Regenerate after LittleFS files updated |

### Estimated Size

~25 string replacements across 5 files. No logic changes. Grep-and-replace.

### Open Question

Should the PROGMEM fallback headers (`html_*.h`) be regenerated now, or deferred to next `push_ui.sh` run? I recommend deferring — LittleFS files take priority.

---

## #6 — Fix OG Setup Wizard Visuals

### Problem

The original setup wizard (captive portal) has visual inconsistencies compared to the v2.5.0 theme engine. Specific issues need to be identified by visual inspection, but known problems include:

1. The setup page uses `html_config.h` PROGMEM, which was written for the system.html UI — it has all the tabs (Device, Network, Integrations, System) but in setup mode, many tabs are irrelevant (no peers, no WLED, no history)
2. Theme CSS variables may not be loaded (no `main.js` or `style.css` available in setup mode since LittleFS may be empty on first boot)
3. Mobile layout may be broken without the responsive CSS from `style.css`

### Current State

Setup mode serves from PROGMEM only (line 1466-1468 in `web_server.cpp`):
```cpp
server.on("/", HTTP_GET, []() {
  server.send_P(200, "text/html", CONFIG_HTML);
});
```

The `CONFIG_HTML` is the full system.html baked into `html_config.h` — a self-contained page with inline CSS/JS. It doesn't depend on external `style.css` or `main.js`.

### Implementation

#### A. Audit Current Setup Page

1. Flash a device with no config → enters setup mode
2. Connect to "👮 MassTrap Setup XXXX" AP
3. Screenshot the captive portal on iOS, Android, desktop
4. Document visual issues

#### B. Minimal Setup-Specific Page

Create a **setup-only page** that strips irrelevant tabs and shows only what's needed:

**Required in setup mode:**
- WiFi SSID (with scan dropdown) + password
- Device role selector (start/finish/speedtrap)
- Device ID (auto-generated, editable)
- Sensor GPIO pins (with blacklist validation)
- Track length + scale factor
- OTA password
- Save + reboot button

**NOT needed in setup mode:**
- Peer management (no peers yet)
- WLED config (need WiFi first)
- Google Sheets URL (need WiFi first)
- Firmware update (need WiFi first)
- Audio management
- File browser
- Console log

#### C. Self-Contained Styling

The setup page should have its own inline `<style>` block that:
- Uses the same CSS custom properties as the theme engine
- Defaults to the "Interceptor" theme (dark blue)
- Is fully responsive without external CSS
- Looks polished on mobile (captive portal popup is typically phone-sized)

### Files to Modify

| File | Changes |
|------|---------|
| `data/setup.html` | New file — minimal setup wizard |
| `web_server.cpp` | Serve `setup.html` from LittleFS if available, fall back to PROGMEM |
| `html_setup.h` | New PROGMEM header generated from `setup.html` |

### Estimated Size

~200-300 lines for a clean setup page. The current `html_config.h` is ~1200 lines.

### Open Question

Should the setup wizard be a multi-step flow (Step 1: WiFi, Step 2: Role, Step 3: Pins, Step 4: Review + Save) or a single scrollable page like the current config? Multi-step would be more polished but more code.

---

## #7 — Node ID Collision Detection

### Problem

`device_id` is derived from `mac[5] % 253 + 1` (range 1-254). If two devices happen to have MAC addresses where the last byte produces the same ID, they'll collide silently. The peer registry uses MAC for lookup (not device_id), but the `senderId` field in ESP-NOW messages uses `device_id` — a collision could cause confusion in logs and UI.

### Current State

```cpp
// config.cpp, setDefaults():
uint8_t mac[6];
esp_efuse_mac_get_default(mac);
c.device_id = (mac[5] % 253) + 1;
```

The device_id is:
- Stored in config (survives reboots)
- Sent in every ESP-NOW message as `msg.senderId`
- Displayed in the UI as "Device ID"
- Used in peer registry as `peers[idx].deviceId`

Collision detection: **none exists**.

### Solution

#### A. Detection at Beacon/Pair Time

When a beacon or pair request arrives, check if the sender's device_id matches our own or any other peer's ID:

```cpp
// In onDataRecv(), after upsertPeer():
if (msg.senderId == cfg.device_id && memcmp(info->src_addr, /* our MAC */, 6) != 0) {
  LOG.printf("[PEERS] ⚠ ID COLLISION: %s (%s) has same device_id=%d as us!\n",
             msg.hostname, msg.role, msg.senderId);
  // Set flag for UI warning
  idCollisionDetected = true;
  strncpy(idCollisionHostname, msg.hostname, sizeof(idCollisionHostname));
}
```

#### B. Collision Flag in Broadcast State

Add to `broadcastState()`:
```cpp
if (idCollisionDetected) {
  doc["idCollision"] = idCollisionHostname;
}
```

Dashboard shows a warning banner: "⚠ Device ID collision with masstrap-start-a7b2. Change one device's ID in config."

#### C. Auto-Resolution (Optional Enhancement)

If collision detected, auto-bump to next available ID:
```cpp
// Find unused ID
uint8_t newId = cfg.device_id;
while (isIdInUse(newId)) newId = (newId % 253) + 1;
if (newId != cfg.device_id) {
  cfg.device_id = newId;
  saveConfig();
  LOG.printf("[PEERS] Auto-resolved ID collision: new ID = %d\n", newId);
}
```

### Files to Modify

| File | Changes |
|------|---------|
| `espnow_comm.cpp` | Collision check in `onDataRecv()` (~15 lines) |
| `espnow_comm.h` | Export collision flag |
| `web_server.cpp` | Add `idCollision` to `broadcastState()` (~3 lines) |
| `data/dashboard.html` | Warning banner UI (~10 lines) |

### Estimated Size

~30 lines C++, ~10 lines JS/HTML.

---

## #8 — Clone Peer Safety

### Problem

Currently, when a compatible peer is discovered via beacon, it's **auto-paired immediately** — no user confirmation. If someone brings a rogue M.A.S.S. Trap device (or a clone), it auto-pairs and can send false timing data.

### Current State

`espnow_comm.cpp:377-383`:
```cpp
// Auto-pair: if compatible and not yet paired → initiate
if (!peers[idx].paired && isCompatibleRole(cfg.role, msg.role)) {
  LOG.printf("[PEERS] Compatible: %s (%s) — requesting pair\n", ...);
  ESPMessage req;
  buildMessage(req, MSG_PAIR_REQ, nowUs(), 0);
  esp_now_send(info->src_addr, (uint8_t*)&req, sizeof(req));
}
```

And `espnow_comm.cpp:425`:
```cpp
peers[idx].paired = true;  // Immediately accepted, no confirmation
```

### Solution: Suggestion-Based Pairing

Change auto-pair to **suggest + require approval**:

1. When a compatible but unknown peer is discovered → add to registry as `paired = false`
2. Show a notification in the dashboard: "New device discovered: masstrap-start-a7b2 (Start Gate). [Accept] [Ignore]"
3. User clicks Accept → `POST /api/peers/accept?mac=XX:XX:XX:XX:XX:XX` → sets `paired = true`, sends `MSG_PAIR_ACK`
4. If user clicks Ignore → device stays in registry as unpaired, no pair request sent

#### A. New Peer State: `pendingApproval`

Add to `KnownPeer`:
```cpp
bool pendingApproval;  // Discovered but not yet user-approved
```

#### B. Modified Auto-Pair Logic

```cpp
// Instead of auto-sending MSG_PAIR_REQ:
if (!peers[idx].paired && !peers[idx].pendingApproval && isCompatibleRole(cfg.role, msg.role)) {
  peers[idx].pendingApproval = true;
  LOG.printf("[PEERS] 📋 Approval needed: %s (%s) wants to pair\n", msg.hostname, msg.role);
  // Notify WebSocket clients
  broadcastPeerDiscovery(msg.hostname, msg.role, info->src_addr);
}
```

#### C. Approval API

```cpp
// POST /api/peers/accept — Accept a pending peer
server.on("/api/peers/accept", HTTP_POST, []() {
  if (!requireAuth()) return;
  String mac = server.arg("mac");
  uint8_t macBytes[6];
  if (!parseMacString(mac.c_str(), macBytes)) {
    server.send(400, "application/json", "{\"error\":\"Invalid MAC\"}");
    return;
  }
  int idx = findPeerByMac(macBytes);
  if (idx < 0) {
    server.send(404, "application/json", "{\"error\":\"Peer not found\"}");
    return;
  }
  // Send pair request now
  ESPMessage req;
  buildMessage(req, MSG_PAIR_REQ, nowUs(), 0);
  esp_now_send(macBytes, (uint8_t*)&req, sizeof(req));
  peers[idx].pendingApproval = false;
  // paired will be set to true when we receive MSG_PAIR_ACK
  server.send(200, "application/json", "{\"ok\":true}");
});
```

#### D. Config Option: Auto-Accept Mode

For convenience (e.g., during initial setup of multiple devices), add a config toggle:

```cpp
bool auto_accept_peers;  // true = old behavior (auto-pair), false = require approval
```

Default: `false` (safe). Users can enable auto-accept temporarily during setup, then disable.

#### E. Dashboard Notification

When a pending peer is detected, show a toast/banner:
```html
<div class="peer-approval-banner">
  New Brother detected: <strong>masstrap-start-a7b2</strong> (Start Gate)
  <button onclick="acceptPeer('AA:BB:CC:DD:EE:FF')">Accept</button>
  <button onclick="ignorePeer('AA:BB:CC:DD:EE:FF')">Ignore</button>
</div>
```

### Files to Modify

| File | Changes |
|------|---------|
| `config.h` | Add `bool auto_accept_peers` |
| `config.cpp` | Default, serialize, deserialize (~4 lines) |
| `espnow_comm.h` | Add `pendingApproval` to `KnownPeer` |
| `espnow_comm.cpp` | Modified auto-pair logic (~15 lines) |
| `web_server.cpp` | `POST /api/peers/accept` endpoint (~20 lines), peer discovery WebSocket notification |
| `data/dashboard.html` | Approval banner UI (~20 lines) |
| `data/system.html` | Auto-accept toggle in config (~5 lines) |

### Estimated Size

~80 lines C++, ~30 lines JS/HTML.

---

## #9 — FNG Module (Auto-Onboard via ESP-NOW)

### Problem

When a new (unconfigured) M.A.S.S. Trap device powers on for the first time, it enters setup mode with a captive portal. The user must manually connect to its AP, navigate to 192.168.4.1, fill in WiFi credentials, role, pins, etc. For a fleet of devices, this is tedious.

"FNG" = "F***ing New Guy" — the new device that needs to be brought up to speed.

### Concept

An already-configured device (the "sergeant") pushes bootstrap config to the FNG over ESP-NOW, allowing zero-touch onboarding:

1. FNG powers on → enters setup mode → broadcasts ESP-NOW beacons with role="unconfigured"
2. Nearby configured devices hear the beacon and recognize it as an FNG
3. Sergeant's dashboard shows: "New unconfigured device detected: 👮 MassTrap Setup A7B2. [Onboard as Start Gate] [Onboard as Speed Trap]"
4. User clicks role → sergeant sends bootstrap config via ESP-NOW:
   - WiFi credentials (from its own config)
   - Selected role
   - Auto-generated hostname
   - Default pin mappings for role
   - PMK key (if encryption enabled)
5. FNG receives config, saves, reboots → comes up configured, joins WiFi, starts beaconing as its assigned role

### Protocol: New Message Types

```cpp
#define MSG_FNG_BEACON    14   // Unconfigured device says "I'm new"
#define MSG_FNG_OFFER     15   // Sergeant offers config to FNG
#define MSG_FNG_ACCEPT    16   // FNG accepts offered config
#define MSG_FNG_CONFIG    17   // Sergeant sends full config payload
#define MSG_FNG_ACK       18   // FNG confirms config received and saved
```

### Challenge: Config Payload Size

`ESPMessage` is ~64 bytes. A full bootstrap config is ~200+ bytes. Options:

**Option A — Multi-part messages**: Split config into 3-4 ESP-NOW frames with sequence numbers. Reassemble on FNG side. Adds complexity but stays within ESP-NOW.

**Option B — WiFi bootstrap**: Instead of sending full config over ESP-NOW, sergeant sends only WiFi credentials (fits in one ESPMessage offset field as packed bytes). FNG connects to WiFi → pulls full config from sergeant via HTTP `GET /api/config/bootstrap?mac=XX:XX:XX:XX:XX:XX`.

**Recommendation: Option B** — simpler, more reliable, and the HTTP endpoint can serve a full JSON config. ESP-NOW just delivers the WiFi "skeleton key".

### Implementation

#### A. FNG Beacon (setup mode broadcasts)

In `MASS_Trap.ino` setup mode section:
```cpp
// FNG beacon: broadcast that we're unconfigured
if (setupMode) {
  // Init ESP-NOW even in setup mode (just for FNG beaconing)
  esp_now_init();
  esp_now_register_recv_cb(onFNGDataRecv);
  // Broadcast FNG beacon every 3 seconds
  ESPMessage fng;
  fng.type = MSG_FNG_BEACON;
  fng.senderId = 0; // No ID yet
  strncpy(fng.role, "unconfigured", sizeof(fng.role));
  // hostname = setup AP name
}
```

#### B. FNG Listener (on configured devices)

In `espnow_comm.cpp`, `onDataRecv()`:
```cpp
if (msg.type == MSG_FNG_BEACON) {
  // Only finish gates should offer onboarding (single point of control)
  if (strcmp(cfg.role, "finish") != 0) return;

  // Notify dashboard via WebSocket
  broadcastFNGDetected(info->src_addr, msg.hostname);
  return;
}
```

#### C. Onboarding API

```
POST /api/fng/onboard
{
  "mac": "AA:BB:CC:DD:EE:FF",
  "role": "start",
  "sensor_pin": 4,
  "led_pin": 2
}
```

Finish gate:
1. Packs WiFi SSID + password into ESPMessage (or minimal struct)
2. Sends `MSG_FNG_OFFER` with WiFi creds to the FNG's MAC
3. FNG receives, connects to WiFi
4. FNG calls `GET http://finish-ip/api/fng/config?mac=...` to get full config
5. FNG saves config, reboots, joins the mesh

#### D. Bootstrap Config Endpoint

```
GET /api/fng/config?mac=AA:BB:CC:DD:EE:FF
```

Returns a complete `config.json` tailored for the FNG:
- WiFi creds (from finish gate's own config)
- Role (from the onboard request)
- Auto-generated hostname
- Default pin mappings for the role
- PMK (if encryption enabled)
- Track length, scale factor (from finish gate's config)
- `configured: true`

### Files to Modify

| File | Changes |
|------|---------|
| `espnow_comm.h` | New message types (14-18) |
| `espnow_comm.cpp` | FNG beacon handler (~20 lines) |
| `MASS_Trap.ino` | FNG beacon in setup mode loop (~30 lines) |
| `web_server.cpp` | `/api/fng/onboard` and `/api/fng/config` endpoints (~60 lines) |
| `data/dashboard.html` | FNG detection UI (~30 lines) |

### Estimated Size

~150 lines C++, ~40 lines JS/HTML.

### Dependencies

- #3 (PMK encryption) — PMK should be distributed during FNG onboarding
- #8 (Clone peer safety) — FNG devices should still require approval after initial config

### Security Considerations

- Only the finish gate can onboard FNGs (single point of control)
- WiFi credentials are sent over ESP-NOW (unencrypted unless PMK is set up) — implement #3 first, or accept that initial onboarding is in the clear (one-time risk)
- The FNG must be physically present (ESP-NOW range ~200m line of sight, ~30m indoors)

---

## #10 — Soft AP Password Option

### Problem

All soft APs are open (no password). Anyone can connect to the device's AP and access the web interface. Related to #2 (hidden SSIDs) — both reduce the attack surface.

### Current State

All three `WiFi.softAP()` calls pass `NULL` for password:
```cpp
WiFi.softAP(hostname, NULL, WiFi.channel());
```

### Solution

Add `char ap_password[33]` to config. When set, apply to all non-setup soft APs.

```cpp
// In DeviceConfig:
char ap_password[33];  // WPA2 password for soft AP (blank = open)

// Usage:
const char* apPw = (strlen(cfg.ap_password) > 0) ? cfg.ap_password : NULL;
WiFi.softAP(hostname, apPw, WiFi.channel(), cfg.ap_hidden, 4);
```

**Setup mode AP must remain open** — if you lock the setup AP, a user who forgot the password can't reconfigure the device. Factory reset already wipes config, which restores the open setup AP.

### WPA2 Constraints

- Minimum 8 characters (ESP32 WiFi driver requirement)
- Maximum 32 characters
- Validate in config save handler

### Implementation

#### A. Config (`config.h`, `config.cpp`)

```cpp
char ap_password[33];  // Soft AP WPA2 password (blank = open, min 8 chars if set)
```

Default: empty string (open AP — backward compatible).

#### B. Validation in `saveConfig()`

```cpp
if (strlen(c.ap_password) > 0 && strlen(c.ap_password) < 8) {
  LOG.println("[CONFIG] AP password must be at least 8 characters!");
  return false;
}
```

#### C. Boot Code (`MASS_Trap.ino`)

```cpp
// Helper
const char* getApPassword() {
  return (strlen(cfg.ap_password) >= 8) ? cfg.ap_password : NULL;
}

// Standalone mode:
WiFi.softAP(standaloneAP, getApPassword(), 1, cfg.ap_hidden, 4);

// WiFi+AP mode:
WiFi.softAP(hostname, getApPassword(), WiFi.channel(), cfg.ap_hidden, 4);

// Fallback AP:
WiFi.softAP(fallbackAP, getApPassword(), 1, false, 4);  // Not hidden in fallback

// Setup mode: ALWAYS OPEN
WiFi.softAP(apName);  // No password, not hidden
```

#### D. Config UI

```html
<div class="card-label">Soft AP Password</div>
<input type="password" id="apPassword" placeholder="Min 8 chars (blank = open)">
<div class="hint">WPA2 password for the device's access point. Leave blank for open access.
Setup mode AP is always open (for recovery).</div>
```

### Files to Modify

| File | Changes |
|------|---------|
| `config.h` | Add `char ap_password[33]` |
| `config.cpp` | Default, serialize, deserialize, validate (~10 lines) |
| `MASS_Trap.ino` | `getApPassword()` helper, pass to all `softAP()` calls (~10 lines) |
| `data/system.html` | Password input field (~8 lines) |

### Estimated Size

~30 lines C++, ~10 lines HTML/JS.

### Combine with #2

Implement together with Hidden SSIDs — both modify the same `softAP()` call signature.

---

## #11 — Speedtrap Update (v2.4.0 → v2.5.0)

### Problem

The speedtrap device at 192.168.1.55 is still running v2.4.0 firmware while finish and start gates are on v2.5.0. It needs to be updated.

### Current State

- Speedtrap IP: 192.168.1.55
- Current firmware: v2.4.0
- The speedtrap runs the same unified binary, just configured with `role=speedtrap`
- v2.5.0 has no breaking config changes — the speedtrap's existing `config.json` should work

### Update Options

#### Option A — PlatformIO OTA (Existing)

```bash
cd /Users/admin/MASS_Trap/v2.5.0
# If speedtrap supports OTA (has ArduinoOTA configured):
pio run -e ota -t upload
# May need to update platformio.ini ota target IP to 192.168.1.55
```

The `ota` environment in `platformio.ini` is configured for `masstrap.local:3232`. Need to check if the speedtrap's hostname resolves, or temporarily change the OTA target.

#### Option B — Web Firmware Update (New in v2.5.0)

If the speedtrap's current v2.4.0 firmware doesn't have the web update feature... it doesn't. The web update was just implemented. So this requires either:
1. PlatformIO OTA (if ArduinoOTA is in v2.4.0 — it should be)
2. USB flash

#### Option C — Fleet Update Phase 2 (#13)

Once implemented, the finish gate could push the update to the speedtrap over LAN. But #13 isn't built yet.

### Recommended Approach

1. Verify speedtrap is reachable: `ping 192.168.1.55`
2. Check if its ArduinoOTA is running: `pio run -e ota -t upload` with correct IP
3. If OTA works: flash v2.5.0 binary, verify via `/api/version`
4. If OTA doesn't work: USB flash

### Steps

```bash
cd /Users/admin/MASS_Trap/v2.5.0

# Build
pio run

# Option A: OTA (update platformio.ini temporarily or use direct command)
espota.py -i 192.168.1.55 -p 3232 -a admin -f .pio/build/mass-trap/firmware.bin

# Option B: USB (requires physical connection)
pio run -t upload
```

### Post-Update Verification

1. Browse to `http://192.168.1.55` or `http://masstrap-speed-XXXX.local`
2. Check `/api/version` returns v2.5.0
3. Verify speedtrap is beaconing and pairing with finish gate
4. Run a test race to verify speed data flows through

### This is an operational task, not a code change.

---

## #12 — WLED Update (v0.14.4 → v0.15.x)

### Problem

WLED device at 192.168.1.159 is running v0.14.4. The latest WLED is 0.15.x which has improved JSON API, better effect performance, and bug fixes.

### Compatibility Check

Our WLED integration (`wled_integration.cpp`) uses:
- `POST /json/state` with `{"on":true,"bri":255,"seg":[{"fx":N,"sx":128,"ix":128}]}`
- `GET /json/info` (proxied via `/api/wled/info`)
- `GET /json/effects` (proxied via `/api/wled/effects`)

These are all **stable WLED JSON API endpoints** that haven't changed between 0.14 and 0.15. The update should be transparent.

### Update Process

1. Browse to `http://192.168.1.159` (WLED UI)
2. Go to Config → Security & Updates → OTA Update
3. Download the correct WLED binary from [WLED Releases](https://github.com/Aircoookie/WLED/releases)
   - Board type matters — identify the WLED hardware (ESP32 variant)
4. Upload `.bin` file via WLED's built-in OTA
5. WLED reboots with new firmware

### Post-Update Verification

1. Browse to WLED UI — verify version shows 0.15.x
2. Test from M.A.S.S. Trap: arm a race → verify WLED changes to armed effect
3. Check `/api/wled/info` proxy still returns valid data
4. Check `/api/wled/effects` still returns effect list

### Risk

Low. WLED's JSON API is backward compatible. The only concern is if the hardware board type is wrong, but WLED's own OTA handles that.

### If WLED API Changed

If something broke in 0.15's API response format, the proxy endpoints in `web_server.cpp` may need minor adjustments. But this is unlikely.

### This is an operational task, not a code change.

---

## #13 — Fleet Update Phase 2 (LAN-Cached .bin Distribution)

### Problem

Currently, each device must individually download firmware from GitHub (or be flashed via USB/OTA). With 3+ devices on the same LAN, this means 3 separate GitHub downloads of the same ~1.6MB file. Plus, not all devices may have internet access (standalone mode, or the speedtrap behind the finish gate's AP).

### Concept

One device (the finish gate, as the "network leader") downloads the `.bin` once from GitHub, caches it in PSRAM, then serves it to peers over LAN HTTP. Other devices pull from the LAN cache instead of GitHub.

### Architecture

```
GitHub CDN → [Finish Gate] → PSRAM cache → local HTTP server
                                ↓
                    [Start Gate] pulls from finish gate LAN IP
                    [Speedtrap] pulls from finish gate LAN IP
```

### PSRAM Budget

- ESP32-S3-WROOM-1 N16R8 has **8MB PSRAM**
- Current firmware: ~1.6MB
- Max firmware: 3MB (partition size)
- PSRAM available at runtime: ~7MB after framework overhead
- Caching a 1.6MB binary in PSRAM: **feasible, ~20% of available PSRAM**

### Implementation

#### A. Firmware Cache in PSRAM

```cpp
// In web_server.cpp
static uint8_t* firmwareCache = nullptr;
static size_t firmwareCacheSize = 0;
static char firmwareCacheVersion[16] = "";
static char firmwareCacheMd5[33] = "";

// Cache the firmware in PSRAM after successful download
void cacheFirmwareInPSRAM(const uint8_t* data, size_t len, const char* version, const char* md5) {
  if (firmwareCache) {
    heap_caps_free(firmwareCache);
    firmwareCache = nullptr;
  }
  firmwareCache = (uint8_t*)heap_caps_malloc(len, MALLOC_CAP_SPIRAM);
  if (!firmwareCache) {
    LOG.printf("[FW-CACHE] PSRAM alloc failed for %u bytes\n", len);
    return;
  }
  memcpy(firmwareCache, data, len);
  firmwareCacheSize = len;
  strncpy(firmwareCacheVersion, version, sizeof(firmwareCacheVersion));
  strncpy(firmwareCacheMd5, md5, sizeof(firmwareCacheMd5));
  LOG.printf("[FW-CACHE] Cached %u bytes (v%s, MD5:%s)\n", len, version, md5);
}
```

#### B. Local Firmware Serve Endpoint

```
GET /api/firmware/serve
```

Streams the cached binary to requesting peers. Sets `Content-Length` and `x-MD5` headers for `HTTPUpdate` compatibility.

```cpp
static void handleFirmwareServe() {
  if (!firmwareCache || firmwareCacheSize == 0) {
    server.send(404, "text/plain", "No firmware cached");
    return;
  }
  server.sendHeader("Content-Length", String(firmwareCacheSize));
  server.sendHeader("x-MD5", firmwareCacheMd5);
  server.send(200, "application/octet-stream", "");
  server.sendContent_P((const char*)firmwareCache, firmwareCacheSize);
}
```

**Wait** — `server.sendContent_P()` expects PROGMEM, not PSRAM. Need to use chunked transfer:

```cpp
static void handleFirmwareServe() {
  if (!firmwareCache || firmwareCacheSize == 0) {
    server.send(404, "text/plain", "No firmware cached");
    return;
  }
  // Stream from PSRAM in 4KB chunks
  WiFiClient client = server.client();
  server.sendHeader("Content-Length", String(firmwareCacheSize));
  if (strlen(firmwareCacheMd5) > 0) {
    server.sendHeader("x-MD5", firmwareCacheMd5);
  }
  server.send(200, "application/octet-stream", "");

  size_t sent = 0;
  while (sent < firmwareCacheSize) {
    size_t chunk = min((size_t)4096, firmwareCacheSize - sent);
    client.write(firmwareCache + sent, chunk);
    sent += chunk;
    yield(); // Let WiFi stack breathe
  }
}
```

#### C. Peer Notification via ESP-NOW

When finish gate has a cached update, notify peers:

```cpp
#define MSG_UPDATE_AVAILABLE 19  // Finish gate → peers: "I have firmware vX.Y.Z"
```

The `offset` field encodes the firmware size. The `hostname` field contains the version string.

Peers receive this → their dashboard shows "Update available from finish gate. [Install]"

#### D. Peer-Side "Pull from LAN" Flow

When a peer's user clicks "Install from LAN":
```
POST /api/firmware/update-from-url
{
  "url": "http://192.168.1.83/api/firmware/serve",
  "md5": "abc123..."
}
```

This reuses the existing `processFirmwareUpdate()` machinery — it just points to a LAN URL instead of GitHub. The URL allowlist check needs to be relaxed for LAN IPs:

```cpp
// In handleFirmwareUpdateFromUrl():
bool isGitHub = url.startsWith(GITHUB_ASSET_PREFIX_1) || url.startsWith(GITHUB_ASSET_PREFIX_2);
bool isLanPeer = url.startsWith("http://192.168.") || url.startsWith("http://10.") || url.startsWith("http://172.");
if (!isGitHub && !isLanPeer) {
  server.send(403, "application/json", "{\"error\":\"URL not in allowlist\"}");
  return;
}
```

#### E. "Update All Devices" Button

On the finish gate's firmware update section:
```html
<button onclick="updateAllPeers()">Update All Brothers</button>
```

1. Finish gate checks it has firmware cached
2. Sends `MSG_UPDATE_AVAILABLE` to all paired peers
3. UI shows fleet update progress:
   - masstrap-start-a7b2: Downloading... → Rebooting... → ✓ v2.5.1
   - masstrap-speed-c3d4: Downloading... → Rebooting... → ✓ v2.5.1

#### F. Cache Lifecycle

- Firmware cached after successful GitHub download (in `processFirmwareUpdate()`)
- Cache survives until: device reboots, or user explicitly clears it
- Not persisted to flash (PSRAM only) — re-download after reboot is fine
- Free cache after all peers updated: `heap_caps_free(firmwareCache)`

### Files to Modify

| File | Changes |
|------|---------|
| `espnow_comm.h` | New message type `MSG_UPDATE_AVAILABLE` |
| `web_server.cpp` | PSRAM cache manager (~40 lines), `/api/firmware/serve` endpoint (~30 lines), cache after download (~10 lines), LAN URL allowlist (~5 lines) |
| `web_server.h` | No new declarations needed (cache is static to web_server.cpp) |
| `data/system.html` | "Update All Brothers" button + fleet progress UI (~40 lines) |

### Estimated Size

~120 lines C++, ~50 lines JS/HTML.

### Dependencies

- Firmware update feature (already implemented ✓)
- #3 (PMK encryption) — nice-to-have for firmware distribution security

### Risk

- **PSRAM allocation failure**: If PSRAM is fragmented or full, cache allocation fails gracefully (falls back to direct GitHub download per device)
- **HTTP streaming stability**: Serving 1.6MB over HTTP from ESP32 while other tasks run — test with WebSocket connections active
- **Concurrent updates**: Only one peer should pull at a time to avoid overwhelming the finish gate's web server. Sequence updates with 10s delays between peers

---

## #14 — Google Sheets AppScript Debugging

### Problem

The Google Sheets webhook URL is configured but **data never arrives in the spreadsheet**. The URL points to a Google Apps Script deployed by Gemini. Race data is sent from the browser JavaScript (not the ESP32) but the POST may be failing silently due to CORS, script errors, or mismatched field names.

### Current State

**Client-Side Code** (`data/index.html`, lines 1545-1558):

```javascript
function uploadToSheets(data, url) {
  fetch(url, {
    method: 'POST', mode: 'no-cors',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      timestamp: new Date().toISOString(),
      car: data.car,
      weight: data.weight,
      time: data.time,
      speed_mph: data.speed_mph,
      scale_mph: data.scale_mph,
      momentum: data.momentum,
      ke: data.ke
    })
  }).then(() => { status.textContent = 'Sent!'; })
    .catch(err => { status.textContent = 'Failed'; });
}
```

**Critical Issue**: `mode: 'no-cors'` means:
1. The browser sends an **opaque response** — JavaScript can't read the response body or status code
2. The `fetch().then()` always succeeds (even if the server returned an error) because the browser treats opaque responses as "ok"
3. So `'Sent!'` shows even when the data didn't actually land

**Webhook URL** (from backup JSON):
```
<REDACTED — Google Apps Script deployment URL>
```

### Diagnosis Results

#### Step 1: Webhook Test (COMPLETED)

```bash
curl -sL -X POST \
  "<REDACTED — Google Apps Script deployment URL>" \
  -H "Content-Type: application/json" \
  -d '{"timestamp":"2026-02-14T12:00:00Z","car":"TEST","weight":35,"time":1.234,"speed_mph":1.62,"scale_mph":103.7,"momentum":0.057,"ke":0.023}'
```

**Result: HTTP 401 — "Sorry, unable to open the file at this time"**

The Google Apps Script returns a Google Drive error page. This means one of:
- **The script deployment is set to "Only myself"** instead of "Anyone" — most likely cause
- **The deployment URL is stale** — Gemini may have redeployed, which generates a new URL
- **The script was deleted** from the user's Google Drive

**Root cause confirmed**: The script cannot be accessed anonymously. The `mode: 'no-cors'` in the browser fetch masked this error (opaque response always "succeeds"), so the UI always showed "Sent!" even though data was being rejected.

**Fix required**:
1. Open the Apps Script in Google (user must do this — needs their Google account)
2. Verify the code is intact (or replace with our known-working version below)
3. Deploy → New deployment → Type: Web app → Execute as: Me → Who has access: **Anyone**
4. Copy the **new** deployment URL → paste into M.A.S.S. Trap config
5. Test with curl again

#### Step 2: Examine the Apps Script

Access the script at: https://script.google.com/

The script likely has a `doPost(e)` function that:
1. Parses the JSON body from `e.postData.contents`
2. Opens a spreadsheet by ID
3. Appends a row with the data

**Common failure modes:**
- Script accesses `e.postData.getDataAsString()` instead of `e.postData.contents` (API changed)
- Script expects different field names than what we send
- Script doesn't handle CORS preflight (`doPost` exists but `doGet` returns wrong content type)
- Spreadsheet ID is wrong or permissions changed
- Script deployment scope is "Only myself" instead of "Anyone"

#### Step 3: Fix the Client-Side Code

Replace `mode: 'no-cors'` with proper CORS handling:

```javascript
function uploadToSheets(data, url) {
  var status = document.getElementById('sheetsStatus');
  status.textContent = 'Uploading...';
  status.style.color = 'var(--mass-blue)';

  var payload = {
    timestamp: new Date().toISOString(),
    car: data.car,
    weight: data.weight,
    time: data.time,
    speed_mph: data.speed_mph,
    scale_mph: data.scale_mph,
    momentum: data.momentum,
    ke: data.ke
  };

  // Google Apps Script deployed as "web app" with "Anyone" access
  // supports CORS via redirect. Use POST with redirect follow.
  fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain' },  // Avoid CORS preflight
    body: JSON.stringify(payload),
    redirect: 'follow'
  }).then(function(r) {
    if (r.ok) {
      status.textContent = 'Sent ✓';
      status.style.color = 'var(--mass-green)';
    } else {
      status.textContent = 'Error ' + r.status;
      status.style.color = 'var(--mass-red)';
    }
    setTimeout(function() { status.textContent = ''; }, 3000);
  }).catch(function(err) {
    status.textContent = 'Failed: ' + err.message;
    status.style.color = 'var(--mass-red)';
    console.log('[SHEETS] Upload error:', err);
  });
}
```

**Key change**: `Content-Type: text/plain` instead of `application/json`. This avoids triggering a CORS preflight request (which Google Apps Script doesn't handle well). The script still receives JSON in the body — it just has to parse it manually.

#### Step 4: Fix or Rewrite the Apps Script

If the existing script is broken, here's a known-working template:

```javascript
function doPost(e) {
  try {
    var sheet = SpreadsheetApp.openById("SPREADSHEET_ID_HERE").getActiveSheet();
    var data = JSON.parse(e.postData.contents);

    // Add header row if sheet is empty
    if (sheet.getLastRow() === 0) {
      sheet.appendRow(["Timestamp", "Car", "Weight (g)", "Time (s)",
                       "Speed (mph)", "Scale Speed (mph)", "Momentum", "KE (J)"]);
    }

    sheet.appendRow([
      data.timestamp || new Date().toISOString(),
      data.car || "Unknown",
      data.weight || 0,
      data.time || 0,
      data.speed_mph || 0,
      data.scale_mph || 0,
      data.momentum || 0,
      data.ke || 0
    ]);

    return ContentService.createTextOutput(
      JSON.stringify({result: "ok", row: sheet.getLastRow()})
    ).setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    return ContentService.createTextOutput(
      JSON.stringify({result: "error", message: error.toString()})
    ).setMimeType(ContentService.MimeType.JSON);
  }
}

function doGet(e) {
  return ContentService.createTextOutput(
    JSON.stringify({status: "MASS Trap Google Sheets Integration", version: "1.0"})
  ).setMimeType(ContentService.MimeType.JSON);
}
```

**Deployment settings:**
- Execute as: **Me** (sheet owner)
- Who has access: **Anyone** (no Google login required)
- After changing code: must click "New deployment" (not just save)

#### Step 5: Add Server-Side Fallback (Optional Enhancement)

Currently Sheets upload happens from the **browser** JavaScript. If the user closes the browser before upload completes, data is lost. Consider also posting from the ESP32:

```cpp
// In finish_gate.cpp, after race result calculation:
if (strlen(cfg.google_sheets_url) > 0 && !dryRunMode) {
  // Fire-and-forget HTTP POST (async, don't block race timing)
  // Use a background task or non-blocking HTTP
  postToGoogleSheets(elapsed_s, speed_ms, momentum, ke);
}
```

This is a nice-to-have but adds complexity (HTTPS from ESP32 to Google, redirect handling, etc.). The browser-side approach is simpler for now.

### Files to Modify

| File | Changes |
|------|---------|
| `data/index.html` | Fix `uploadToSheets()` function (~20 lines) |
| `data/dashboard.html` | Same fix if this file has the function |
| Google Apps Script | Rewrite/fix `doPost()` (external to this repo) |

### Estimated Size

~20 lines JS client-side. Google Apps Script is ~30 lines (external).

### Verification

1. `curl` the webhook URL → verify 200 response with `{result: "ok"}`
2. Run "Test Sheets Upload" from dashboard → verify `Sent ✓` and data appears in spreadsheet
3. Complete a real race → verify auto-upload works
4. Check `status.textContent` shows actual success/failure (not always "Sent" from opaque response)

---

## Implementation Priority / Dependency Graph

```
Independent (can implement in any order):
  #2  Hidden SSIDs          (trivial, 15 lines)
  #4  Password toggle       (trivial, 25 lines)
  #5  Brother rename        (cosmetic, 25 string replacements)
  #7  ID collision detect   (small, 30 lines)
  #11 Speedtrap update      (operational, no code)
  #12 WLED update           (operational, no code)
  #14 Google Sheets fix     (debugging + 20 lines)

Group A (security hardening, implement together):
  #10 Soft AP password  →  #2 Hidden SSIDs  (both modify softAP() calls)
  #3  PMK encryption    →  #9 FNG module    (PMK needed for secure onboarding)
  #1  Server-side auth  →  #8 Clone safety  (auth needed for approval API)

Group B (fleet management, sequential):
  #8  Clone peer safety  →  #9 FNG module  →  #13 Fleet update Phase 2

Standalone:
  #6  Setup wizard visuals  (independent visual overhaul)
```

### Suggested Implementation Order

1. **#4** Password toggle (trivial, immediate UX win)
2. **#5** Brother rename (cosmetic, quick)
3. **#14** Google Sheets debugging (diagnose first, may be a quick fix)
4. **#2 + #10** Hidden SSIDs + AP password (both touch same code, 30 lines total)
5. **#7** ID collision detection (small, independent)
6. **#1** Server-side auth gate (biggest security win, ~150 lines)
7. **#3** PMK encryption (ESP-NOW security, ~30 lines)
8. **#8** Clone peer safety (requires #1 for approval API)
9. **#6** Setup wizard visuals (can defer, only seen on first boot)
10. **#9** FNG module (requires #3 and #8)
11. **#11** Speedtrap update (operational, do after firmware stabilizes)
12. **#12** WLED update (operational, independent)
13. **#13** Fleet update Phase 2 (most complex, do last)

---

*End of plans. Ready for review and approval.*
