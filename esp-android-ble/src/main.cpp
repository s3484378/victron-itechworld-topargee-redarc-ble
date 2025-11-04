#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// BLE UUIDs
#define SERVICE_UUID        "12345678-1234-1234-1234-123456789abc"
#define TELEMETRY_CHAR_UUID "87654321-4321-4321-4321-210987654321"  // Read/Notify characteristic for telemetry data
#define UPDATE_RATE_CHAR_UUID "11111111-2222-3333-4444-555555555555"  // Read/Write characteristic for update rate

// Telemetry data structure (48 bytes total)
struct TelemetryData {
    // Battery data (12 bytes)
    float batteryVoltage;    // Volts
    float batteryCurrent;    // Amps (negative = discharging)
    float batteryPower;      // Watts (negative = discharging)
    
    // Solar data (4 bytes)
    float solarPower;        // Watts
    
    // Water tank data (8 bytes)
    float tankPercentage;    // Percentage (0-100)
    float tankLitersPerMin;  // Current flow rate L/min
    
    // Counter for demo purposes (4 bytes)
    uint32_t counter;
    
    // Timestamp (4 bytes)
    uint32_t timestamp;      // Milliseconds since boot
} __attribute__((packed));

// Global variables
TelemetryData telemetryData;
uint32_t updateRateMs = 1000;  // Default update rate: 1 second
unsigned long lastUpdate = 0;

// BLE objects
BLEServer* pServer = nullptr;
BLECharacteristic* pTelemetryCharacteristic = nullptr;
BLECharacteristic* pUpdateRateCharacteristic = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Server callbacks
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println("Device connected");
    };

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println("Device disconnected");
    }
};

// Callback for update rate characteristic writes
class UpdateRateCharacteristicCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        
        if (value.length() == 4) { // Expecting 4 bytes for uint32
            uint32_t newRate = *(uint32_t*)value.data();
            if (newRate >= 100 && newRate <= 60000) { // Limit between 100ms and 60 seconds
                updateRateMs = newRate;
                Serial.print("Update rate set to: ");
                Serial.print(updateRateMs);
                Serial.println(" ms");
            } else {
                Serial.println("Invalid update rate (must be 100-60000 ms)");
            }
        } else {
            Serial.println("Invalid update rate value length");
        }
    }
};

// Function to simulate sensor readings
void updateSensorData() {
    static float battVoltage = 12.0f;    // Start at nominal 12V
    static float battCurrent = 8.0f;     // Start with moderate charging
    static float solarPwr = 250.0f;      // Start at half max solar
    static float tankPct = 65.0f;        // Start at 65% full
    static float flowRate = 0.5f;        // Start with small flow
    static unsigned long lastSolarChange = 0;
    static unsigned long lastTankChange = 0;
    
    // Simulate realistic battery voltage (12V system: 10.5V empty to 14.4V full charge)
    battVoltage += (random(-30, 31) / 1000.0f);  // ±0.03V variation per update
    battVoltage = constrain(battVoltage, 10.5f, 14.4f);
    
    // Simulate battery current based on solar and load conditions
    // Positive = charging, negative = discharging
    float baseLoad = -3.0f + (random(-200, 201) / 100.0f); // Base load -1A to -5A
    float solarContribution = (solarPwr > 50) ? solarPwr / 12.0f : 0.0f; // Rough current from solar
    battCurrent = baseLoad + solarContribution + (random(-50, 51) / 100.0f); // Add some noise
    battCurrent = constrain(battCurrent, -25.0f, 30.0f);
    
    // Simulate solar power with day/night cycle and weather variations
    unsigned long currentTime = millis();
    if (currentTime - lastSolarChange > 5000) { // Change solar conditions every 5 seconds
        // Simulate clouds, sun intensity changes
        float solarChange = random(-5000, 5001) / 100.0f; // ±50W change
        solarPwr += solarChange;
        lastSolarChange = currentTime;
    }
    // Add small continuous variations
    solarPwr += (random(-200, 201) / 100.0f);  // ±2W variation
    solarPwr = constrain(solarPwr, 0.0f, 500.0f); // Your 500W max panels
    
    // Simulate water tank level changes (slowly decreasing with occasional refills)
    if (currentTime - lastTankChange > 10000) { // Major tank changes every 10 seconds
        if (random(0, 100) < 10) { // 10% chance of refill
            tankPct += random(1000, 2500) / 100.0f; // Add 10-25%
        }
        lastTankChange = currentTime;
    }
    // Normal consumption
    tankPct -= random(0, 5) / 1000.0f; // Slow decrease 0-0.5% per update
    tankPct = constrain(tankPct, 0.0f, 100.0f);
    
    // Simulate water flow rate (correlates somewhat with tank level)
    if (tankPct < 5.0f) {
        flowRate = 0.0f; // No flow when tank nearly empty
    } else {
        flowRate = (random(0, 1000) / 100.0f) * (tankPct / 100.0f); // 0-10 L/min, scaled by tank level
        // Occasional burst flow (pump cycling)
        if (random(0, 100) < 5) { // 5% chance
            flowRate += random(500, 2000) / 100.0f; // Add 5-20 L/min burst
        }
    }
    flowRate = constrain(flowRate, 0.0f, 25.0f);
    
    // Update telemetry data
    telemetryData.batteryVoltage = battVoltage;
    telemetryData.batteryCurrent = battCurrent;
    telemetryData.batteryPower = battVoltage * battCurrent; // Calculate power (can be negative)
    telemetryData.solarPower = solarPwr;
    telemetryData.tankPercentage = tankPct;
    telemetryData.tankLitersPerMin = flowRate;
    telemetryData.counter++;
    telemetryData.timestamp = millis();
}

