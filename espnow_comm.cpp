// ============================================================================
// M.A.S.S. TRAP — ESP-NOW Communication & Auto-Discovery
// "Brother's Six" Protocol — A cop always watches his brother's six.
//
// Zero-config peer discovery: devices find each other automatically via
// continuous ESP-NOW beacons. Role-aware pairing ensures a Start Gate
// links with a Finish Gate without any manual MAC address entry.
//
// Why ESP-NOW and not BLE?
//   ESP-NOW shares the same 2.4GHz radio as WiFi, coexisting natively
//   with zero extra hardware. BLE on the ESP32-S3 shares the same radio
//   AND requires its own BLE stack (~80KB RAM), which conflicts with
//   WiFi+ESP-NOW and adds latency. ESP-NOW gives us:
//     - Sub-1ms latency (vs 7.5ms+ BLE connection intervals)
//     - 250-byte payloads (vs 20-byte BLE characteristic writes)
//     - No pairing/bonding ceremony (vs BLE GATT setup)
//     - Native WiFi coexistence (AP_STA mode)
//     - Broadcast + unicast in one protocol
//   For a race timing system where microseconds matter, ESP-NOW wins.
//
// Protocol flow:
//   1. Every device broadcasts MSG_BEACON every 3s (forever, like a heartbeat)
//   2. On hearing a beacon, device replies with MSG_BEACON_ACK (direct)
//   3. If the sender's role is compatible, auto-send MSG_PAIR_REQ
//   4. Recipient confirms with MSG_PAIR_ACK → both sides save to /peers.json
//   5. Once paired, normal race messages flow (PING, START, CONFIRM, etc.)
//   6. Peer status tracked: ONLINE (<15s), STALE (<60s), OFFLINE (>60s)
//   7. On reboot, persisted peers re-register immediately — instant reconnect
//
// Overhead: One 64-byte broadcast every 3 seconds = ~21 bytes/sec average.
// WiFi throughput is ~2MB/s. This is 0.001% of the radio capacity.
// ============================================================================

#include "espnow_comm.h"
#include "config.h"
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <WiFi.h>

// ============================================================================
// GLOBAL STATE
// ============================================================================
volatile RaceState raceState = IDLE;
bool dryRunMode = false;
int64_t clockOffset_us = 0;
bool peerConnected = false;
unsigned long lastPeerSeen = 0;

KnownPeer peers[MAX_PEERS];
int peerCount = 0;

// Fleet management
volatile bool identifyActive = false;
unsigned long identifyStartMs = 0;

// Pending WiFi config change (deferred until IDLE to avoid mid-race reboot)
static bool wifiConfigPending = false;
static char pendingSSID[33] = {0};
static char pendingPass[65] = {0};

// Deferred WiFi reconnect (CMD_WIFI_RECONNECT sets this flag; main loop handles it)
// WiFi APIs are NOT thread-safe — must only be called from Core 1 (main loop),
// never from ESP-NOW callback (Core 0).
volatile bool wifiReconnectRequested = false;

// Timing
static unsigned long lastBeaconTime = 0;
static unsigned long lastPeerCheck = 0;
static bool needsSave = false;             // Deferred save flag
static unsigned long saveRequestedAt = 0;  // Debounce to reduce flash wear

// ============================================================================
// ROLE COMPATIBILITY — Who should pair with whom?
// ============================================================================
static bool isCompatibleRole(const char* myRole, const char* theirRole) {
  // Start ↔ Finish (timing link)
  if (strcmp(myRole, "start") == 0 && strcmp(theirRole, "finish") == 0) return true;
  if (strcmp(myRole, "finish") == 0 && strcmp(theirRole, "start") == 0) return true;

  // Speedtrap ↔ Finish (speed data flows to dashboard)
  if (strcmp(myRole, "speedtrap") == 0 && strcmp(theirRole, "finish") == 0) return true;
  if (strcmp(myRole, "finish") == 0 && strcmp(theirRole, "speedtrap") == 0) return true;

  // Telemetry ↔ Finish (IMU data flows to dashboard)
  if (strcmp(myRole, "telemetry") == 0 && strcmp(theirRole, "finish") == 0) return true;
  if (strcmp(myRole, "finish") == 0 && strcmp(theirRole, "telemetry") == 0) return true;

  return false;
}

// ============================================================================
// MICROSECOND TIMER
// ============================================================================
uint64_t IRAM_ATTR nowUs() {
  return esp_timer_get_time();
}

