#ifndef START_GATE_H
#define START_GATE_H

#include <Arduino.h>
#include "espnow_comm.h"

void startGateSetup();
void startGateLoop();
void onStartGateESPNow(const ESPMessage& msg, uint64_t receiveTime);

// Proximity arm sensor state (HW-870 / TCRT5000)
bool isProxArmEnabled();    // True if sensor_pin_2 is configured
bool isProxCarPresent();    // True if car currently detected (debounced)

#endif
