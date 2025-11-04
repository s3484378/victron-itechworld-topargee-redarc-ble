#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// BLE UUIDs
#define SERVICE_UUID        "12345678-1234-1234-1234-123456789abc"
#define TELEMETRY_CHAR_UUID "87654321-4321-4321-4321-210987654321"  // Read/Notify characteristic for telemetry data
#define UPDATE_RATE_CHAR_UUID "11111111-2222-3333-4444-555555555555"  // Read/Write characteristic for update rate

// Individual solar panel data
struct SolarPanelData {
    float voltage;           // Volts
    float current;           // Amps
    float power;             // Watts
} __attribute__((packed));

// Individual battery monitor data
struct BatteryMonitorData {
    float voltage;           // Volts
    float current;           // Amps (negative = discharging)
    float power;             // Watts (negative = discharging)
    float stateOfCharge;     // Percentage (0-100)
    float timeToEmptyFull;   // Hours (positive = time to empty, negative = time to full)
} __attribute__((packed));

// Water tank data
struct WaterTankData {
    float percentage;        // Percentage (0-100)
    float litresRemaining;   // Current litres in tank
    float flowRate;          // Current flow rate L/min
    uint32_t lastRefillDate; // Days since epoch (or days since boot for simulation)
    float averageLPerDay;    // Average consumption L/day
    float estimatedDaysLeft; // Estimated days until empty
} __attribute__((packed));

// Complete telemetry data structure
struct TelemetryData {
    // Solar panels (2x panels, 12 bytes each = 24 bytes)
    SolarPanelData solarPanel1;
    SolarPanelData solarPanel2;
    
    // Battery monitors (2x monitors, 20 bytes each = 40 bytes)
    BatteryMonitorData batteryMonitor1;
    BatteryMonitorData batteryMonitor2;
    
    // Water tank (24 bytes)
    WaterTankData waterTank;
    
    // System info (8 bytes)
    uint32_t counter;        // Counter for demo purposes
    uint32_t timestamp;      // Milliseconds since boot
} __attribute__((packed));

// Global variables
TelemetryData telemetryData;
uint32_t updateRateMs = 1000;  // Default update rate: 1 second
unsigned long lastUpdate = 0;

