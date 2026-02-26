#ifndef ESPNOW_COMM_H
#define ESPNOW_COMM_H

#include <Arduino.h>
#include <esp_now.h>

// ============================================================================
// ESP-NOW MESSAGE TYPES
// ============================================================================
#define MSG_PING        0
#define MSG_START       1
#define MSG_CONFIRM     2
#define MSG_PONG        3
#define MSG_SYNC_REQ    4
#define MSG_OFFSET      5
#define MSG_ARM_CMD     6
#define MSG_DISARM_CMD  7
#define MSG_BEACON      8    // Periodic "I'm here" broadcast (replaces MSG_DISCOVER)
#define MSG_BEACON_ACK  9    // Direct reply to a beacon (replaces MSG_DISCOVER_ACK)
#define MSG_SPEED_DATA  10   // Speed trap → finish: mid-track velocity
#define MSG_SPEED_ACK   11   // Finish → speed trap: acknowledge receipt
#define MSG_PAIR_REQ    12   // "I want to pair with you" (role-aware)
#define MSG_PAIR_ACK    13   // "Pairing accepted"
#define MSG_TELEM_HEADER 14  // Telemetry → finish: run metadata before data chunks
#define MSG_TELEM_CHUNK  15  // Telemetry → finish: IMU data chunk (≤250 bytes)
#define MSG_TELEM_END    16  // Telemetry → finish: end marker with checksum
#define MSG_TELEM_ACK    17  // Finish → telemetry: acknowledge receipt
#define MSG_REMOTE_CMD   18  // Finish → peer: remote command (reboot, identify, etc.)
#define MSG_WIFI_CONFIG  19  // Finish → peer: push WiFi credentials

// ============================================================================
// REMOTE COMMAND SUBTYPES
// ============================================================================
#define CMD_REBOOT          1   // Reboot the target device
#define CMD_IDENTIFY        2   // Flash LED rapidly for 10s (find the device)
#define CMD_DIAG_REPORT     3   // Request detailed diagnostics response
#define CMD_WIFI_RECONNECT  4   // Disconnect + reconnect WiFi

// Race states shared by all roles
enum RaceState { IDLE, ARMED, RACING, FINISHED };

// ============================================================================
// ESP-NOW MESSAGE STRUCTURE
// ============================================================================
typedef struct {
  uint8_t type;
  uint8_t senderId;
  uint64_t timestamp;
  int64_t offset;
  char role[16];         // "start", "finish", "speedtrap"
  char hostname[32];     // mDNS hostname for display
} ESPMessage;

// ============================================================================
// TELEMETRY DATA STRUCTURES (XIAO ride-along IMU logger)
// ============================================================================

// Single IMU sample — 16 bytes
struct __attribute__((packed)) IMUSample {
  uint32_t timestamp_us;    // Microseconds offset from run start
  int16_t  ax, ay, az;      // Raw accelerometer (LSB, ±16g: raw * 0.000488 = g)
  int16_t  gx, gy, gz;      // Raw gyroscope (LSB, ±2000dps: raw * 0.070 = dps)
};

#define TELEM_SAMPLES_PER_CHUNK  14   // 14 × 16 = 224 bytes data per ESP-NOW chunk
#define TELEM_ACCEL_LSB_TO_G     0.000488f
#define TELEM_GYRO_LSB_TO_DPS    0.070f

// Telemetry header — sent before data chunks
struct __attribute__((packed)) TelemetryHeader {
  uint8_t  type;             // MSG_TELEM_HEADER
  uint8_t  senderId;
  uint16_t sampleCount;
  uint16_t sampleRate;       // Hz
  uint8_t  accelRange;       // g (2, 4, 8, 16)
  uint8_t  gyroRange_div100; // dps / 100 (2000 → 20)
  uint32_t runId;
  uint32_t duration_ms;
  uint64_t startTimestamp;   // Absolute micros() at run start
};

// Telemetry data chunk — ≤250 bytes for ESP-NOW
struct __attribute__((packed)) TelemetryChunk {
  uint8_t  type;             // MSG_TELEM_CHUNK
  uint8_t  chunkIndex;
  uint8_t  totalChunks;
  uint8_t  samplesInChunk;   // 1-14
  uint32_t runId;
  IMUSample samples[TELEM_SAMPLES_PER_CHUNK];
};  // 8 + 224 = 232 bytes

