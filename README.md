# victron-itechworld-topargee-redarc-ble

Attempt at an ESP32 based BLE device to consolidate the readings from an Itechworld 240X battery, Redarc Alpha 50 DC-DC charger, Victron Smart Shunt and Topargee BLE water gauge

## Hardware - in progress
Developing using a TTGO 18560 board with OLED display and an android app built using Flutter framework - aim will be to have this on a custom touch panel to allow control (isolate battery, reset water gauge etc)


## Project Checklist
- [x] Itechworld 240X Pro
- [x] Victron 300A smart shunt
- [x] Victron 20A Smart Solar
- [x] Topargee BLE Tank sensor
- [ ] Redarc Alpha 50
- [x] Android app to view all data in single screen
- [ ] ESP32 data concentrator
- [ ] Raspberry Pi data concentrator/datalogger

## Current Project Structure
Currently the devices are still being reverse engineered. For a speedy process, python is being used for the reverse engineering and data decoding. There is a folder for each device where the final (if completed) python script is located to extract data from these devices. If you want to replicate, you'll most likely need to create a secrets.py file that will include the device MAC address you're trying to connect to and any other secrets you may need (like a bind key for your Victron devices).

## Ultimate Goal
Raspberry Pi will connect to and poll all BLE devices data. Pi will also act as a BLE server that my phone can connect to when in range to view the latest data for each connected device. Control commands can also be sent (to reset the water tank for example).

## Features
- [ ] Homeassistant integration when Raspberry Pi is in WiFi range or connected to VPN
- [ ] Standalone screen for quick glance of data (ESP32 OLED, etc)
- [ ] Phone app to connect locally via BLE to Raspberry Pi, or via API/MQTT if remote
- [ ] Ability to store and forward historic data (e.g. go on 2 week trip, Pi stores data locally, on return home and connect to home WiFi, backfill Homeassistant database)
- [ ] Possibly add GPS data logger in Pi to automate drawing trips onto a map