// Boot button configuration
#define BOOT_BUTTON_PIN 0
bool lastBootButtonState = HIGH;
unsigned long lastButtonPress = 0;
const unsigned long BUTTON_DEBOUNCE_MS = 200;
bool forceWaterTankReset = false; // Flag to sync static variables

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
        Serial.println("Device disconnected - will restart advertising");
        // Stop advertising to clean up the BLE stack
        BLEDevice::getAdvertising()->stop();
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
    // Static variables for simulation state
    static float panel1Voltage = 18.5f, panel2Voltage = 18.2f;
    static float panel1Current = 8.0f, panel2Current = 7.5f;
    static float batt1Voltage = 12.0f, batt2Voltage = 12.1f;
    static float batt1Current = 8.0f, batt2Current = 7.8f;
    static float batt1SoC = 75.0f, batt2SoC = 73.0f;
    static float tankPct = 65.0f;
    static float tankCapacity = 400.0f; // 400L tank
    static float flowRate = 0.5f;
    static float avgConsumption = 25.0f; // L/day
    static uint32_t daysSinceBoot = 15; // Simulate 15 days since last refill
    static unsigned long lastMajorChange = 0;
    
    unsigned long currentTime = millis();
    
    // === SOLAR PANEL 1 ===
    panel1Voltage += (random(-20, 21) / 1000.0f); // ±0.02V variation
    panel1Voltage = constrain(panel1Voltage, 0.0f, 22.0f);
    panel1Current += (random(-50, 51) / 1000.0f); // ±0.05A variation
    panel1Current = constrain(panel1Current, 0.0f, 15.0f);
    telemetryData.solarPanel1.voltage = panel1Voltage;
    telemetryData.solarPanel1.current = panel1Current;
    telemetryData.solarPanel1.power = panel1Voltage * panel1Current;
    
    // === SOLAR PANEL 2 ===
    panel2Voltage += (random(-20, 21) / 1000.0f);
    panel2Voltage = constrain(panel2Voltage, 0.0f, 22.0f);
    panel2Current += (random(-50, 51) / 1000.0f);
    panel2Current = constrain(panel2Current, 0.0f, 15.0f);
    telemetryData.solarPanel2.voltage = panel2Voltage;
    telemetryData.solarPanel2.current = panel2Current;
    telemetryData.solarPanel2.power = panel2Voltage * panel2Current;
    
    // === BATTERY MONITOR 1 ===
    batt1Voltage += (random(-30, 31) / 1000.0f); // ±0.03V variation
    batt1Voltage = constrain(batt1Voltage, 10.5f, 14.4f);
    batt1Current += (random(-100, 101) / 1000.0f); // ±0.1A variation
    batt1Current = constrain(batt1Current, -50.0f, 50.0f);
    batt1SoC += (random(-10, 11) / 1000.0f); // ±0.01% variation
    batt1SoC = constrain(batt1SoC, 0.0f, 100.0f);
    
    telemetryData.batteryMonitor1.voltage = batt1Voltage;
    telemetryData.batteryMonitor1.current = batt1Current;
    telemetryData.batteryMonitor1.power = batt1Voltage * batt1Current;
    telemetryData.batteryMonitor1.stateOfCharge = batt1SoC;
    // Time calculation: positive = time to empty, negative = time to full
    if (batt1Current < -0.1f) { // Discharging
        telemetryData.batteryMonitor1.timeToEmptyFull = (batt1SoC / 100.0f) * 200.0f / abs(batt1Current); // Assume 200Ah capacity
    } else if (batt1Current > 0.1f) { // Charging
        telemetryData.batteryMonitor1.timeToEmptyFull = -((100.0f - batt1SoC) / 100.0f) * 200.0f / batt1Current;
    } else {
        telemetryData.batteryMonitor1.timeToEmptyFull = 999.0f; // Standby
    }
    
    // === BATTERY MONITOR 2 ===
    batt2Voltage += (random(-30, 31) / 1000.0f);
    batt2Voltage = constrain(batt2Voltage, 10.5f, 14.4f);
    batt2Current += (random(-100, 101) / 1000.0f);
    batt2Current = constrain(batt2Current, -50.0f, 50.0f);
    batt2SoC += (random(-10, 11) / 1000.0f);
    batt2SoC = constrain(batt2SoC, 0.0f, 100.0f);
    
    telemetryData.batteryMonitor2.voltage = batt2Voltage;
    telemetryData.batteryMonitor2.current = batt2Current;
    telemetryData.batteryMonitor2.power = batt2Voltage * batt2Current;
    telemetryData.batteryMonitor2.stateOfCharge = batt2SoC;
    if (batt2Current < -0.1f) {
        telemetryData.batteryMonitor2.timeToEmptyFull = (batt2SoC / 100.0f) * 200.0f / abs(batt2Current);
    } else if (batt2Current > 0.1f) {
        telemetryData.batteryMonitor2.timeToEmptyFull = -((100.0f - batt2SoC) / 100.0f) * 200.0f / batt2Current;
    } else {
        telemetryData.batteryMonitor2.timeToEmptyFull = 999.0f;
    }
    
    // === WATER TANK ===
    // Handle forced reset from button press
    if (forceWaterTankReset) {
        tankPct = 100.0f;
        daysSinceBoot = 0;
        avgConsumption = 25.0f; // Reset to default
        lastMajorChange = currentTime; // Reset major change timer
        forceWaterTankReset = false; // Clear the flag
        Serial.println("Water tank static variables synced to 100%");
    }
    
    // Major changes every 15 seconds
    if (currentTime - lastMajorChange > 15000) {
        if (random(0, 100) < 15) { // 15% chance of refill
            tankPct = random(8500, 10000) / 100.0f; // Refill to 85-100%
            daysSinceBoot = 0; // Reset refill date
            avgConsumption = random(2000, 4000) / 100.0f; // Recalc average 20-40 L/day
        }
        lastMajorChange = currentTime;
    }
    
    // Normal consumption
    tankPct -= random(0, 8) / 10000.0f; // Slow decrease 0-0.008% per update
    tankPct = constrain(tankPct, 0.0f, 100.0f);
    
    // Flow rate simulation
    if (tankPct < 2.0f) {
        flowRate = 0.0f;
    } else {
        flowRate = (random(0, 500) / 100.0f) * (tankPct / 100.0f);
        if (random(0, 100) < 3) { // 3% chance of high flow
            flowRate += random(800, 1500) / 100.0f;
        }
    }
    flowRate = constrain(flowRate, 0.0f, 20.0f);
    
    // Update water tank data
    telemetryData.waterTank.percentage = tankPct;
    telemetryData.waterTank.litresRemaining = (tankPct / 100.0f) * tankCapacity;
    telemetryData.waterTank.flowRate = flowRate;
    telemetryData.waterTank.lastRefillDate = daysSinceBoot;
    telemetryData.waterTank.averageLPerDay = avgConsumption;
    telemetryData.waterTank.estimatedDaysLeft = (telemetryData.waterTank.litresRemaining > 0) ? 
                                               (telemetryData.waterTank.litresRemaining / avgConsumption) : 0.0f;
    
    // === SYSTEM INFO ===
    telemetryData.counter++;
    telemetryData.timestamp = millis();
    daysSinceBoot = millis() / (24 * 60 * 60 * 1000); // Convert to days for simulation
}

