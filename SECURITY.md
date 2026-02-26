# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 2.6.x   | Yes       |
| 2.5.x   | Yes       |
| < 2.5   | No        |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT open a public issue**
2. Email the maintainer at the address listed on their [GitHub profile](https://github.com/Ryan4n6)
3. Include a description of the vulnerability, steps to reproduce, and potential impact
4. Allow reasonable time for a fix before public disclosure

## Security Considerations

M.A.S.S. Trap is designed for **local network use** (home WiFi). It is not intended to be exposed to the public internet. Keep the following in mind:

- **API authentication**: All API endpoints require an `X-API-Key` header (set via OTA password in config)
- **WiFi credentials**: Stored in LittleFS on the device, never transmitted over ESP-NOW
- **OTA updates**: Protected by password authentication
- **Web UI**: Served over HTTP (not HTTPS) on local network only
- **ESP-NOW**: Unencrypted broadcast protocol used for device-to-device communication on the same WiFi channel

## Scope

Security reports are welcome for:

- Authentication bypass on API endpoints
- Cross-site scripting (XSS) in the web dashboard
- Credential exposure in firmware or web UI
- Unauthorized OTA firmware uploads

Out of scope:

- Physical access attacks (if someone has physical access to the ESP32, security is moot)
- Denial of service on local network
- Issues requiring man-in-the-middle on the local network
