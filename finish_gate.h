#ifndef FINISH_GATE_H
#define FINISH_GATE_H

#include <Arduino.h>
#include "espnow_comm.h"

// Timing variables (volatile for ISR access)
extern volatile uint64_t startTime_us;
extern volatile uint64_t finishTime_us;

// Race info
extern String currentCar;
extern float currentWeight;
extern uint32_t totalRuns;

void finishGateSetup();
void finishGateLoop();
void onFinishGateESPNow(const ESPMessage& msg, uint64_t receiveTime);

#endif
