# Tallulah BLE Vehicle Monitor

This Flutter app allows you to monitor and control multiple BLE devices in your vehicle, including:
- Victron SmartShunt and SmartSolar
- Itechworld battery (with isolator controls)
- Topargee water tank gauge

## Features
- **Direct BLE Access:** Connect directly to supported BLE devices when nearby.
- **Multi-Device Support:** View live data from multiple devices simultaneously.
- **Water Tank Integration:** Monitor water tank capacity, usage, and reset tank meter from the app.
- **Isolator Controls:** Toggle charge/discharge isolators on Itechworld battery.
- **Status Indicators:** Real-time connection and data freshness indicators for each device.
- **Automatic Scanning:** Reliable BLE scanning with watchdog and health checks.
- **Modern UI:** Card-based layout for each device, with easy navigation.

## Security
- Sensitive information (MAC addresses, BLE keys) is stored in `lib/secrets.dart`, which is excluded from version control via `.gitignore`.

## Getting Started
- Install dependencies with `flutter pub get`.
- Add your device MAC addresses and keys to `lib/secrets.dart` (see template).
- Run the app on your device with `flutter run`.

## Secrets Setup

This app requires you to provide your own BLE device MAC addresses and keys for security. These are stored in `lib/secrets.dart`, which is excluded from version control.

**How to set up your secrets:**
1. Copy `lib/secrets_example.dart` to `lib/secrets.dart`.
2. Edit `lib/secrets.dart` and update the MAC addresses and keys to match your devices.
3. Do not commit `lib/secrets.dart` to version control (it's already excluded in `.gitignore`).

Example:
```dart
// lib/secrets.dart
const String SHUNT_MAC = "EB:FC:BD:2B:46:3B";
const List<int> SHUNT_BINDKEY = [0xd3, ...];
// ...etc
```

If you do not provide valid secrets, the app will not be able to connect to your BLE devices.

## Roadmap
- Historic trending and data logging (planned)
- ESP32/Raspberry Pi gateway integration for remote access
- API/MQTT support for home network viewing

---
For more details, see the code and comments in `lib/main.dart`.
