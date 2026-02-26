#ifndef AUDIO_MANAGER_H
#define AUDIO_MANAGER_H

#include <Arduino.h>

// ============================================================================
// Audio Manager — Unified API for I2S (MAX98357A) and UART (DY-SV5W) backends
// ============================================================================
// Backend is selected by cfg.audio_backend: "i2s" or "dysv5w"
// All callers use the same API regardless of backend.

// Initialize the audio backend. No-op if audio not enabled in config.
// Call once from setup().
void audioSetup();

// Feed DMA buffer (I2S backend only). Non-blocking — call every loop().
// No-op for DY-SV5W backend (UART is fire-and-forget).
void audioLoop();

// Play a sound clip by filename (e.g. "armed.wav", "speed_trap.wav").
// I2S: opens WAV from LittleFS. DY-SV5W: maps name to track number.
void playSound(const char* filename);

// Stop any currently playing sound immediately.
void stopSound();

// Returns true if a sound is currently playing.
bool isPlaying();

// Set volume level. I2S: 0-21. DY-SV5W: 0-30.
void setVolume(uint8_t level);

// Get list of WAV files in LittleFS as JSON array string
String getAudioFileList();

#endif
