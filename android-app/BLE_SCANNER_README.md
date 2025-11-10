# BLE Scanner App

A simple Bluetooth Low Energy (BLE) scanner app built with Flutter.

## Features

- Scan for nearby BLE devices
- Display device information including:
  - Device name (or "Unknown Device" if not available)
  - Device ID (MAC address)
  - Signal strength (RSSI) in dBm
  - Signal quality indicator (Strong/Medium/Weak)
  - Number of advertised services
- Real-time scanning with start/stop controls
- Permission handling for Bluetooth and location access

## Permissions Required

The app requires the following permissions:
- **Bluetooth**: To access Bluetooth functionality
- **Bluetooth Admin**: To manage Bluetooth connections
- **Location**: Required for BLE scanning on Android
- **Bluetooth Scan**: For Android 12+ devices
- **Bluetooth Connect**: For Android 12+ devices

## How to Use

1. Launch the app
2. Grant the required permissions when prompted
3. Ensure Bluetooth is enabled on your device
4. Tap "Start Scan" to begin scanning for BLE devices
5. Nearby devices will appear in the list with their information
6. Tap "Stop Scan" to stop scanning
7. The signal strength indicator shows:
   - **Green (Strong)**: RSSI > -60 dBm
   - **Orange (Medium)**: RSSI between -80 and -60 dBm
   - **Red (Weak)**: RSSI < -80 dBm

## Dependencies

- `flutter_blue_plus`: For BLE functionality
- `permission_handler`: For managing app permissions

## Platform Support

- Android (primary target)
- iOS (with appropriate Info.plist configuration)
- Desktop platforms (with limited functionality)

## Notes

- The app scans for 10 seconds by default
- Location services must be enabled on Android for BLE scanning
- Some devices may not advertise their names and will show as "Unknown Device"
- The app automatically handles Bluetooth state changes and permission requests