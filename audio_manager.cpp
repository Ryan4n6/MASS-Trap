#include "audio_manager.h"
#include "config.h"
#include "dysv5w.h"
#include <LittleFS.h>
#include <driver/i2s.h>

// ============================================================================
// BACKEND SELECTION
// ============================================================================
enum AudioBackend {
  BACKEND_NONE,
  BACKEND_I2S,
  BACKEND_DYSV5W
};

static AudioBackend activeBackend = BACKEND_NONE;

// ============================================================================
// I2S CONFIGURATION for MAX98357A
// ============================================================================
#define I2S_PORT          I2S_NUM_0
#define DMA_BUF_COUNT     8
#define DMA_BUF_LEN       256
#define SAMPLE_RATE       16000   // 16kHz mono — good balance of quality and size

// ============================================================================
// I2S PLAYBACK STATE
// ============================================================================
static File audioFile;
static bool audioPlaying = false;
static bool audioInitialized = false;
static uint32_t audioDataStart = 0;
static uint32_t audioDataSize = 0;
static uint32_t audioBytesRead = 0;
static uint8_t volumeLevel = 10;
static uint8_t audioBuffer[512];

static uint8_t wavBitsPerSample = 16;
static uint16_t wavChannels = 1;
static uint32_t wavSampleRate = 16000;

// ============================================================================
// WAV HEADER PARSER (I2S backend only)
// ============================================================================
static bool parseWavHeader(File& f) {
  uint8_t header[44];
  if (f.read(header, 44) != 44) return false;

  if (header[0] != 'R' || header[1] != 'I' || header[2] != 'F' || header[3] != 'F') return false;
  if (header[8] != 'W' || header[9] != 'A' || header[10] != 'V' || header[11] != 'E') return false;

  wavChannels = header[22] | (header[23] << 8);
  wavSampleRate = header[24] | (header[25] << 8) | (header[26] << 16) | (header[27] << 24);
  wavBitsPerSample = header[34] | (header[35] << 8);

  f.seek(12);
  while (f.available() >= 8) {
    uint8_t chunkHeader[8];
    if (f.read(chunkHeader, 8) != 8) return false;

    uint32_t chunkSize = chunkHeader[4] | (chunkHeader[5] << 8) |
                         (chunkHeader[6] << 16) | (chunkHeader[7] << 24);

    if (chunkHeader[0] == 'd' && chunkHeader[1] == 'a' &&
        chunkHeader[2] == 't' && chunkHeader[3] == 'a') {
      audioDataStart = f.position();
      audioDataSize = chunkSize;
      return true;
    }

    f.seek(f.position() + chunkSize);
  }

  return false;
}

// ============================================================================
// I2S SETUP
// ============================================================================
static void i2sSetup() {
  i2s_config_t i2s_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX),
    .sample_rate = SAMPLE_RATE,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = DMA_BUF_COUNT,
    .dma_buf_len = DMA_BUF_LEN,
    .use_apll = false,
    .tx_desc_auto_clear = true,
    .fixed_mclk = 0
  };

  i2s_pin_config_t pin_config = {
    .bck_io_num = cfg.i2s_bclk_pin,
    .ws_io_num = cfg.i2s_lrc_pin,
    .data_out_num = cfg.i2s_dout_pin,
    .data_in_num = I2S_PIN_NO_CHANGE
  };

  esp_err_t err = i2s_driver_install(I2S_PORT, &i2s_config, 0, NULL);
  if (err != ESP_OK) {
    LOG.printf("[AUDIO] I2S driver install failed: %d\n", err);
    return;
  }

  err = i2s_set_pin(I2S_PORT, &pin_config);
  if (err != ESP_OK) {
    LOG.printf("[AUDIO] I2S pin config failed: %d\n", err);
    i2s_driver_uninstall(I2S_PORT);
    return;
  }

  i2s_zero_dma_buffer(I2S_PORT);
  audioInitialized = true;
  activeBackend = BACKEND_I2S;

  LOG.printf("[AUDIO] I2S initialized: BCLK=%d, LRC=%d, DOUT=%d\n",
                cfg.i2s_bclk_pin, cfg.i2s_lrc_pin, cfg.i2s_dout_pin);
}

// ============================================================================
// I2S LOOP — Feed DMA buffer (non-blocking)
// ============================================================================
static void i2sLoop() {
  if (!audioInitialized || !audioPlaying) return;

  size_t bytesToRead = sizeof(audioBuffer);
  size_t remaining = audioDataSize - audioBytesRead;
  if (bytesToRead > remaining) bytesToRead = remaining;

  if (bytesToRead == 0) {
    stopSound();
    return;
  }

  size_t bytesRead = audioFile.read(audioBuffer, bytesToRead);
  if (bytesRead == 0) {
    stopSound();
    return;
  }

  int16_t sampleBuf[256];
  size_t sampleCount = 0;

  if (wavBitsPerSample == 8) {
    for (size_t i = 0; i < bytesRead; i++) {
      int16_t sample = ((int16_t)audioBuffer[i] - 128) << 8;
      sample = (sample * volumeLevel) / 21;
      sampleBuf[sampleCount++] = sample;
    }
  } else {
    sampleCount = bytesRead / 2;
    for (size_t i = 0; i < sampleCount; i++) {
      int16_t sample = (int16_t)(audioBuffer[i * 2] | (audioBuffer[i * 2 + 1] << 8));
      sample = (sample * volumeLevel) / 21;
      sampleBuf[i] = sample;
    }
  }

  if (wavChannels == 2) {
    size_t monoCount = sampleCount / 2;
    for (size_t i = 0; i < monoCount; i++) {
      sampleBuf[i] = sampleBuf[i * 2];
    }
    sampleCount = monoCount;
  }

  size_t bytesWritten = 0;
  i2s_write(I2S_PORT, sampleBuf, sampleCount * 2, &bytesWritten, 0);

  audioBytesRead += bytesRead;
}

