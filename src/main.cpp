#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>

#include <Adafruit_SSD1306.h>
#include <BLEDevice.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET    -1
#define SCREEN_ADDRESS 0x3C

// Use custom I2C pins: SDA = 5, SCL = 4
TwoWire myWire = TwoWire(0);
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &myWire, OLED_RESET);


void setup() {
  Serial.begin(115200);
  Serial.println("Starting I2C OLED display...");
  myWire.begin(5, 4); // SDA, SCL
  if(!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
    Serial.println(F("SSD1306 allocation failed"));
    for(;;);
  }
  display.clearDisplay();
  display.setTextSize(2); // Medium font size
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("Hello World");
  display.display();

  BLEDevice::init("");
  BLEScan* pBLEScan = BLEDevice::getScan();
  pBLEScan->setActiveScan(true);
  Serial.println("Starting BLE scan for 5 seconds...");
  BLEScanResults foundDevices = pBLEScan->start(5, false);
  int count = foundDevices.getCount();
  Serial.printf("Scan complete. %d device(s) found.\n", count);
  for (int i = 0; i < count; ++i) {
    BLEAdvertisedDevice d = foundDevices.getDevice(i);
    Serial.print("Found device: ");
    if (d.haveName()) {
      Serial.print(d.getName().c_str());
      Serial.print(" ");
    }
    Serial.println(d.getAddress().toString().c_str());
  }
}

void loop() {
  // Nothing to do here
}