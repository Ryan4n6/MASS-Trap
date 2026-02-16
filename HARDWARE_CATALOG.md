# M.A.S.S. Trap — Hardware Catalog

*Compiled from Amazon order history, February 14, 2026. Project-relevant components only.*
*Excludes: Pwnagotchi ("Ryanagotchi"), 3D printer upgrades, general Raspberry Pi, Meshtastic-specific.*

---

## Sensors

| Component | Qty | Interface | Order Date | Notes |
|-----------|-----|-----------|------------|-------|
| **WT901 IMU** (9-axis accel/gyro/mag, Kalman, 200Hz) | 1 | UART/USB | Feb 14, 2026 | High-accuracy, MPU9250-based |
| **GY-291 ADXL345** (3-axis accelerometer) | 4 | I2C/SPI | Feb 14, 2026 | Welded headers, gravity/tilt |
| **Adafruit BNO055** (9-DOF absolute orientation IMU) | 1 | I2C | Feb 14, 2026 | Fusion breakout, absolute heading |
| **Teyleten GY-906 MLX90614** (IR temp sensor) | 1 | I2C | Feb 14, 2026 | Non-contact, general FOV |
| **EC Buying MLX90614ESF-DCI** (IR temp, long distance) | 1 | I2C | Feb 14, 2026 | Narrow FOV (5°), 50cm cable, "track temp gun" |
| **HiLetgo BMP280** (barometric pressure/temp) | 5 | I2C/SPI | Feb 14, 2026 | Air density calculation |
| **IR Break Beam Sensors** (photoelectric, 3 pairs) | 3pr | Digital | Feb 13, 2026 | Race trigger / finish line |
| **IR Break Beam Sensors** (5mm LED, 25cm cable, 4 pcs) | 4 | Digital NPN | Jan 27, 2026 | 30cm range, spares |
| **TCRT5000 IR Reflective Sensors** | 10 | Analog | Jan 27, 2026 | Line/obstacle detection |
| **Wishiot TF-Luna LiDAR** (0.2-8m range finder) | 2 | UART/I2C | Feb 4 + Jan 27, 2026 | Auto-arm trigger, distance sensing |
| **BOJACK Photoresistors LDR GM5539** | 50 | Analog | Apr 15, 2025 | Ambient light sensing |

## NFC / RFID

| Component | Qty | Interface | Order Date | Notes |
|-----------|-----|-----------|------------|-------|
| **HiLetgo PN532 NFC/RFID Module V3** | 1 | I2C/SPI/HSU(UART) | Feb 10, 2026 | Includes S50 white cards |
| **NTAG213 NFC Sticker Tags** (transparent, 144 bytes) | 20 | — | Feb 2026 | For car tagging (from previous session catalog) |

## Microcontrollers / Dev Boards

| Component | Qty | Notes | Order Date |
|-----------|-----|-------|------------|
| **Seeed Studio XIAO ESP32-S3 Sense** | 1 | WiFi/BLE, camera, mic, 8MB PSRAM/Flash | Feb 14, 2026 |
| **Seeed Studio XIAO ESP32C3** | 1 | WiFi/BLE, tiny, battery charge | Apr 9, 2025 |
| **Freenove ESP32-S3 CAM Board** | 1 | Dual-core 240MHz, onboard camera | Feb 8, 2026 |
| **Meshnology ESP32 Breakout (N40)** | 4+ | ESP32/S3 WROVER/WROOM, 5V/3.3V, GPIO, LED | Feb 13, 2026 |
| **ESP32 Expansion Boards (38-pin)** | 3 | NodeMCU-32S/WROOM-32D/32U/WROVER | Feb 13, 2026 |
| **hiBCTR RP2040-Zero** | 6 | Pico, dual-core Cortex M0+, 2MB flash | Jan 20, 2026 |
| **DWEII RP2040-Zero** | 3 | USB-C, Pico, MicroPython | Jan 16, 2026 |

## Displays

