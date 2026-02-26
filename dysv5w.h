#ifndef DYSV5W_H
#define DYSV5W_H

#include <Arduino.h>

// ============================================================================
// DY-SV5W UART Sound Module Driver
// ============================================================================
// Protocol: 9600 baud, 8N1
// Frame: [0xAA] [LEN] [CMD] [DATA...] [CHECKSUM]
//   LEN = bytes from CMD to CHECKSUM inclusive
//   CHECKSUM = low byte of sum of all frame bytes
//
// Plays MP3/WAV files from TF card by track number (00001.mp3 = track 1).
// BUSY pin (I/O1): LOW while playing, HIGH when idle.
// ============================================================================

// Initialize UART and BUSY pin. Call once from audioSetup().
void dysv5wSetup(uint8_t txPin, uint8_t busyPin);

// Play a track by number (1-65535, maps to 00001.mp3-65535.mp3 on TF card).
void dysv5wPlayTrack(uint16_t trackNumber);

// Stop playback immediately.
void dysv5wStop();

// Set volume (0-30). Default after power-on is 20.
void dysv5wSetVolume(uint8_t level);

// Returns true if module is currently playing (BUSY pin LOW).
bool dysv5wIsBusy();

// Map a clip filename (e.g. "speed_trap", "armed") to its track number.
// Returns 0 if the clip name is not found in the track map.
uint16_t dysv5wLookupTrack(const char* clipName);

#endif
