#ifndef WEB_SERVER_H
#define WEB_SERVER_H

#include <Arduino.h>
#include <WebServer.h>
#include <WebSocketsServer.h>

extern WebServer server;
extern WebSocketsServer webSocket;

// Initialize web server routes and WebSocket
void initWebServer();

// Start the servers (call after WiFi is connected)
void startWebServer();

// Broadcast current race state to all WebSocket clients
void broadcastState();

// Setup mode: minimal server with config endpoints only
void initSetupServer();

#endif
