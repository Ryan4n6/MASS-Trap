#ifndef WLED_INTEGRATION_H
#define WLED_INTEGRATION_H

#include <Arduino.h>

// Set WLED effect based on race state ("idle", "armed", "racing", "finished")
// No-op if WLED host is not configured
void setWLEDState(const char* raceState);

// Test WLED connection. Returns true if reachable.
bool testWLEDConnection();

#endif