// ============================================================================
// HELPER: Build an ESPMessage with our identity
// ============================================================================
static void buildMessage(ESPMessage& msg, uint8_t type, uint64_t timestamp, int64_t offset) {
  msg.type = type;
  msg.senderId = cfg.device_id;
  msg.timestamp = timestamp;
  msg.offset = offset;
  strncpy(msg.role, cfg.role, sizeof(msg.role) - 1);
  msg.role[sizeof(msg.role) - 1] = '\0';
  strncpy(msg.hostname, cfg.hostname, sizeof(msg.hostname) - 1);
  msg.hostname[sizeof(msg.hostname) - 1] = '\0';
}

// ============================================================================
// HELPER: Ensure a MAC is registered as an ESP-NOW peer
// ============================================================================
static bool ensureESPNowPeer(const uint8_t* mac) {
  if (esp_now_is_peer_exist(mac)) return true;

  esp_now_peer_info_t peerInfo = {};
  memcpy(peerInfo.peer_addr, mac, 6);
  peerInfo.channel = 0;
  peerInfo.encrypt = false;
  return esp_now_add_peer(&peerInfo) == ESP_OK;
}

// ============================================================================
// HELPER: Format MAC for logging
// ============================================================================
static String macToStr(const uint8_t* mac) {
  char buf[18];
  snprintf(buf, sizeof(buf), "%02X:%02X:%02X:%02X:%02X:%02X",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  return String(buf);
}

// ============================================================================
// PEER REGISTRY OPERATIONS
// ============================================================================

int findPeerByMac(const uint8_t* mac) {
  for (int i = 0; i < peerCount; i++) {
    if (memcmp(peers[i].mac, mac, 6) == 0) return i;
  }
  return -1;
}

int findPeerByRole(const char* role) {
  // Prefer online paired peers
  for (int i = 0; i < peerCount; i++) {
    if (peers[i].paired && strcmp(peers[i].role, role) == 0) {
      PeerStatus st = getPeerStatus(peers[i]);
      if (st == PEER_ONLINE || st == PEER_STALE) return i;
    }
  }
  // Fallback: any paired peer with that role (even offline — for boot-up sends)
  for (int i = 0; i < peerCount; i++) {
    if (peers[i].paired && strcmp(peers[i].role, role) == 0) return i;
  }
  return -1;
}

PeerStatus getPeerStatus(const KnownPeer& peer) {
  if (peer.lastSeen == 0) return PEER_OFFLINE;  // Never seen this session
  unsigned long age = millis() - peer.lastSeen;
  if (age < PEER_ONLINE_THRESH_MS) return PEER_ONLINE;
  if (age < PEER_STALE_THRESH_MS) return PEER_STALE;
  return PEER_OFFLINE;
}

bool hasOnlinePeer() {
  for (int i = 0; i < peerCount; i++) {
    if (peers[i].paired && getPeerStatus(peers[i]) == PEER_ONLINE) return true;
  }
  return false;
}

// Add or update a peer in the registry (does NOT auto-pair — that's explicit)
static int upsertPeer(const uint8_t* mac, const char* role, const char* hostname, uint8_t deviceId) {
  int idx = findPeerByMac(mac);

  if (idx >= 0) {
    // Update existing entry
    strncpy(peers[idx].role, role, sizeof(peers[idx].role) - 1);
    strncpy(peers[idx].hostname, hostname, sizeof(peers[idx].hostname) - 1);
    peers[idx].deviceId = deviceId;
    peers[idx].lastSeen = millis();
    return idx;
  }

  // Add new entry
  if (peerCount >= MAX_PEERS) {
    // Registry full — evict oldest unpaired peer first, then oldest offline
    int evictIdx = -1;
    unsigned long oldest = ULONG_MAX;
    for (int i = 0; i < peerCount; i++) {
      if (!peers[i].paired && peers[i].lastSeen < oldest) {
        oldest = peers[i].lastSeen;
        evictIdx = i;
      }
    }
    if (evictIdx < 0) {
      oldest = ULONG_MAX;
      for (int i = 0; i < peerCount; i++) {
        if (getPeerStatus(peers[i]) == PEER_OFFLINE && peers[i].lastSeen < oldest) {
          oldest = peers[i].lastSeen;
          evictIdx = i;
        }
      }
    }
    if (evictIdx < 0) {
      LOG.println("[PEERS] Registry full — cannot add peer");
      return -1;
    }
    esp_now_del_peer(peers[evictIdx].mac);
    for (int i = evictIdx; i < peerCount - 1; i++) {
      peers[i] = peers[i + 1];
    }
    peerCount--;
  }

  idx = peerCount;
  memcpy(peers[idx].mac, mac, 6);
  strncpy(peers[idx].role, role, sizeof(peers[idx].role) - 1);
  peers[idx].role[sizeof(peers[idx].role) - 1] = '\0';
  strncpy(peers[idx].hostname, hostname, sizeof(peers[idx].hostname) - 1);
  peers[idx].hostname[sizeof(peers[idx].hostname) - 1] = '\0';
  peers[idx].deviceId = deviceId;
  peers[idx].lastSeen = millis();
  peers[idx].espnowRegistered = false;
  peers[idx].paired = false;
  peerCount++;

  LOG.printf("[PEERS] New device: %s (%s) @ %s\n", hostname, role, macToStr(mac).c_str());
  return idx;
}

void forgetPeer(const uint8_t* mac) {
  int idx = findPeerByMac(mac);
  if (idx < 0) return;

  LOG.printf("[PEERS] Forgetting: %s (%s)\n", peers[idx].hostname, peers[idx].role);
  esp_now_del_peer(mac);

  for (int i = idx; i < peerCount - 1; i++) {
    peers[i] = peers[i + 1];
  }
  peerCount--;
  savePeers();
}

void forgetAllPeers() {
  LOG.println("[PEERS] Forgetting ALL peers");
  for (int i = 0; i < peerCount; i++) {
    esp_now_del_peer(peers[i].mac);
  }
  peerCount = 0;
  LittleFS.remove("/peers.json");
}

// ============================================================================
// PEER PERSISTENCE — /peers.json on LittleFS
// Separate from config.json so pairing changes don't require a reboot.
// ============================================================================

void loadPeers() {
  if (!LittleFS.exists("/peers.json")) {
    LOG.println("[PEERS] No saved peers — fresh start");
    return;
  }

  File f = LittleFS.open("/peers.json", "r");
  if (!f) return;
  String json = f.readString();
  f.close();

  StaticJsonDocument<1024> doc;
  DeserializationError err = deserializeJson(doc, json);
  if (err) {
    LOG.printf("[PEERS] Bad peers.json: %s\n", err.c_str());
    return;
  }

  JsonArray arr = doc.as<JsonArray>();
  for (JsonObject obj : arr) {
    if (peerCount >= MAX_PEERS) break;

    const char* macStr = obj["mac"] | "";
    uint8_t mac[6];
    if (!parseMacString(macStr, mac)) continue;

    int idx = peerCount;
    memcpy(peers[idx].mac, mac, 6);
    strncpy(peers[idx].role, obj["role"] | "", sizeof(peers[idx].role) - 1);
    peers[idx].role[sizeof(peers[idx].role) - 1] = '\0';
    strncpy(peers[idx].hostname, obj["hostname"] | "", sizeof(peers[idx].hostname) - 1);
    peers[idx].hostname[sizeof(peers[idx].hostname) - 1] = '\0';
    peers[idx].deviceId = obj["id"] | 0;
    peers[idx].lastSeen = 0;  // Haven't heard from them yet this session
    peers[idx].espnowRegistered = false;
    peers[idx].paired = obj["paired"] | false;
    peerCount++;

    LOG.printf("[PEERS] Restored: %s (%s) paired=%s\n",
                  peers[idx].hostname, peers[idx].role,
                  peers[idx].paired ? "yes" : "no");
  }

  LOG.printf("[PEERS] Loaded %d saved peer(s)\n", peerCount);
}

void savePeers() {
  StaticJsonDocument<1024> doc;
  JsonArray arr = doc.to<JsonArray>();

  for (int i = 0; i < peerCount; i++) {
    if (!peers[i].paired) continue;  // Only save paired peers

    JsonObject obj = arr.createNestedObject();
    obj["mac"] = macToStr(peers[i].mac);
    obj["role"] = peers[i].role;
    obj["hostname"] = peers[i].hostname;
    obj["id"] = peers[i].deviceId;
    obj["paired"] = true;
  }

  File f = LittleFS.open("/peers.json", "w");
  if (!f) {
    LOG.println("[PEERS] Failed to write peers.json!");
    return;
  }
  serializeJson(doc, f);
  f.close();
  LOG.printf("[PEERS] Saved %d paired peer(s) to flash\n", arr.size());
}

// Request a deferred save (debounced to reduce flash wear)
static void requestSave() {
  needsSave = true;
  saveRequestedAt = millis();
}

// ============================================================================
// JSON EXPORT — For web API (/api/peers)
// ============================================================================
String getPeersJson() {
  StaticJsonDocument<2048> doc;
  JsonArray arr = doc.to<JsonArray>();

  for (int i = 0; i < peerCount; i++) {
    JsonObject obj = arr.createNestedObject();
    obj["mac"] = macToStr(peers[i].mac);
    obj["role"] = peers[i].role;
    obj["hostname"] = peers[i].hostname;
    obj["id"] = peers[i].deviceId;
    obj["paired"] = peers[i].paired;

    PeerStatus st = getPeerStatus(peers[i]);
    obj["status"] = (st == PEER_ONLINE) ? "online" :
                    (st == PEER_STALE) ? "stale" : "offline";
    obj["lastSeen"] = peers[i].lastSeen > 0 ?
                      (int)((millis() - peers[i].lastSeen) / 1000) : -1;

    // Beacon diagnostics (if we've received at least one beacon with data)
    if (peers[i].diag.valid) {
      JsonObject d = obj.createNestedObject("diag");
      d["uptimeMin"]  = peers[i].diag.uptimeMin;
      d["freeHeapKB"] = peers[i].diag.freeHeapKB;
      d["rssi"]       = peers[i].diag.rssi;
      const char* stateStr = "UNKNOWN";
      switch (peers[i].diag.raceState) {
        case IDLE:     stateStr = "IDLE";     break;
        case ARMED:    stateStr = "ARMED";    break;
        case RACING:   stateStr = "RACING";   break;
        case FINISHED: stateStr = "FINISHED"; break;
      }
      d["raceState"]  = stateStr;
      char fwBuf[12];
      snprintf(fwBuf, sizeof(fwBuf), "%d.%d", peers[i].diag.fwMajor, peers[i].diag.fwMinor);
      d["fwVersion"]  = fwBuf;
    }
  }

  String output;
  serializeJson(doc, output);
  return output;
}

// Forward declarations for fleet management handlers (defined after discoveryLoop)
static void handleWiFiConfig(const WiFiConfigMsg& wcfg, const uint8_t* srcMac);
static void handleRemoteCmd(const RemoteCmdMsg& rcmd, const uint8_t* srcMac);

// ============================================================================
// ESP-NOW RECEIVE CALLBACK — Heart of the "Brother's Six" protocol
// ============================================================================
static void onDataRecv(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
  if (len < 1) return;

  // DEBUG: Uncomment to log unknown traffic (floods ring buffer at ~2/sec/peer)
  // LOG.printf("[ESPNOW-RX] type=%d len=%d from=%02X:%02X:%02X:%02X:%02X:%02X\n",
  //           data[0], len, info->src_addr[0], info->src_addr[1], info->src_addr[2],
  //           info->src_addr[3], info->src_addr[4], info->src_addr[5]);

  // ---- VARIABLE-SIZE MESSAGES: Route by type byte BEFORE size check ----

  // Telemetry messages (232 bytes for chunks) — finish gate only
  if (strcmp(cfg.role, "finish") == 0) {
    uint8_t msgType = data[0];
    if (msgType == MSG_TELEM_HEADER && len >= (int)sizeof(TelemetryHeader)) {
      TelemetryHeader hdr;
      memcpy(&hdr, data, sizeof(hdr));
      onTelemetryHeader(info->src_addr, hdr);
      return;
    }
    if (msgType == MSG_TELEM_CHUNK && len >= (int)sizeof(TelemetryChunk)) {
      TelemetryChunk chunk;
      memcpy(&chunk, data, sizeof(chunk));
      onTelemetryChunk(info->src_addr, chunk);
      return;
    }
    if (msgType == MSG_TELEM_END && len >= (int)sizeof(TelemetryEnd)) {
      TelemetryEnd end;
      memcpy(&end, data, sizeof(end));
      onTelemetryEnd(info->src_addr, end);
      return;
    }
  }

  // Fleet management messages (all roles receive these)
  {
    uint8_t msgType = data[0];
    if (msgType == MSG_WIFI_CONFIG && len >= (int)sizeof(WiFiConfigMsg)) {
      WiFiConfigMsg wcfg;
      memcpy(&wcfg, data, sizeof(wcfg));
      handleWiFiConfig(wcfg, info->src_addr);
      return;
    }
    if (msgType == MSG_REMOTE_CMD && len >= (int)sizeof(RemoteCmdMsg)) {
      RemoteCmdMsg rcmd;
      memcpy(&rcmd, data, sizeof(rcmd));
      handleRemoteCmd(rcmd, info->src_addr);
      return;
    }
  }

  // ---- STANDARD MESSAGES: Fixed 56-byte ESPMessage ----
  if (len != (int)sizeof(ESPMessage)) return;

  ESPMessage msg;
  memcpy(&msg, data, sizeof(msg));
  uint64_t receiveTime = nowUs();

  // ---- BEACON: Someone broadcasting their presence ----
  if (msg.type == MSG_BEACON) {
    int idx = upsertPeer(info->src_addr, msg.role, msg.hostname, msg.senderId);
    if (idx < 0) return;

    // Unpack beacon diagnostics from offset field
    if (msg.offset != 0) {
      unpackBeaconDiag(msg.offset, peers[idx].diag);
    }

    // Register in ESP-NOW so we can reply directly
    if (!peers[idx].espnowRegistered) {
      if (ensureESPNowPeer(info->src_addr)) {
        peers[idx].espnowRegistered = true;
      }
    }

    // Reply with ACK so they know we exist (with our diagnostics too)
    ESPMessage ack;
    buildMessage(ack, MSG_BEACON_ACK, nowUs(), packBeaconDiag());
    esp_now_send(info->src_addr, (uint8_t*)&ack, sizeof(ack));

    // Auto-pair: if compatible and not yet paired → initiate
    if (!peers[idx].paired && isCompatibleRole(cfg.role, msg.role)) {
      LOG.printf("[PEERS] Compatible: %s (%s) — requesting pair\n",
                    msg.hostname, msg.role);
      ESPMessage req;
      buildMessage(req, MSG_PAIR_REQ, nowUs(), 0);
      esp_now_send(info->src_addr, (uint8_t*)&req, sizeof(req));
    }
    return;
  }

  // ---- BEACON_ACK: Direct reply to our beacon ----
  if (msg.type == MSG_BEACON_ACK) {
    int idx = upsertPeer(info->src_addr, msg.role, msg.hostname, msg.senderId);
    if (idx < 0) return;

    // Unpack beacon diagnostics from offset field
    if (msg.offset != 0) {
      unpackBeaconDiag(msg.offset, peers[idx].diag);
    }

    if (!peers[idx].espnowRegistered) {
      if (ensureESPNowPeer(info->src_addr)) {
        peers[idx].espnowRegistered = true;
      }
    }

    // Auto-pair if compatible and not yet paired
    if (!peers[idx].paired && isCompatibleRole(cfg.role, msg.role)) {
      LOG.printf("[PEERS] Compatible ACK: %s (%s) — requesting pair\n",
                    msg.hostname, msg.role);
      ESPMessage req;
      buildMessage(req, MSG_PAIR_REQ, nowUs(), 0);
      esp_now_send(info->src_addr, (uint8_t*)&req, sizeof(req));
    }
    return;
  }

  // ---- PAIR_REQ: "I want to pair with you" ----
  if (msg.type == MSG_PAIR_REQ) {
    if (!isCompatibleRole(cfg.role, msg.role)) {
      LOG.printf("[PEERS] Rejected pair: incompatible %s (%s)\n",
                    msg.hostname, msg.role);
      return;
    }

    int idx = upsertPeer(info->src_addr, msg.role, msg.hostname, msg.senderId);
    if (idx < 0) return;

    if (!peers[idx].espnowRegistered) {
      ensureESPNowPeer(info->src_addr);
      peers[idx].espnowRegistered = true;
    }

    peers[idx].paired = true;
    LOG.printf("[PEERS] ★ PAIRED with %s (%s) @ %s\n",
                  msg.hostname, msg.role, macToStr(info->src_addr).c_str());

    // Confirm
    ESPMessage ack;
    buildMessage(ack, MSG_PAIR_ACK, nowUs(), 0);
    esp_now_send(info->src_addr, (uint8_t*)&ack, sizeof(ack));

    requestSave();
    return;
  }

  // ---- PAIR_ACK: Pairing confirmed by the other side ----
  if (msg.type == MSG_PAIR_ACK) {
    int idx = findPeerByMac(info->src_addr);
    if (idx < 0) {
      idx = upsertPeer(info->src_addr, msg.role, msg.hostname, msg.senderId);
      if (idx < 0) return;
    }

    if (!peers[idx].paired) {
      peers[idx].paired = true;
      LOG.printf("[PEERS] ★ PAIR CONFIRMED: %s (%s)\n", msg.hostname, msg.role);
      requestSave();
    }
    return;
  }

  // ---- ALL OTHER MESSAGES: Track presence, then dispatch ----

  // Update lastSeen for any known peer
  int idx = findPeerByMac(info->src_addr);
  if (idx >= 0) {
    peers[idx].lastSeen = millis();
  }

  // Legacy peerConnected tracking
  if (msg.type == MSG_PING || msg.type == MSG_PONG) {
    peerConnected = true;
    lastPeerSeen = millis();
  }

  // Dispatch to role-specific handler
  if (strcmp(cfg.role, "finish") == 0) {
    onFinishGateESPNow(msg, receiveTime);
  } else if (strcmp(cfg.role, "start") == 0) {
    onStartGateESPNow(msg, receiveTime);
  } else if (strcmp(cfg.role, "speedtrap") == 0) {
    onSpeedTrapESPNow(msg, receiveTime);
  }
}

// ============================================================================
// INITIALIZATION
// ============================================================================
void initESPNow() {
  if (esp_now_init() != ESP_OK) {
    LOG.println("[ESP-NOW] Init FAILED!");
    return;
  }

  esp_now_register_recv_cb(onDataRecv);

  // Broadcast peer for beacons
  esp_now_peer_info_t broadcastPeer = {};
  memset(broadcastPeer.peer_addr, 0xFF, 6);
  broadcastPeer.channel = 0;
  broadcastPeer.encrypt = false;
  esp_now_add_peer(&broadcastPeer);

  // Restore persisted peers and pre-register in ESP-NOW for instant reconnect
  loadPeers();
  for (int i = 0; i < peerCount; i++) {
    if (ensureESPNowPeer(peers[i].mac)) {
      peers[i].espnowRegistered = true;
    }
  }

  // Legacy: if config has a manual peer_mac (old firmware), honor it
  bool hasManualMac = false;
  for (int i = 0; i < 6; i++) {
    if (cfg.peer_mac[i] != 0) { hasManualMac = true; break; }
  }
  if (hasManualMac) {
    int idx = findPeerByMac(cfg.peer_mac);
    if (idx < 0) {
      idx = upsertPeer(cfg.peer_mac, "unknown", "manual-peer", 0);
    }
    if (idx >= 0) {
      peers[idx].paired = true;
      if (!peers[idx].espnowRegistered) {
        ensureESPNowPeer(peers[idx].mac);
        peers[idx].espnowRegistered = true;
      }
      LOG.printf("[PEERS] Legacy manual peer: %s\n", formatMac(cfg.peer_mac).c_str());
    }
  }

  LOG.printf("[ESP-NOW] Brother's Six active — %d peer(s) in registry\n", peerCount);
}

// ============================================================================
// MESSAGING
// ============================================================================

void sendToMac(const uint8_t* mac, uint8_t type, uint64_t timestamp, int64_t offset) {
  ensureESPNowPeer(mac);
  ESPMessage msg;
  buildMessage(msg, type, timestamp, offset);
  esp_now_send(mac, (uint8_t*)&msg, sizeof(msg));
}

void sendToPeer(uint8_t type, uint64_t timestamp, int64_t offset) {
  // Legacy convenience: send to the primary complementary peer
  //   start gate    → finish gate
  //   finish gate   → start gate
  //   speed trap    → finish gate

  const char* targetRole = NULL;
  if (strcmp(cfg.role, "start") == 0)          targetRole = "finish";
  else if (strcmp(cfg.role, "finish") == 0)     targetRole = "start";
  else if (strcmp(cfg.role, "speedtrap") == 0)  targetRole = "finish";

  if (targetRole) {
    int idx = findPeerByRole(targetRole);
    if (idx >= 0) {
      sendToMac(peers[idx].mac, type, timestamp, offset);
      return;
    }
  }

  // Last resort: try legacy manual MAC from config
  bool hasManualMac = false;
  for (int i = 0; i < 6; i++) {
    if (cfg.peer_mac[i] != 0) { hasManualMac = true; break; }
  }
  if (hasManualMac) {
    sendToMac(cfg.peer_mac, type, timestamp, offset);
  }
}

// ============================================================================
// BEACON DIAGNOSTICS — Pack/unpack live telemetry in beacon offset field
// ============================================================================

int64_t packBeaconDiag() {
  uint16_t upMin  = (uint16_t)(millis() / 60000UL);
  uint16_t heapKB = (uint16_t)(ESP.getFreeHeap() / 1024);
  uint8_t rssiEnc = (uint8_t)((int16_t)WiFi.RSSI() + 128);
  uint8_t state   = (uint8_t)raceState;

  // Parse FIRMWARE_VERSION "2.6.0-beta" → major=2, minor=6
  uint8_t fwMaj = 0, fwMin = 0;
  sscanf(FIRMWARE_VERSION, "%hhu.%hhu", &fwMaj, &fwMin);

  int64_t packed = 0;
  packed |= ((int64_t)upMin   << 48);
  packed |= ((int64_t)heapKB  << 32);
  packed |= ((int64_t)rssiEnc << 24);
  packed |= ((int64_t)state   << 16);
  packed |= ((int64_t)fwMaj   << 8);
  packed |= ((int64_t)fwMin);
  return packed;
}

void unpackBeaconDiag(int64_t packed, PeerDiagnostics& out) {
  out.uptimeMin  = (uint16_t)((packed >> 48) & 0xFFFF);
  out.freeHeapKB = (uint16_t)((packed >> 32) & 0xFFFF);
  out.rssi       = (int8_t)((packed >> 24) & 0xFF) - 128;
  out.raceState  = (uint8_t)((packed >> 16) & 0xFF);
  out.fwMajor    = (uint8_t)((packed >> 8) & 0xFF);
  out.fwMinor    = (uint8_t)(packed & 0xFF);
  out.valid      = true;
}

// ============================================================================
// FLEET MANAGEMENT — WiFi sharing and remote commands
// ============================================================================

// Verify that a sender is a paired "finish" peer (security: only hub can push commands)
static bool isAuthorizedSender(const uint8_t* srcMac) {
  int idx = findPeerByMac(srcMac);
  if (idx < 0) return false;
  return peers[idx].paired && strcmp(peers[idx].role, "finish") == 0;
}

// Handle incoming WiFi config from finish gate
static void handleWiFiConfig(const WiFiConfigMsg& wcfg, const uint8_t* srcMac) {
  // Security: only accept from paired finish gate
  if (!isAuthorizedSender(srcMac)) {
    LOG.printf("[FLEET] WiFi config rejected — sender not authorized (%s)\n",
               macToStr(srcMac).c_str());
    return;
  }

  LOG.printf("[FLEET] WiFi config received from %s: SSID='%s'\n",
             wcfg.senderRole, wcfg.ssid);

  // Check if creds are different from current config
  if (strcmp(cfg.wifi_ssid, wcfg.ssid) == 0 && strcmp(cfg.wifi_pass, wcfg.pass) == 0) {
    LOG.println("[FLEET] WiFi config unchanged — ignoring");
    return;
  }

  // Defer reboot until race is IDLE (sanity check #7 in plan)
  if (raceState != IDLE) {
    LOG.println("[FLEET] WiFi config queued — waiting for IDLE state before applying");
    strncpy(pendingSSID, wcfg.ssid, sizeof(pendingSSID) - 1);
    pendingSSID[sizeof(pendingSSID) - 1] = '\0';
    strncpy(pendingPass, wcfg.pass, sizeof(pendingPass) - 1);
    pendingPass[sizeof(pendingPass) - 1] = '\0';
    wifiConfigPending = true;
    return;
  }

  // Apply immediately
  strncpy(cfg.wifi_ssid, wcfg.ssid, sizeof(cfg.wifi_ssid) - 1);
  cfg.wifi_ssid[sizeof(cfg.wifi_ssid) - 1] = '\0';
  strncpy(cfg.wifi_pass, wcfg.pass, sizeof(cfg.wifi_pass) - 1);
  cfg.wifi_pass[sizeof(cfg.wifi_pass) - 1] = '\0';
  saveConfig();
  LOG.println("[FLEET] WiFi config updated — rebooting in 2 seconds...");
  delay(2000);
  ESP.restart();
}

// Handle incoming remote command from finish gate
static void handleRemoteCmd(const RemoteCmdMsg& rcmd, const uint8_t* srcMac) {
  // Security: only accept from paired finish gate
  if (!isAuthorizedSender(srcMac)) {
    LOG.printf("[FLEET] Remote command rejected — sender not authorized (%s)\n",
               macToStr(srcMac).c_str());
    return;
  }

  LOG.printf("[FLEET] Remote command %d from %s (param=%u)\n",
             rcmd.command, rcmd.senderRole, rcmd.param);

  switch (rcmd.command) {
    case CMD_REBOOT:
      LOG.println("[FLEET] Remote reboot command — restarting in 1 second...");
      delay(1000);
      ESP.restart();
      break;

    case CMD_IDENTIFY:
      LOG.println("[FLEET] Identify command — LED rapid blink for 10 seconds");
      identifyActive = true;
      identifyStartMs = millis();
      break;

    case CMD_DIAG_REPORT: {
      // Send back detailed diagnostics in a PONG with packed offset
      int64_t diag = packBeaconDiag();
      sendToMac(srcMac, MSG_PONG, nowUs(), diag);
      LOG.println("[FLEET] Diagnostics report sent");
      break;
    }

    case CMD_WIFI_RECONNECT:
      LOG.println("[FLEET] WiFi reconnect requested — deferring to main loop");
      wifiReconnectRequested = true;  // Handled in MASS_Trap.ino loop() (thread-safe)
      break;

    default:
      LOG.printf("[FLEET] Unknown command: %d\n", rcmd.command);
      break;
  }
}

void sendWiFiConfig(const uint8_t* mac) {
  WiFiConfigMsg wcfg;
  memset(&wcfg, 0, sizeof(wcfg));
  wcfg.type = MSG_WIFI_CONFIG;
  wcfg.senderId = cfg.device_id;
  strncpy(wcfg.ssid, cfg.wifi_ssid, sizeof(wcfg.ssid) - 1);
  strncpy(wcfg.pass, cfg.wifi_pass, sizeof(wcfg.pass) - 1);
  strncpy(wcfg.senderRole, cfg.role, sizeof(wcfg.senderRole) - 1);

  ensureESPNowPeer(mac);
  esp_now_send(mac, (uint8_t*)&wcfg, sizeof(wcfg));
  LOG.printf("[FLEET] WiFi config sent to %s\n", macToStr(mac).c_str());
}

void sendWiFiConfigAll() {
  int sent = 0;
  for (int i = 0; i < peerCount; i++) {
    if (peers[i].paired) {
      sendWiFiConfig(peers[i].mac);
      sent++;
      delay(5);  // Small gap to avoid ESP-NOW flooding
    }
  }
  LOG.printf("[FLEET] WiFi config broadcast to %d paired peer(s)\n", sent);
}

void sendRemoteCmd(const uint8_t* mac, uint8_t cmd, uint32_t param) {
  RemoteCmdMsg rcmd;
  memset(&rcmd, 0, sizeof(rcmd));
  rcmd.type = MSG_REMOTE_CMD;
  rcmd.senderId = cfg.device_id;
  rcmd.command = cmd;
  rcmd.param = param;
  strncpy(rcmd.senderRole, cfg.role, sizeof(rcmd.senderRole) - 1);

  ensureESPNowPeer(mac);
  esp_now_send(mac, (uint8_t*)&rcmd, sizeof(rcmd));
  LOG.printf("[FLEET] Command %d sent to %s\n", cmd, macToStr(mac).c_str());
}

// ============================================================================
// DISCOVERY LOOP — Called every iteration of main loop()
//
// The beacon runs FOREVER (not just 30 seconds). This is by design:
//   - Devices can be powered on at any time / in any order
//   - If a device reboots mid-session, it re-pairs in ~3 seconds
//   - If a new device is added to the track, it joins automatically
//   - Total radio overhead: ~21 bytes/sec (0.001% of WiFi capacity)
// ============================================================================
void discoveryLoop() {
  unsigned long now = millis();

  // ---- Beacon every 2 seconds (with packed diagnostics) ----
  if (now - lastBeaconTime > BEACON_INTERVAL_MS) {
    ESPMessage msg;
    buildMessage(msg, MSG_BEACON, nowUs(), packBeaconDiag());
    uint8_t broadcastAddr[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    esp_now_send(broadcastAddr, (uint8_t*)&msg, sizeof(msg));
    lastBeaconTime = now;
  }

  // ---- Peer health check every 5 seconds ----
  if (now - lastPeerCheck > PEER_HEALTH_CHECK_MS) {
    lastPeerCheck = now;

    // Update legacy peerConnected flag
    peerConnected = hasOnlinePeer();
    if (peerConnected) lastPeerSeen = now;
  }

  // ---- Deferred save (debounce 2s to reduce flash wear) ----
  if (needsSave && now - saveRequestedAt > PEER_SAVE_DEBOUNCE_MS) {
    needsSave = false;
    savePeers();
  }

  // ---- Apply pending WiFi config when race is IDLE (safety: avoid mid-race reboot) ----
  if (wifiConfigPending && raceState == IDLE) {
    wifiConfigPending = false;
    LOG.println("[FLEET] Applying deferred WiFi config now (race is IDLE)");
    strncpy(cfg.wifi_ssid, pendingSSID, sizeof(cfg.wifi_ssid) - 1);
    cfg.wifi_ssid[sizeof(cfg.wifi_ssid) - 1] = '\0';
    strncpy(cfg.wifi_pass, pendingPass, sizeof(cfg.wifi_pass) - 1);
    cfg.wifi_pass[sizeof(cfg.wifi_pass) - 1] = '\0';
    saveConfig();
    LOG.println("[FLEET] WiFi config updated — rebooting in 2 seconds...");
    delay(2000);
    ESP.restart();
  }
}