void setup() {
    Serial.begin(115200);
    Serial.println("Starting BLE Telemetry Service...");

    // Initialize boot button
    pinMode(BOOT_BUTTON_PIN, INPUT_PULLUP);
    Serial.println("Boot button initialized (GPIO 0) - Press to refill water tank to 100%");

    // Initialize telemetry data with default values
    memset(&telemetryData, 0, sizeof(telemetryData));
    
    // Initialize solar panels
    telemetryData.solarPanel1.voltage = 18.5f;
    telemetryData.solarPanel2.voltage = 18.2f;
    
    // Initialize battery monitors
    telemetryData.batteryMonitor1.voltage = 12.5f;
    telemetryData.batteryMonitor1.stateOfCharge = 75.0f;
    telemetryData.batteryMonitor2.voltage = 12.4f;
    telemetryData.batteryMonitor2.stateOfCharge = 73.0f;
    
    // Initialize water tank
    telemetryData.waterTank.percentage = 65.0f;
    telemetryData.waterTank.litresRemaining = 260.0f; // 65% of 400L
    telemetryData.waterTank.averageLPerDay = 25.0f;
    
    telemetryData.counter = 0;

    // Initialize BLE
    BLEDevice::init("Tallulah");
    
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
    
    // Update telemetry data only when a device is connected
    if (deviceConnected && (currentTime - lastUpdate >= updateRateMs)) {
        // Update all sensor data
        updateSensorData();
        
        // Update the characteristic value with complete telemetry data
        pTelemetryCharacteristic->setValue((uint8_t*)&telemetryData, sizeof(telemetryData));
        
        // Notify connected client
        pTelemetryCharacteristic->notify();
        
        // Print telemetry data to serial for debugging
        Serial.println("=== Telemetry Update ===");
        Serial.printf("Solar Panel 1: %.2fV, %.2fA, %.1fW\n", 
                      telemetryData.solarPanel1.voltage,
                      telemetryData.solarPanel1.current,
                      telemetryData.solarPanel1.power);
        Serial.printf("Solar Panel 2: %.2fV, %.2fA, %.1fW\n", 
                      telemetryData.solarPanel2.voltage,
                      telemetryData.solarPanel2.current,
                      telemetryData.solarPanel2.power);
        Serial.printf("Battery Mon 1: %.2fV, %.2fA, %.1fW, %.1f%% SoC, %.1fh TTx\n", 
                      telemetryData.batteryMonitor1.voltage,
                      telemetryData.batteryMonitor1.current,
                      telemetryData.batteryMonitor1.power,
                      telemetryData.batteryMonitor1.stateOfCharge,
                      telemetryData.batteryMonitor1.timeToEmptyFull);
        Serial.printf("Battery Mon 2: %.2fV, %.2fA, %.1fW, %.1f%% SoC, %.1fh TTx\n", 
                      telemetryData.batteryMonitor2.voltage,
                      telemetryData.batteryMonitor2.current,
                      telemetryData.batteryMonitor2.power,
                      telemetryData.batteryMonitor2.stateOfCharge,
                      telemetryData.batteryMonitor2.timeToEmptyFull);
        Serial.printf("Water Tank: %.1f%% (%.1fL), %.2f L/min, %u days since refill\n", 
                      telemetryData.waterTank.percentage,
                      telemetryData.waterTank.litresRemaining,
                      telemetryData.waterTank.flowRate,
                      telemetryData.waterTank.lastRefillDate);
        Serial.printf("Water Stats: %.1f L/day avg, %.1f days remaining\n", 
                      telemetryData.waterTank.averageLPerDay,
                      telemetryData.waterTank.estimatedDaysLeft);
        Serial.printf("Counter: %u, Timestamp: %u ms, Data Size: %u bytes\n", 
                      telemetryData.counter, 
                      telemetryData.timestamp,
                      sizeof(telemetryData));
        Serial.printf("Update Rate: %u ms\n", updateRateMs);
        Serial.println("========================");
        
        lastUpdate = currentTime;
    }
    
    // Handle boot button press for water tank refill
    bool currentBootButtonState = digitalRead(BOOT_BUTTON_PIN);
    if (currentBootButtonState == LOW && lastBootButtonState == HIGH && 
        (currentTime - lastButtonPress) > BUTTON_DEBOUNCE_MS) {
        // Button pressed (LOW = pressed due to pullup)
        Serial.println("Boot button pressed - Refilling water tank to 100%!");
        
        // Reset water tank to full and sync with updateSensorData() static variables
        telemetryData.waterTank.percentage = 100.0f;
        telemetryData.waterTank.litresRemaining = 400.0f; // Full 400L tank
        telemetryData.waterTank.lastRefillDate = 0; // Reset refill date
        
        // Signal updateSensorData() to reset its static variables
        forceWaterTankReset = true;
        
        // Update the characteristic if connected
        if (deviceConnected) {
            pTelemetryCharacteristic->setValue((uint8_t*)&telemetryData, sizeof(telemetryData));
            pTelemetryCharacteristic->notify();
            Serial.println("Water tank refill data sent to connected device");
        }
        
        lastButtonPress = currentTime;
    }
    lastBootButtonState = currentBootButtonState;
    
    // Show advertising status when no device connected (less frequent)
    static unsigned long lastAdvertisingMsg = 0;
    if (!deviceConnected && (currentTime - lastAdvertisingMsg >= 10000)) { // Every 10 seconds
        Serial.println("Waiting for BLE connection...");
        lastAdvertisingMsg = currentTime;
    }
    
    // Handle connection status changes
    if (!deviceConnected && oldDeviceConnected) {
        Serial.println("Handling disconnection...");
        delay(1000); // Give the BLE stack time to clean up properly
        
        // Restart advertising with fresh configuration
        BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
        pAdvertising->stop(); // Ensure it's stopped
        delay(100);
        
        // Reconfigure advertising
        pAdvertising = BLEDevice::getAdvertising();
        pAdvertising->addServiceUUID(SERVICE_UUID);
        pAdvertising->setScanResponse(false);
        pAdvertising->setMinPreferred(0x0);
        
        // Start advertising again
        BLEDevice::startAdvertising();
        Serial.println("Advertising restarted successfully");
        
        oldDeviceConnected = deviceConnected;
    }
    
    if (deviceConnected && !oldDeviceConnected) {
        Serial.println("New device connected");
        oldDeviceConnected = deviceConnected;
    }
    
    delay(10); // Small delay to prevent watchdog issues
}