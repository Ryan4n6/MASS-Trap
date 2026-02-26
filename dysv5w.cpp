#include "dysv5w.h"
#include "config.h"

// ============================================================================
// DY-SV5W UART PROTOCOL (dyplayer compatible)
// ============================================================================
// Frame format: [0xAA] [CMD] [LEN] [DATA...] [SM]
//   0xAA  = start marker
//   CMD   = command code
//   LEN   = number of data bytes (0 if no parameters)
//   SM    = checksum = low byte of sum of all frame bytes
//
// Key commands:
//   0x04  Stop
//   0x07  Play track N  (LEN=0x02, 2-byte track number big-endian)
//   0x13  Set volume    (LEN=0x01, 1 byte 0-30)
// ============================================================================

#define DYSV5W_BAUD       9600
#define DYSV5W_HEADER     0xAA
#define DYSV5W_CMD_PLAY       0x07
#define DYSV5W_CMD_STOP       0x04
#define DYSV5W_CMD_VOLUME     0x13
#define DYSV5W_CMD_SET_DEVICE 0x0B
#define DYSV5W_DEVICE_SD      0x01

// Use UART1 (avoids conflict with Serial0 used for LOG/debug)
static HardwareSerial dysv5wSerial(1);
static uint8_t busyGPIO = 0;
static bool dysv5wReady = false;

// ============================================================================
// TRACK MAP — clip filename to DY-SV5W track number
// Must match the numbered files on the TF card (00001.mp3 through 00020.mp3)
// Order matches clips.json definitions
// ============================================================================
struct TrackEntry {
  const char* name;
  uint16_t track;
};

static const TrackEntry TRACK_MAP[] = {
  // Firmware clips (tracks 1-8)
  { "armed",            1 },
  { "go",               2 },
  { "finish",           3 },
  { "record",           4 },
  { "reset",            5 },
  { "sync",             6 },
  { "error",            7 },
  { "speed_trap",       8 },
  // Lab clips (tracks 9-16, 19-20)
  { "attention",        9 },
  { "next_car",        10 },
  { "condition_change", 11 },
  { "trial_complete",  12 },
  { "experiment_done", 13 },
  { "sanity_alert",    14 },
  { "case_assigned",   15 },
  { "calibration",     19 },
  { "photo_prompt",    20 },
  // Extra clips (tracks 16-18)
  { "leaderboard",     16 },
  { "startup",         17 },
  { "peer_found",      18 },
};
static const int TRACK_MAP_SIZE = sizeof(TRACK_MAP) / sizeof(TRACK_MAP[0]);

// ============================================================================
// SEND COMMAND
// ============================================================================
static void sendCommand(uint8_t cmd, const uint8_t* data, uint8_t dataLen) {
  if (!dysv5wReady) return;

  // Frame: [AA] [CMD] [LEN] [DATA...] [SM]
  uint8_t frame[16];
  uint8_t idx = 0;
  frame[idx++] = DYSV5W_HEADER;
  frame[idx++] = cmd;
  frame[idx++] = dataLen;
  for (uint8_t i = 0; i < dataLen && idx < 14; i++) {
    frame[idx++] = data[i];
  }
  // Checksum: sum of all preceding bytes
  uint16_t sum = 0;
  for (uint8_t i = 0; i < idx; i++) sum += frame[i];
  frame[idx++] = (uint8_t)(sum & 0xFF);

  // Debug: log exact hex bytes
  char hex[48];
  int pos = 0;
  for (uint8_t i = 0; i < idx; i++) {
    pos += snprintf(hex + pos, sizeof(hex) - pos, "%02X ", frame[i]);
  }
  LOG.printf("[DY-SV5W] TX: %s\n", hex);

  dysv5wSerial.write(frame, idx);
  dysv5wSerial.flush();
}

// ============================================================================
// PUBLIC API
// ============================================================================
void dysv5wSetup(uint8_t txPin, uint8_t busyPin) {
  busyGPIO = busyPin;

  // TX-only UART: we send commands, module doesn't reply in normal use
  // RX pin = -1 (not connected)
  dysv5wSerial.begin(DYSV5W_BAUD, SERIAL_8N1, -1, txPin);

  // BUSY pin: INPUT_PULLUP since I/O1 is open-drain on DY-SV5W
  pinMode(busyPin, INPUT_PULLUP);

  dysv5wReady = true;

  // Module auto-plays all tracks on power-on — kill it
  delay(500);
  dysv5wStop();
  delay(100);
  dysv5wStop();
  delay(100);

  // Select SD/TF card as playback device
  uint8_t dev = DYSV5W_DEVICE_SD;
  sendCommand(DYSV5W_CMD_SET_DEVICE, &dev, 1);
  delay(100);

  LOG.printf("[DY-SV5W] UART initialized: TX=GPIO%d, BUSY=GPIO%d, 9600 baud\n",
             txPin, busyPin);
}

void dysv5wPlayTrack(uint16_t trackNumber) {
  if (trackNumber == 0) return;
  uint8_t data[2] = {
    (uint8_t)(trackNumber >> 8),   // high byte
    (uint8_t)(trackNumber & 0xFF)  // low byte
  };
  sendCommand(DYSV5W_CMD_PLAY, data, 2);
  LOG.printf("[DY-SV5W] Play track %d\n", trackNumber);
}

void dysv5wStop() {
  sendCommand(DYSV5W_CMD_STOP, NULL, 0);
}

void dysv5wSetVolume(uint8_t level) {
  if (level > 30) level = 30;
  sendCommand(DYSV5W_CMD_VOLUME, &level, 1);
  LOG.printf("[DY-SV5W] Volume set to %d/30\n", level);
}

bool dysv5wIsBusy() {
  if (!dysv5wReady) return false;
  return digitalRead(busyGPIO) == LOW;
}

uint16_t dysv5wLookupTrack(const char* clipName) {
  if (!clipName) return 0;

  // Strip leading "/" and trailing ".wav" or ".mp3" if present
  const char* name = clipName;
  if (name[0] == '/') name++;

  // Compare against track map (with or without extension)
  for (int i = 0; i < TRACK_MAP_SIZE; i++) {
    // Exact match on base name
    if (strcmp(name, TRACK_MAP[i].name) == 0) {
      return TRACK_MAP[i].track;
    }
    // Match with .wav extension
    size_t baseLen = strlen(TRACK_MAP[i].name);
    if (strncmp(name, TRACK_MAP[i].name, baseLen) == 0) {
      const char* ext = name + baseLen;
      if (strcmp(ext, ".wav") == 0 || strcmp(ext, ".mp3") == 0) {
        return TRACK_MAP[i].track;
      }
    }
  }

  LOG.printf("[DY-SV5W] Unknown clip: %s\n", clipName);
  return 0;
}
