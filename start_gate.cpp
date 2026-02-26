#include "start_gate.h"
#include "config.h"
#include "audio_manager.h"
#include "lidar_sensor.h"
// NOTE: Start gate does NOT include wled_integration.h
// Only the finish gate controls WLED to avoid HTTP conflicts.

// Trigger detection
static portMUX_TYPE startMux = portMUX_INITIALIZER_UNLOCKED;
static volatile bool triggerDetected = false;
static volatile uint64_t triggerTime_us = 0;

// Timing
static unsigned long lastPingTime = 0;
static unsigned long triggeredTime = 0;
static unsigned long finishedAt = 0;
static bool waitingToReset = false;

// Proximity arm sensor (HW-870 / TCRT5000 on sensor_pin_2)
// DO pin goes LOW when reflective surface detected (car present)
static bool proxArmEnabled = false;       // Set true if sensor_pin_2 is configured
static bool proxCarPresent = false;       // Debounced: car is currently detected
static unsigned long proxDetectStart = 0; // When car was first detected (for dwell time)
static unsigned long proxClearTime = 0;   // When car was last cleared (for re-arm lockout)
static bool proxArmEligible = true;       // Must see sensor CLEAR before next arm

// ============================================================================
// START TRIGGER INTERRUPT
// ============================================================================
void IRAM_ATTR startTriggerISR() {
  portENTER_CRITICAL_ISR(&startMux);
  if (!triggerDetected) {
    triggerTime_us = esp_timer_get_time();
    triggerDetected = true;
  }
  portEXIT_CRITICAL_ISR(&startMux);
}

// ============================================================================
// SETUP
// ============================================================================
void startGateSetup() {
  pinMode(cfg.sensor_pin, INPUT_PULLUP);
  pinMode(cfg.led_pin, OUTPUT);
  // Don't attach interrupt yet - only when ARMED

  // Proximity arm sensor (HW-870 / TCRT5000) on sensor_pin_2
  // DO output has onboard pull-up via LM393, so INPUT is fine (no pullup needed).
  // LOW = car detected (reflective surface), HIGH = clear.
  if (cfg.sensor_pin_2 > 0 && cfg.sensor_pin_2 != cfg.sensor_pin) {
    pinMode(cfg.sensor_pin_2, INPUT);
    proxArmEnabled = true;
    LOG.printf("[START] Proximity arm sensor enabled on GPIO%d\n", cfg.sensor_pin_2);
  }

  LOG.printf("[START] Setup complete. Trigger=GPIO%d, LED=GPIO%d, ProxArm=%s\n",
                cfg.sensor_pin, cfg.led_pin, proxArmEnabled ? "ON" : "OFF");
}

// ============================================================================
// LED breathing effect for idle state
// ============================================================================
static void breatheLED() {
  // Simple on/off breathing using millis
  int brightness = (millis() / 10) % 512;
  if (brightness > 255) brightness = 511 - brightness;
  analogWrite(cfg.led_pin, brightness);
}