| Component | Qty | Specs | Order Date | Notes |
|-----------|-----|-------|------------|-------|
| **ESP32-P4-WIFI6 7" Touch Display** | 1 | 1024×600, ESP32-P4+C6, RS485/CAN/I2C/UART | Feb 10, 2026 | AI speech interaction |
| **ESP32-S3 7" Touch LCD** | 1 | 1024×600, IPS, LX7, WiFi/BLE 5 | Feb 10, 2026 | Backlight adjustable |
| **Waveshare ESP32-S3 2.8" Display** | 1 | 480×640, IPS, no touch | Feb 8, 2026 | Compact status display |
| **HiLetgo TM1638 Segment Display** | 1 | 8-digit LED tube + 8 LEDs + 8 buttons | Feb 6, 2026 | Scanner segment display for Daytona theme! |

## Audio

| Component | Qty | Specs | Order Date | Notes |
|-----------|-----|-------|------------|-------|
| **Diann MP3 Voice Playback Module** (DY-SV5W) | 4 | UART trigger, 5W amp, 32G card | Feb 13, 2026 | Sound effects / announcements |
| **DWEII 3W Mini Speakers** | 4+4 | 4Ω, JST-PH 2.0mm, 11mm | Feb 8, 2026 | 2 orders |
| **PAM8403 Bluetooth Audio Amp** | 1 | 5V, 5W+5W, 18650, 20m BT range | Feb 8, 2026 | Wireless audio bridge |

## WLED / LED Controllers

| Component | Qty | Specs | Order Date | Notes |
|-----------|-----|-------|------------|-------|
| **BTF-LIGHTING ESP32 WLED SP803E** | 3+ | WS2811/2812/SK6812, USB-C, mic | Feb 8, 2026 | Multiple orders |
| **BTF-LIGHTING WS2811/2812B RF Controller** | 1 | 14-key wireless, DC5/12V, 300 effects | Feb 8, 2026 | Non-ESP standalone controller |
| **Adeept Mini Traffic Light LEDs** | 10 | 5V, 5mm, R/Y/G | Feb 9, 2026 | Drag tree / start gate visual |

## Radio / Wireless

| Component | Qty | Interface | Order Date | Notes |
|-----------|-----|-----------|------------|-------|
| **NRF24L01+PA+LNA** (UMLIFE, w/ breakout+3.3V reg) | 5+5 | SPI | Jan 20, 2026 | 2.4GHz, 1100m range |
| **NRF24L01+PA+LNA** (EC Buying) | 2 | SPI | Jan 20, 2026 | 20dBm, 2000m range |
| **NRF24L01+PA+LNA** (HiLetgo) | 2 | SPI | Jan 16, 2026 | 2.4G, 1100m |
| **433MHz SMA Antennas** (Kaunosta) | 2 | SMA | Jan 20, 2026 | LoRa/HAM |
| **IPX to SMA Pigtail Antennas** (HiLetgo) | 5 | U.FL→SMA | Mar 27, 2025 | WiFi antenna adapters |
| **IPEX U.FL Coaxial Connectors** (E-outstanding) | 4 | SMD solder | Mar 27, 2025 | PCB antenna mount |

## Power

| Component | Qty | Specs | Order Date | Notes |
|-----------|-----|-------|------------|-------|
| **MP1584EN 5V Buck Converters** | 5 | DC 5-30V→5V, 1.8A | Mar 31, 2025 | Field power regulation |
| **L7805CV Voltage Regulators** (BOJACK) | 25 | 5V, 1.5A, TO-220 | Mar 22, 2025 | Linear regulators |
| **MakerHawk 10000mAh LiPo** | 1 | 3.7V, PH2.0, ESP32 compatible | Mar 16, 2025 | Portable field power |

## Connectors / Wiring

| Component | Qty | Specs | Order Date | Notes |
|-----------|-----|-------|------------|-------|
| **PB1.25→Dupont 2.54mm Cables** | 1 kit | PicoBlade 1.25mm pitch, 20cm | Feb 4, 2026 | LiDAR/sensor cables |
| **ELEGOO Dupont Jumper Wires** | 120 | M-F, M-M, F-F, 40pin ribbon | Jan 16, 2026 | Prototyping |

