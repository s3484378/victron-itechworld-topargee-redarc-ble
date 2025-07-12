# victron-itechworld-topargee-redarc-ble

Attempt at an ESP32 based BLE device to consolidate the readings from an Itechworld 240X battery, Redarc Alpha 50 DC-DC charger, Victron Smart Shunt and Topargee BLE water gauge

## Hardware - in progress
Developing using a TTGO 18560 board with OLED display - aim will be to have this on a custom touch panel to allow control (isolate battery, reset water gauge etc)

## Setup Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/victron-itechworld-topargee-redarc-ble.git
cd victron-itechworld-topargee-redarc-ble
```

### 2. Configure Secrets
Before building the project, you need to create a secrets file with your device-specific information:

1. Copy the template file:
   ```bash
   cp include/secrets_template.h include/secrets.h
   ```

2. Edit `include/secrets.h` and replace the placeholder values with your actual device information:
   - `BATTERY_MAC_ADDRESS`: The MAC address of your target BLE device
   - `DEVICE_NAME`: The name your ESP32 should advertise as

### 3. Build and Upload
Use PlatformIO to build and upload the firmware to your ESP32:
```bash
platformio run --target upload
```

### 4. Monitor Serial Output
```bash
platformio device monitor
```

## Project Structure
- `src/main.cpp` - Main BLE proxy application
- `include/secrets.h` - Device-specific configuration (not tracked by git)
- `include/secrets_template.h` - Template for secrets configuration
- `raw_data/` - Sample BLE communication data
- `backup/` - Backup files (not tracked by git)

## Features
- **BLE Transparent Proxy**: Acts as a man-in-the-middle between your phone and BLE device
- **Complete Service Cloning**: Automatically discovers and replicates all BLE services
- **Real-time Monitoring**: Logs all BLE communication for analysis
- **Command Discovery**: Captures the exact commands sent by mobile apps

## Security Note
The `secrets.h` file contains sensitive information like MAC addresses and is excluded from version control. Always use the template file to create your own secrets configuration.