void setup() {
    Serial.begin(115200);
    Serial.println("Starting BLE Telemetry Service...");

    // Initialize telemetry data with default values
    memset(&telemetryData, 0, sizeof(telemetryData));
    telemetryData.batteryVoltage = 12.5f;
    telemetryData.batteryCurrent = 0.0f;
    telemetryData.batteryPower = 0.0f;
    telemetryData.solarPower = 0.0f;
    telemetryData.tankPercentage = 75.0f;
    telemetryData.tankLitersPerMin = 0.0f;
    telemetryData.counter = 0;

    // Initialize BLE
    BLEDevice::init("ESP32-Telemetry");
    
    // Create BLE Server
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    // Create BLE Service
    BLEService *pService = pServer->createService(SERVICE_UUID);

    // Create Telemetry Characteristic (Read + Notify)
    pTelemetryCharacteristic = pService->createCharacteristic(
        TELEMETRY_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    
    // Add descriptor for notifications
    pTelemetryCharacteristic->addDescriptor(new BLE2902());

    // Create Update Rate Characteristic (Read + Write)
    pUpdateRateCharacteristic = pService->createCharacteristic(
        UPDATE_RATE_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_WRITE
    );
    
    // Set callback for update rate characteristic
    pUpdateRateCharacteristic->setCallbacks(new UpdateRateCharacteristicCallbacks());

    // Set initial values
    pTelemetryCharacteristic->setValue((uint8_t*)&telemetryData, sizeof(telemetryData));
    pUpdateRateCharacteristic->setValue((uint8_t*)&updateRateMs, 4);

    // Start the service
    pService->start();

    // Start advertising
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(false);
    pAdvertising->setMinPreferred(0x0);  // set value to 0x00 to not advertise this parameter
    BLEDevice::startAdvertising();
    
    Serial.println("BLE telemetry service started and advertising...");
    Serial.println("Service UUID: " + String(SERVICE_UUID));
    Serial.println("Telemetry Characteristic UUID: " + String(TELEMETRY_CHAR_UUID));
    Serial.println("Update Rate Characteristic UUID: " + String(UPDATE_RATE_CHAR_UUID));
    Serial.println("Data structure size: " + String(sizeof(telemetryData)) + " bytes");
}

void loop() {
    unsigned long currentTime = millis();
    
    // Update telemetry data at specified rate
    if (currentTime - lastUpdate >= updateRateMs) {
        // Update all sensor data
        updateSensorData();
        
        // Update the characteristic value with complete telemetry data
        pTelemetryCharacteristic->setValue((uint8_t*)&telemetryData, sizeof(telemetryData));
        
        // Notify connected clients if any
        if (deviceConnected) {
            pTelemetryCharacteristic->notify();
        }
        
        // Print telemetry data to serial for debugging
        Serial.println("=== Telemetry Update ===");
        Serial.printf("Battery: %.2fV, %.2fA, %.1fW\n", 
                      telemetryData.batteryVoltage, 
                      telemetryData.batteryCurrent, 
                      telemetryData.batteryPower);
        Serial.printf("Solar: %.1fW\n", telemetryData.solarPower);
        Serial.printf("Water Tank: %.1f%%, %.2f L/min\n", 
                      telemetryData.tankPercentage, 
                      telemetryData.tankLitersPerMin);
        Serial.printf("Counter: %u, Timestamp: %u ms\n", 
                      telemetryData.counter, 
                      telemetryData.timestamp);
        Serial.printf("Update Rate: %u ms\n", updateRateMs);
        Serial.println("========================");
        
        lastUpdate = currentTime;
    }
    
    // Handle connection status changes
    if (!deviceConnected && oldDeviceConnected) {
        delay(500); // give the bluetooth stack the chance to get things ready
        pServer->startAdvertising(); // restart advertising
        Serial.println("Restarting advertising...");
        oldDeviceConnected = deviceConnected;
    }
    
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }
    
    delay(10); // Small delay to prevent watchdog issues
}