// ============================================================================
// I2S PLAY SOUND
// ============================================================================
static void i2sPlaySound(const char* filename) {
  if (!audioInitialized) return;

  if (audioPlaying) stopSound();

  String path = String("/") + filename;
  if (!LittleFS.exists(path)) {
    LOG.printf("[AUDIO] File not found: %s\n", path.c_str());
    return;
  }

  audioFile = LittleFS.open(path, "r");
  if (!audioFile) {
    LOG.printf("[AUDIO] Failed to open: %s\n", path.c_str());
    return;
  }

  if (!parseWavHeader(audioFile)) {
    LOG.printf("[AUDIO] Invalid WAV: %s\n", path.c_str());
    audioFile.close();
    return;
  }

  if (wavSampleRate != SAMPLE_RATE) {
    i2s_set_sample_rates(I2S_PORT, wavSampleRate);
  }

  audioFile.seek(audioDataStart);
  audioBytesRead = 0;
  audioPlaying = true;

  LOG.printf("[AUDIO] Playing: %s (%dHz, %dbit, %dch, %d bytes)\n",
                filename, wavSampleRate, wavBitsPerSample, wavChannels, audioDataSize);
}

// ============================================================================
// I2S STOP
// ============================================================================
static void i2sStop() {
  if (!audioInitialized) return;

  audioPlaying = false;
  if (audioFile) {
    audioFile.close();
  }
  i2s_zero_dma_buffer(I2S_PORT);

  if (wavSampleRate != SAMPLE_RATE) {
    i2s_set_sample_rates(I2S_PORT, SAMPLE_RATE);
    wavSampleRate = SAMPLE_RATE;
  }
}

// ============================================================================
// PUBLIC API — dispatches to active backend
// ============================================================================
void audioSetup() {
  if (!cfg.audio_enabled) return;

  if (strcmp(cfg.audio_backend, "dysv5w") == 0) {
    dysv5wSetup(cfg.dysv5w_tx_pin, cfg.dysv5w_busy_pin);
    activeBackend = BACKEND_DYSV5W;

    // Scale volume: config stores 0-21 for I2S, map to 0-30 for DY-SV5W
    uint8_t vol = (uint8_t)((cfg.audio_volume * 30) / 21);
    dysv5wSetVolume(vol);

    LOG.println("[AUDIO] Backend: DY-SV5W (UART sound module)");
  } else {
    i2sSetup();
    LOG.println("[AUDIO] Backend: I2S (MAX98357A)");
  }
}

void audioLoop() {
  if (activeBackend == BACKEND_I2S) {
    i2sLoop();
  }
  // DY-SV5W is fire-and-forget, no loop needed
}

void playSound(const char* filename) {
  if (activeBackend == BACKEND_I2S) {
    i2sPlaySound(filename);
  } else if (activeBackend == BACKEND_DYSV5W) {
    uint16_t track = dysv5wLookupTrack(filename);
    if (track > 0) {
      dysv5wPlayTrack(track);
    }
  }
}

void stopSound() {
  if (activeBackend == BACKEND_I2S) {
    i2sStop();
  } else if (activeBackend == BACKEND_DYSV5W) {
    dysv5wStop();
  }
}

bool isPlaying() {
  if (activeBackend == BACKEND_I2S) {
    return audioPlaying;
  } else if (activeBackend == BACKEND_DYSV5W) {
    return dysv5wIsBusy();
  }
  return false;
}

void setVolume(uint8_t level) {
  if (activeBackend == BACKEND_I2S) {
    if (level > 21) level = 21;
    volumeLevel = level;
    LOG.printf("[AUDIO] Volume set to %d/21\n", level);
  } else if (activeBackend == BACKEND_DYSV5W) {
    if (level > 30) level = 30;
    dysv5wSetVolume(level);
  }
}

String getAudioFileList() {
  String json = "[";
  File root = LittleFS.open("/");
  File f = root.openNextFile();
  bool first = true;
  while (f) {
    String name = String(f.name());
    if (name.endsWith(".wav")) {
      if (!first) json += ",";
      json += "{\"name\":\"" + name + "\",\"size\":" + String(f.size()) + "}";
      first = false;
    }
    f = root.openNextFile();
  }
  json += "]";
  return json;
}