// Telemetry end marker
struct __attribute__((packed)) TelemetryEnd {
  uint8_t  type;             // MSG_TELEM_END
  uint8_t  senderId;
  uint32_t runId;
  uint16_t checksum;         // CRC16 of all sample data
  uint16_t sampleCount;
};

// ============================================================================
// FLEET MANAGEMENT STRUCTURES
// ============================================================================

// WiFi credential sharing — finish gate pushes creds to peers
struct __attribute__((packed)) WiFiConfigMsg {
  uint8_t type;           // MSG_WIFI_CONFIG (19)
  uint8_t senderId;
  char ssid[33];          // WiFi SSID (null-terminated)
  char pass[65];          // WiFi password (null-terminated)
  char senderRole[16];    // Role of sender (for verification)
};  // 116 bytes (under 250 ESP-NOW limit)

// Remote command — finish gate sends commands to peers
struct __attribute__((packed)) RemoteCmdMsg {
  uint8_t type;           // MSG_REMOTE_CMD (18)
  uint8_t senderId;
  uint8_t command;        // CMD_* subtype
  uint8_t reserved;       // Alignment / future use
  uint32_t param;         // Command-specific parameter
  char senderRole[16];    // Role of sender (for verification)
};  // 24 bytes

// ============================================================================
// BEACON DIAGNOSTICS — Packed into beacon offset field (int64_t, 8 bytes)
//
// Every beacon carries live diagnostics at zero extra cost. Format:
//   Bits 63-48: uptimeMinutes   (16 bits = 0-65535 min ≈ 45 days)
//   Bits 47-32: freeHeapKB      (16 bits)
//   Bits 31-24: rssiEncoded     (8 bits = WiFi RSSI + 128)
//   Bits 23-16: raceState       (8 bits = IDLE/ARMED/RACING/FINISHED)
//   Bits 15-8:  fwMajor         (8 bits)
//   Bits  7-0:  fwMinor         (8 bits)
// ============================================================================

// Decoded diagnostics from a peer's beacon
struct PeerDiagnostics {
  uint16_t uptimeMin;     // Minutes since boot
  uint16_t freeHeapKB;    // Free heap in KB
  int8_t   rssi;          // WiFi RSSI (dBm)
  uint8_t  raceState;     // RaceState enum value
  uint8_t  fwMajor;       // Firmware major version
  uint8_t  fwMinor;       // Firmware minor version
  bool     valid;         // True if we've received at least one beacon with diag data
};

// ============================================================================
// PEER REGISTRY — The "Brother's Six" System
//
// Every M.A.S.S. Trap device continuously broadcasts beacons on ESP-NOW.
// When a compatible peer is heard, it's automatically added to the registry
// and paired for direct communication — no manual MAC entry needed.
//
// Pairing rules (role-aware):
//   start     ↔ finish     (bidirectional — timing link)
//   speedtrap → finish     (unidirectional — speed data to dashboard)
//   telemetry → finish     (unidirectional — IMU data to dashboard)
//   start     ↔ speedtrap  (not paired — no direct communication needed)
//
// Peers are persisted to /peers.json on LittleFS so they survive reboots.
// ============================================================================

// Peer status
enum PeerStatus {
  PEER_ONLINE,       // Heard within last 15 seconds
  PEER_STALE,        // Heard within last 60 seconds
  PEER_OFFLINE       // Not heard for >60 seconds (but still in registry)
};

// A known peer device
struct KnownPeer {
  uint8_t mac[6];
  char role[16];
  char hostname[32];
  uint8_t deviceId;
  unsigned long lastSeen;      // millis() of last beacon/message
  bool espnowRegistered;       // true if esp_now_add_peer() was called
  bool paired;                 // true if mutual pairing confirmed
  PeerDiagnostics diag;        // Live diagnostics from beacon offset field
};

#define MAX_PEERS 8

