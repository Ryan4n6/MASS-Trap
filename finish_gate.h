#ifndef FINISH_GATE_H
#define FINISH_GATE_H

#include <Arduino.h>
#include "espnow_comm.h"

// Mutex protecting 64-bit timing variables (ISR ↔ main loop ↔ ESP-NOW task)
extern portMUX_TYPE finishTimerMux;

// Timing variables (volatile for ISR access)
extern volatile uint64_t startTime_us;
extern volatile uint64_t finishTime_us;

// Race info
extern String currentCar;
extern float currentWeight;
extern uint32_t totalRuns;

// Speed trap data (received from speed trap node via ESP-NOW)
extern double midTrackSpeed_mps;  // 0 if no speed trap data available

void finishGateSetup();
void finishGateLoop();
void onFinishGateESPNow(const ESPMessage& msg, uint64_t receiveTime);

// Telemetry receive handlers (called from espnow_comm.cpp for variable-size messages)
void onTelemetryHeader(const uint8_t* srcMac, const TelemetryHeader& hdr);
void onTelemetryChunk(const uint8_t* srcMac, const TelemetryChunk& chunk);
void onTelemetryEnd(const uint8_t* srcMac, const TelemetryEnd& end);

// Telemetry state query (for web API)
bool hasTelemetryData();
String getTelemetryInfoJson();

#endif