// ============================================================================
// MAIN LOOP
// ============================================================================
void startGateLoop() {
  // Check peer connectivity timeout
  if (peerConnected && millis() - lastPeerSeen > PING_BACKOFF_MS) {
    peerConnected = false;
    LOG.println("[START] Peer disconnected - reducing ping rate");
  }

  // Ping finish gate - back off to 10s when disconnected
  unsigned long pingInterval = peerConnected ? PING_INTERVAL_MS : PING_BACKOFF_MS;
  if (millis() - lastPingTime > pingInterval) {
    sendToPeer(MSG_PING, nowUs(), 0);
    lastPingTime = millis();
  }

  // NOTE: The FINISH gate owns clock sync (it initiates SYNC_REQ every 10s).
  // The start gate just responds to SYNC_REQ with MSG_OFFSET.

  // Non-blocking reset after FINISHED state
  if (waitingToReset && millis() - finishedAt > START_RESET_DELAY_MS) {
    waitingToReset = false;
    raceState = IDLE;
    // Reset prox sensor — require car to CLEAR then re-detect before next arm.
    // This means Ben must pull the old car out and put a new one in.
    proxCarPresent = false;
    proxDetectStart = 0;
    proxClearTime = 0;
    proxArmEligible = false; // Must see car REMOVED before next arm
    LOG.println("[START] Auto-reset to IDLE");
  }

  switch (raceState) {
    case IDLE:
      breatheLED();

      // --- Proximity arm sensor (HW-870) polling ---
      // DO goes LOW when car is detected. Arm after PROX_ARM_DWELL_MS dwell.
      // Re-arm requires the sensor to CLEAR first (car removed), then detect
      // a new car. This prevents the same car from re-arming without human action.
      if (proxArmEnabled) {
        bool carNow = (digitalRead(cfg.sensor_pin_2) == LOW);

        if (carNow && !proxCarPresent) {
          // Rising edge: car just appeared (or reappeared after clearing)
          proxCarPresent = true;
          // Only start dwell timer if eligible (sensor cleared since last arm)
          if (proxArmEligible) {
            proxDetectStart = millis();
          }
        } else if (!carNow && proxCarPresent) {
          // Falling edge: car removed — this is the "human action" that
          // makes the next detection eligible for arming
          proxCarPresent = false;
          proxClearTime = millis();
          proxDetectStart = 0;
          proxArmEligible = true;  // Car was physically removed → next detect can arm
        } else if (!carNow && !proxCarPresent) {
          // Sensor clear, no car — keep eligibility flag current
          // (handles case where car was never detected after reset)
          if (!proxArmEligible && proxClearTime == 0) {
            proxArmEligible = true;  // Sensor is clear after reset → eligible
            proxClearTime = millis();
          }
        }

        // Arm when: car present for PROX_ARM_DWELL_MS AND eligible
        // (sensor must have cleared since last arm, or first boot)
        if (proxArmEligible && proxCarPresent && proxDetectStart > 0 &&
            (millis() - proxDetectStart >= PROX_ARM_DWELL_MS)) {
          raceState = ARMED;
          triggerDetected = false;
          portENTER_CRITICAL(&startMux);
          triggerTime_us = 0;
          portEXIT_CRITICAL(&startMux);
          attachInterrupt(digitalPinToInterrupt(cfg.sensor_pin), startTriggerISR, FALLING);
          sendToPeer(MSG_ARM_CMD, nowUs(), 0);
          playSound("armed.wav");
          LOG.println("[START] AUTO-ARMED via proximity sensor (HW-870)");
          // Reset: require sensor to clear before next arm
          proxDetectStart = 0;
          proxClearTime = 0;
          proxArmEligible = false; // Must see car REMOVED before next arm
          break;
        }
      }

      // LiDAR auto-arm: if car has been staged for >1 second, auto-arm
      if (lidarAutoArmReady()) {
        raceState = ARMED;
        triggerDetected = false;
        portENTER_CRITICAL(&startMux);
        triggerTime_us = 0;
        portEXIT_CRITICAL(&startMux);
        attachInterrupt(digitalPinToInterrupt(cfg.sensor_pin), startTriggerISR, FALLING);
        sendToPeer(MSG_ARM_CMD, nowUs(), 0);
        playSound("armed.wav");
        LOG.println("[START] AUTO-ARMED via LiDAR sensor");
      }
      break;

    case ARMED:
      // Solid LED when armed
      digitalWrite(cfg.led_pin, HIGH);

      if (triggerDetected) {
        // Beam broken - race starts!
        raceState = RACING;
        triggerDetected = false;
        triggeredTime = millis();

        // Atomic read of 64-bit trigger timestamp
        uint64_t safeTrigger;
        portENTER_CRITICAL(&startMux);
        safeTrigger = triggerTime_us;
        portEXIT_CRITICAL(&startMux);

        // Send START with our LOCAL precise timestamp to finish gate.
        // The finish gate will convert this to its timebase using clockOffset.
        LOG.printf("[START] TRIGGERED at %llu us\n", safeTrigger);
        sendToPeer(MSG_START, safeTrigger, 0);

        // Play "go" sound on start gate speaker
        playSound("go.wav");

        // Detach interrupt to prevent re-trigger
        detachInterrupt(digitalPinToInterrupt(cfg.sensor_pin));

        LOG.println("[START] Race started.");
      }
      break;

    case RACING:
      // Flash LED rapidly while racing
      digitalWrite(cfg.led_pin, (millis() / 100) % 2);

      // Timeout: if no CONFIRM after 30 seconds, reset
      if (millis() - triggeredTime > RACE_TIMEOUT_MS) {
        LOG.println("[START] Race timeout - no finish confirmation");
        raceState = IDLE;
        // Reset prox sensor — require clear→detect cycle
        proxCarPresent = false;
        proxDetectStart = 0;
        proxClearTime = 0;
        proxArmEligible = false;
      }
      break;

    case FINISHED:
      // Solid LED briefly then non-blocking reset
      if (!waitingToReset) {
        digitalWrite(cfg.led_pin, HIGH);
        waitingToReset = true;
        finishedAt = millis();
      }
      break;
  }
}

// ============================================================================
// ESP-NOW MESSAGE HANDLER
// ============================================================================
void onStartGateESPNow(const ESPMessage& msg, uint64_t receiveTime) {
  switch (msg.type) {
    case MSG_PING:
      // Reply with PONG
      sendToPeer(MSG_PONG, nowUs(), 0);
      break;

    case MSG_CONFIRM:
      // Finish gate confirmed race complete
      raceState = FINISHED;
      LOG.println("[START] Race confirmed complete!");
      break;

    case MSG_SYNC_REQ:
      // Finish gate is requesting clock sync - reply with our current time.
      // The finish gate will use this to compute the offset between our clocks.
      sendToPeer(MSG_OFFSET, nowUs(), 0);
      break;

    case MSG_OFFSET:
      // Finish gate owns the offset - we ignore this.
      break;

    case MSG_ARM_CMD:
      // Finish gate says to arm
      if (raceState == IDLE) {
        raceState = ARMED;
        triggerDetected = false;
        portENTER_CRITICAL(&startMux);
        triggerTime_us = 0;
        portEXIT_CRITICAL(&startMux);
        // Attach interrupt to detect beam break
        attachInterrupt(digitalPinToInterrupt(cfg.sensor_pin), startTriggerISR, FALLING);
        // Play armed chime on start gate speaker
        playSound("armed.wav");
        LOG.println("[START] ARMED - waiting for trigger");
      }
      break;

    case MSG_DISARM_CMD:
      // Finish gate says to reset
      raceState = IDLE;
      triggerDetected = false;
      detachInterrupt(digitalPinToInterrupt(cfg.sensor_pin));
      // Reset prox sensor — require clear→detect cycle before next arm
      proxCarPresent = false;
      proxDetectStart = 0;
      proxClearTime = 0;
      proxArmEligible = false; // Must see car REMOVED before next arm
      LOG.println("[START] DISARMED");
      break;
  }
}

// ============================================================================
// PROXIMITY ARM SENSOR ACCESSORS
// ============================================================================
bool isProxArmEnabled() {
  return proxArmEnabled;
}

bool isProxCarPresent() {
  return proxCarPresent;
}