## Expansion / IO

| Component | Qty | Interface | Order Date | Notes |
|-----------|-----|-----------|------------|-------|
| **NULLLAB IO Expansion Board** | 1 | I2C, 8ch ADC/IO, PWM | Feb 14, 2026 | Additional GPIO/ADC expansion |

## Optics / Laser

| Component | Qty | Specs | Order Date | Notes |
|-----------|-----|-------|------------|-------|
| **488nm Blue Laser Module** | 1 | Line projector, with mount | Feb 13, 2026 | Start line alignment / visual effect |

## Enclosures

| Component | Qty | Specs | Order Date | Notes |
|-----------|-----|-------|------------|-------|
| **LMioEtool IP65 Junction Box** | 1 | ABS, 150×100×70mm, clear cover | Mar 16, 2025 | Weatherproof electronics housing |

## Passive Components

| Component | Qty | Specs | Order Date | Notes |
|-----------|-----|-------|------------|-------|
| **1N4007 Rectifier Diodes** (BOJACK) | 125 | 1A, 1000V, DO-41 | Dec 30, 2025 | Reverse polarity protection |

## GPS (Potentially Useful)

| Component | Qty | Interface | Order Date | Notes |
|-----------|-----|-----------|------------|-------|
| **RAK12500 GNSS GPS Module + Antenna** | 1 | I2C/SPI | Mar 16, 2025 | Location services (originally for Meshtastic) |

---

## Summary by Use Case

### Core Race System (Already Integrated)
- TF-Luna LiDAR × 2 (auto-arm)
- IR Break Beam Sensors × 7+ pairs (start/finish triggers)
- ESP32 breakout boards (main MCU housing)
- BTF-LIGHTING WLED controllers × 3+ (LED effects)

### Sensor Pack (Phase Next — config.h Goal 14)
- BMP280 × 5 → air density (drag coefficient refinement)
- MLX90614 × 2 → track surface temperature (tire grip modeling)
- ADXL345 × 4 → track vibration / launch detection
- BNO055 × 1 → absolute orientation (track bank angle)
- WT901 IMU × 1 → high-precision 9-axis reference

### NFC Car Tagging (Designed, Awaiting Build)
- PN532 reader × 1 (UART to ESP32)
- NTAG213 stickers × 20 (on car bottoms)

### Onboard Telemetry (XIAO strapped to a Hot Wheels)
- XIAO ESP32-S3 Sense × 1 (WiFi + camera + mic)
- ADXL345 × 1 (acceleration logging during run)

### Audio System
- Diann DY-SV5W × 4 (UART-triggered sound effects)
- DWEII speakers × 8 (output)
- PAM8403 Bluetooth amp × 1 (wireless audio)

### Start Gate / Drag Tree
- Traffic light LEDs × 10 (visual countdown)
- Blue laser module × 1 (alignment)

### Displays (Dashboard / Kiosk)
- 7" ESP32-P4 touch × 1 (flagship dashboard display)
- 7" ESP32-S3 touch × 1 (secondary / pit display)
- 2.8" ESP32-S3 × 1 (compact status)
- TM1638 segment display × 1 (Daytona scanner theme!)

### Radio Experiments (Mesh Autonomy Phase 3+)
- NRF24L01+PA+LNA × 9 total (long-range 2.4GHz)
- 433MHz antennas × 2 (LoRa band)
- Various antenna adapters

### Power Solutions (Field Deployment)
- Buck converters × 5 (vehicle/bench power)
- Linear regulators × 25 (simple 5V)
- 10Ah LiPo × 1 (portable)
- Diodes × 125 (protection)

---

*Last updated: February 14, 2026*
*Source: Amazon order history, pages 1-7 of 19 (pages 8-19 are pre-project: Pwnagotchi, 3D printing, Meshtastic)*
