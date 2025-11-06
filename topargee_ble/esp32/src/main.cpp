
#include <Arduino.h>
#include <ArduinoBLE.h>



#include "secrets.h"
// Custom service/characteristics from pdml
const char* SERVICE_UUID = "fff0"; // Custom service
const char* CHARACTERISTIC_UUID_NOTIFY = "fff4"; // Actual notify characteristic from Wireshark

BLEDevice topargeeDevice;
BLECharacteristic notifyChar;

void setup() {
  Serial.begin(115200);
  while (!Serial);

  if (!BLE.begin()) {
    Serial.println("Starting BLE failed!");
    while (1);
  }

  Serial.println("Scanning for Topargee BLE device...");
  BLE.scan();

  // Wait for device by MAC address
  while (true) {
    topargeeDevice = BLE.available();
    if (topargeeDevice && topargeeDevice.address() == DEVICE_ADDRESS) {
      Serial.print("Device found: ");
      Serial.println(topargeeDevice.address());
      BLE.stopScan();
      if (topargeeDevice.connect()) {
        Serial.println("Connected!");
        break;
      } else {
        Serial.println("Connection failed, retrying...");
        BLE.scan();
      }
    }
    delay(100);
  }

  // Discover custom service
  if (topargeeDevice.discoverService(SERVICE_UUID)) {
    Serial.println("Custom service discovered.");

    // List of known characteristic UUIDs from pdml
    const char* knownCharacteristicUUIDs[] = {
      "2a00", // Device Name
      "2a01", // Appearance
      "2a02", // Peripheral Privacy Flag
      "2a03", // Reconnection Address
      "2a04", // Peripheral Preferred Connection Parameters
      "fff1", // Custom (notifies? try reading anyway)
      "fff2", // Custom
      "fff3", // Custom
      "fff4"  // Notification characteristic
    };
    const int numCharacteristics = sizeof(knownCharacteristicUUIDs) / sizeof(knownCharacteristicUUIDs[0]);

    // Try reading each known characteristic
    for (int i = 0; i < numCharacteristics; i++) {
      BLECharacteristic c = topargeeDevice.characteristic(knownCharacteristicUUIDs[i]);
      if (c) {
        Serial.print("Characteristic UUID: ");
        Serial.println(knownCharacteristicUUIDs[i]);
        if (c.canRead()) {
          int len = c.valueLength();
          const uint8_t* val = c.value();
          Serial.print("Read value: ");
          for (int j = 0; j < len; j++) {
            Serial.print(val[j], HEX);
            Serial.print(" ");
          }
          Serial.println();
        }
      } else {
        Serial.print("Characteristic not found: ");
        Serial.println(knownCharacteristicUUIDs[i]);
      }
      delay(100);
    }

    // Now subscribe to notifications on fff4
    notifyChar = topargeeDevice.characteristic(CHARACTERISTIC_UUID_NOTIFY);
    if (notifyChar) {
      if (notifyChar.canSubscribe()) {
        notifyChar.subscribe();
        Serial.println("Subscribed to notifications on fff4.");
      } else {
        Serial.println("fff4 does not support notifications.");
      }
    } else {
      Serial.println("Notify characteristic fff4 not found.");
    }
  } else {
    Serial.println("Custom service fff0 not found.");
  }
}

void loop() {
  BLE.poll();

  if (notifyChar && notifyChar.valueUpdated()) {
    int len = notifyChar.valueLength();
    const uint8_t* data = notifyChar.value();
    Serial.print("Notification received: ");
    for (int i = 0; i < len; i++) {
      Serial.print(data[i], HEX);
      Serial.print(" ");
    }
    Serial.println();
  }
}