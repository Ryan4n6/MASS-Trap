# Contributing to M.A.S.S. Trap

Thanks for your interest in contributing! This is a family-built project, and we welcome help from the community.

## Getting Started

### Prerequisites

- [PlatformIO](https://platformio.org/) (CLI or VS Code extension)
- ESP32-S3-WROOM-1 N16R8 (16MB Flash / 8MB PSRAM)
- Basic soldering skills for sensor wiring

### Building

```bash
cd v2.5.0
pio run              # Build firmware
pio run -t upload    # Flash via USB
pio run -t uploadfs  # Upload LittleFS data (audio, HTML)
pio run -t monitor   # Serial monitor (115200 baud)
```

### Project Structure

This is a flat PlatformIO project (`src_dir = .`). All source files live directly in `v2.5.0/`. Web UI files are in `data/`, documentation pages in `docs/`.

## How to Contribute

### Reporting Bugs

- Use the **Bug Report** issue template
- Include your firmware version (`GET /api/version`)
- Include serial monitor output if possible
- Describe what you expected vs. what happened

### Suggesting Features

- Use the **Feature Request** issue template
- Explain the use case, not just the solution
- Keep in mind this project is designed for kids and science fairs

### Code Contributions

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Test on actual hardware (there is no simulator)
5. Submit a Pull Request

### Code Style

- **C++**: Follow existing patterns in the codebase
- **JavaScript**: ES5 only (`var`, not `let`/`const`) for embedded browser compatibility
- **Serial output**: Always use `LOG.printf()` / `LOG.println()`, never raw `Serial`
- **Constants**: Define in `config.h`, no magic numbers
- **ISR safety**: Timing variables must be `volatile` and protected with `portMUX_TYPE` spinlocks

### What We're Looking For

- Bug fixes with clear reproduction steps
- Documentation improvements
- New sensor integrations
- Web UI enhancements (keep it kid-friendly)
- Translation support

### What Probably Won't Be Merged

- Changes that break the flat directory structure
- Dependencies beyond the two we use (WebSockets + ArduinoJson)
- Features that require `delay()` in the main loop
- Changes that don't work on ESP32-S3

## Testing

There is no automated test suite. This is embedded firmware tested on real hardware. Please describe your test setup and results in your PR.

## Questions?

Open a Discussion on GitHub or file an issue. We're friendly.
