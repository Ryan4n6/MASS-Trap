#include "finish_gate.h"
#include "config.h"
#include "wled_integration.h"
#include <LittleFS.h>

// Forward declaration from web_server
extern void broadcastState();

volatile uint64_t startTime_us = 0;
volatile uint64_t finishTime_us = 0;

String currentCar = "Unknown";
float currentWeight = 35.0;
uint32_t totalRuns = 0;

static unsigned long lastPingTime = 0;

// ============================================================================
// FINISH LINE INTERRUPT
// ============================================================================
void IRAM_ATTR finishISR() {
  if (raceState == RACING && finishTime_us == 0) {
    finishTime_us = nowUs();
    raceState = FINISHED;
  }
}

// ============================================================================
// SETUP
// ============================================================================
void finishGateSetup() {
  pinMode(cfg.sensor_pin, INPUT_PULLUP);
  pinMode(cfg.led_pin, OUTPUT);
  attachInterrupt(digitalPinToInterrupt(cfg.sensor_pin), finishISR, FALLING);
  Serial.printf("[FINISH] Setup complete. Sensor=GPIO%d, LED=GPIO%d\n",
                cfg.sensor_pin, cfg.led_pin);
}

// ============================================================================
// MAIN LOOP
// ============================================================================
void finishGateLoop() {
  // Heartbeat LED blink
  static unsigned long lastBlink = 0;
  if (millis() - lastBlink > 1000) {
    digitalWrite(cfg.led_pin, !digitalRead(cfg.led_pin));
    lastBlink = millis();
  }

  // Ping peer (start gate) every 2 seconds
  if (millis() - lastPingTime > 2000) {
    sendToPeer(MSG_PING, nowUs(), 0);
    lastPingTime = millis();
  }

  // Check peer connectivity timeout (10 seconds)
  if (peerConnected && millis() - lastPeerSeen > 10000) {
    peerConnected = false;
  }

  // Handle race finish
  if (raceState == FINISHED && finishTime_us > 0) {
    delay(100); // Small delay for stability

    // Save to LittleFS CSV
    File file = LittleFS.open("/runs.csv", "a");
    if (file) {
      if (file.size() == 0) file.println("Run,Car,Time,Speed");
      uint64_t elapsed_us = finishTime_us - startTime_us;
      double elapsed_s = elapsed_us / 1000000.0;
      double speed_ms = cfg.track_length_m / elapsed_s;
      file.printf("%u,%s,%.4f,%.2f\n", ++totalRuns, currentCar.c_str(),
                  elapsed_s, speed_ms * 2.23694);
      file.close();
    }

    // Send CONFIRM to start gate
    sendToPeer(MSG_CONFIRM, nowUs(), 0);

    // Trigger WLED finished effect
    setWLEDState("finished");

    // Broadcast to WebSocket clients
    broadcastState();

    // Wait then auto-reset
    delay(5000);
    raceState = IDLE;
    startTime_us = 0;
    finishTime_us = 0;
    setWLEDState("idle");
    broadcastState();
  }
}

// ============================================================================
// ESP-NOW MESSAGE HANDLER
// ============================================================================
void onFinishGateESPNow(const ESPMessage& msg, uint64_t receiveTime) {
  switch (msg.type) {
    case MSG_PING:
      // Reply with PONG
      sendToPeer(MSG_PONG, nowUs(), 0);
      break;

    case MSG_START:
      // Start gate triggered - race begins!
      if (raceState == ARMED) {
        startTime_us = msg.timestamp + clockOffset_us;
        raceState = RACING;
        setWLEDState("racing");
        Serial.println("[FINISH] RACE STARTED!");
        broadcastState();
      }
      break;

    case MSG_SYNC_REQ:
      // Respond with our timestamp for clock sync
      sendToPeer(MSG_OFFSET, nowUs(), 0);
      break;

    case MSG_OFFSET:
      // Clock sync response from peer
      clockOffset_us = msg.timestamp - receiveTime;
      Serial.printf("[FINISH] Clock offset: %lld us\n", clockOffset_us);
      break;
  }
}