// ============================================================================
// GLOBAL STATE
// ============================================================================
extern volatile RaceState raceState;
extern bool dryRunMode;              // Dry-run: race works but no data is logged/saved
extern int64_t clockOffset_us;
extern bool peerConnected;           // Legacy: true if PRIMARY peer is online
extern unsigned long lastPeerSeen;   // Legacy: millis() of last primary peer msg

// Peer registry
extern KnownPeer peers[];
extern int peerCount;

// ============================================================================
// MICROSECOND TIMER
// ============================================================================
uint64_t nowUs();  // Definition in .cpp is IRAM_ATTR (ISR-safe)

// ============================================================================
// INITIALIZATION
// ============================================================================
// Initialize ESP-NOW, register callbacks, load persisted peers, start beaconing
void initESPNow();

// ============================================================================
// MESSAGING
// ============================================================================
// Send to a specific MAC address
void sendToMac(const uint8_t* mac, uint8_t type, uint64_t timestamp, int64_t offset);

// Send to the primary peer (legacy — sends to first paired complementary role)
void sendToPeer(uint8_t type, uint64_t timestamp, int64_t offset);

// ============================================================================
// PEER MANAGEMENT
// ============================================================================
// Find a peer by MAC address. Returns index or -1.
int findPeerByMac(const uint8_t* mac);

// Find the first paired peer with a given role. Returns index or -1.
int findPeerByRole(const char* role);

// Get peer status based on lastSeen
PeerStatus getPeerStatus(const KnownPeer& peer);

// Check if we have at least one online paired peer (for legacy peerConnected flag)
bool hasOnlinePeer();

// Forget a specific peer by MAC
void forgetPeer(const uint8_t* mac);

// Forget ALL peers (factory reset peers)
void forgetAllPeers();

// Get peers list as JSON string (for web API)
String getPeersJson();

// ============================================================================
// PEER PERSISTENCE
// ============================================================================
void loadPeers();   // Load /peers.json from LittleFS
void savePeers();   // Save /peers.json to LittleFS

// ============================================================================
// DISCOVERY LOOP — Call from main loop()
// ============================================================================
// Handles beacon broadcasting, peer timeout tracking, and auto-pairing
void discoveryLoop();

// ============================================================================
// ROLE-SPECIFIC ESP-NOW HANDLERS
// Implemented in start_gate.cpp, finish_gate.cpp, speed_trap.cpp
// ============================================================================
extern void onFinishGateESPNow(const ESPMessage& msg, uint64_t receiveTime);
extern void onStartGateESPNow(const ESPMessage& msg, uint64_t receiveTime);
extern void onSpeedTrapESPNow(const ESPMessage& msg, uint64_t receiveTime);

// Telemetry handlers (called from onDataRecv for variable-size telemetry messages)
extern void onTelemetryHeader(const uint8_t* srcMac, const TelemetryHeader& hdr);
extern void onTelemetryChunk(const uint8_t* srcMac, const TelemetryChunk& chunk);
extern void onTelemetryEnd(const uint8_t* srcMac, const TelemetryEnd& end);

// ============================================================================
// FLEET MANAGEMENT — WiFi sharing, remote commands, beacon diagnostics
// ============================================================================

// Pack live diagnostics into a 64-bit value for beacon offset field
int64_t packBeaconDiag();

// Unpack diagnostics from a received beacon offset field
void unpackBeaconDiag(int64_t packed, PeerDiagnostics& out);

// Send WiFi credentials to a specific peer (by MAC)
void sendWiFiConfig(const uint8_t* mac);

// Send WiFi credentials to ALL paired peers
void sendWiFiConfigAll();

// Send a remote command to a specific peer
void sendRemoteCmd(const uint8_t* mac, uint8_t cmd, uint32_t param = 0);

// Identify flag — set by CMD_IDENTIFY handler, checked in main loop() for LED blink
extern volatile bool identifyActive;
extern unsigned long identifyStartMs;

// WiFi reconnect flag — set by CMD_WIFI_RECONNECT handler, consumed in main loop()
// WiFi APIs aren't thread-safe; ESP-NOW callback runs on Core 0, WiFi must be called on Core 1
extern volatile bool wifiReconnectRequested;

#endif
