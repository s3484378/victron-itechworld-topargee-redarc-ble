#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEClient.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <map>
#include "secrets.h"

// Target battery device
BLEAddress batteryAddress(BATTERY_MAC_ADDRESS);

// BLE Server (appears as battery to phone)
BLEServer* pServer = nullptr;
BLEClient* pClient = nullptr;

bool deviceConnected = false;
bool batteryConnected = false;
bool servicesCloned = false;

// Maps to store service/characteristic relationships
std::map<std::string, BLEService*> serverServices;
std::map<std::string, BLECharacteristic*> serverCharacteristics;
std::map<std::string, BLERemoteService*> remoteServices;
std::map<std::string, BLERemoteCharacteristic*> remoteCharacteristics;

// All service UUIDs from your snapshot data
const char* serviceUUIDs[] = {
  "00001800-0000-1000-8000-00805f9b34fb",  // Generic Access
  "00001801-0000-1000-8000-00805f9b34fb",  // Generic Attribute  
  "0000180a-0000-1000-8000-00805f9b34fb",  // Device Information
  "0000ff00-0000-1000-8000-00805f9b34fb",  // Custom Service
  "00010203-0405-0607-0809-0a0b0c0d1912"   // OTA Service
};

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Phone connected to ESP32 proxy!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Phone disconnected from ESP32 proxy!");
    }
};

class TransparentCharacteristicCallbacks: public BLECharacteristicCallbacks {
  private:
    std::string charUUID;
    
  public:
    TransparentCharacteristicCallbacks(std::string uuid) : charUUID(uuid) {}
    
    void onWrite(BLECharacteristic* pCharacteristic) {
      std::string value = pCharacteristic->getValue();
      
      Serial.println("\n=== PHONE → BATTERY (via ESP32) ===");
      Serial.printf("Characteristic: %s\n", charUUID.c_str());
      Serial.printf("Length: %d bytes\n", value.length());
      Serial.print("Data: ");
      for (int i = 0; i < value.length(); i++) {
        Serial.printf("%02X ", (uint8_t)value[i]);
      }
      Serial.println();
      Serial.println("==================================\n");
      
      // Forward to real battery if connected
      if (batteryConnected && remoteCharacteristics.find(charUUID) != remoteCharacteristics.end()) {
        BLERemoteCharacteristic* pRemoteChar = remoteCharacteristics[charUUID];
        if (pRemoteChar != nullptr) {
          pRemoteChar->writeValue((uint8_t*)value.data(), value.length(), false);
          Serial.println("→ Forwarded to real battery");
        }
      }
    }
    
    void onRead(BLECharacteristic* pCharacteristic) {
      Serial.printf("Read request on characteristic: %s\n", charUUID.c_str());
      
      // Read from real battery and forward response
      if (batteryConnected && remoteCharacteristics.find(charUUID) != remoteCharacteristics.end()) {
        BLERemoteCharacteristic* pRemoteChar = remoteCharacteristics[charUUID];
        if (pRemoteChar != nullptr && pRemoteChar->canRead()) {
          std::string value = pRemoteChar->readValue();
          pCharacteristic->setValue(value);
          
          Serial.printf("Read response (%d bytes): ", value.length());
          for (int i = 0; i < value.length(); i++) {
            Serial.printf("%02X ", (uint8_t)value[i]);
          }
          Serial.println();
        }
      }
    }
};

void batteryNotifyCallback(BLERemoteCharacteristic* pBLERemoteCharacteristic,
                          uint8_t* pData, size_t length, bool isNotify) {
  std::string charUUID = pBLERemoteCharacteristic->getUUID().toString();
  
  Serial.println("\n=== BATTERY → PHONE (via ESP32) ===");
  Serial.printf("Characteristic: %s\n", charUUID.c_str());
  Serial.printf("Length: %d bytes\n", length);
  Serial.print("Data: ");
  for (int i = 0; i < length; i++) {
    Serial.printf("%02X ", pData[i]);
  }
  Serial.println();
  Serial.println("==================================\n");
  
  // Forward to phone if connected
  if (deviceConnected && serverCharacteristics.find(charUUID) != serverCharacteristics.end()) {
    BLECharacteristic* pServerChar = serverCharacteristics[charUUID];
    if (pServerChar != nullptr) {
      pServerChar->setValue(pData, length);
      pServerChar->notify();
      Serial.println("→ Forwarded to phone");
    }
  }
}

void cloneServicesFromBattery() {
  if (!batteryConnected || servicesCloned) return;
  
  Serial.println("Cloning all services from battery...");
  
  // Get all services from the battery
  std::map<std::string, BLERemoteService*>* pServiceMap = pClient->getServices();
  
  for (auto& servicePair : *pServiceMap) {
    std::string serviceUUID = servicePair.first;
    BLERemoteService* pRemoteService = servicePair.second;
    
    Serial.printf("Cloning service: %s\n", serviceUUID.c_str());
    
    // Create corresponding server service
    BLEService* pServerService = pServer->createService(serviceUUID);
    serverServices[serviceUUID] = pServerService;
    remoteServices[serviceUUID] = pRemoteService;
    
    // Get all characteristics for this service
    std::map<std::string, BLERemoteCharacteristic*>* pCharMap = pRemoteService->getCharacteristics();
    
    for (auto& charPair : *pCharMap) {
      std::string charUUID = charPair.first;
      BLERemoteCharacteristic* pRemoteChar = charPair.second;
      
      Serial.printf("  Cloning characteristic: %s\n", charUUID.c_str());
      
      // Determine properties
      uint32_t properties = 0;
      if (pRemoteChar->canRead()) properties |= BLECharacteristic::PROPERTY_READ;
      if (pRemoteChar->canWrite()) properties |= BLECharacteristic::PROPERTY_WRITE;
      if (pRemoteChar->canWriteNoResponse()) properties |= BLECharacteristic::PROPERTY_WRITE_NR;
      if (pRemoteChar->canNotify()) properties |= BLECharacteristic::PROPERTY_NOTIFY;
      if (pRemoteChar->canIndicate()) properties |= BLECharacteristic::PROPERTY_INDICATE;
      
      // Create server characteristic
      BLECharacteristic* pServerChar = pServerService->createCharacteristic(charUUID, properties);
      
      // Set callbacks
      pServerChar->setCallbacks(new TransparentCharacteristicCallbacks(charUUID));
      
      // Add descriptors if it can notify/indicate
      if (pRemoteChar->canNotify() || pRemoteChar->canIndicate()) {
        pServerChar->addDescriptor(new BLE2902());
      }
      
      // Store references
      serverCharacteristics[charUUID] = pServerChar;
      remoteCharacteristics[charUUID] = pRemoteChar;
      
      // Set up notifications from battery
      if (pRemoteChar->canNotify()) {
        pRemoteChar->registerForNotify(batteryNotifyCallback);
      }
      
      // Copy initial value if readable
      if (pRemoteChar->canRead()) {
        try {
          std::string value = pRemoteChar->readValue();
          pServerChar->setValue(value);
        } catch (...) {
          Serial.printf("    Could not read initial value for %s\n", charUUID.c_str());
        }
      }
    }
    
    // Start the service
    pServerService->start();
  }
  
  servicesCloned = true;
  Serial.println("All services cloned successfully!");
}

void captureAndReplicateAdvertising() {
  Serial.println("Capturing advertising data from real battery...");
  
  // Disconnect from battery temporarily to scan its advertising
  if (pClient->isConnected()) {
    pClient->disconnect();
    delay(1000);
  }
  
  // Set up a scan to capture the real battery's advertising data
  BLEScan* pScan = BLEDevice::getScan();
  pScan->setActiveScan(true);
  pScan->setInterval(100);
  pScan->setWindow(99);
  
  class AdvertisingCaptureCallback : public BLEAdvertisedDeviceCallbacks {
    private:
      BLEScan* scanPtr;
      bool foundDevice = false;
      
    public:
      AdvertisingCaptureCallback(BLEScan* scan) : scanPtr(scan) {}
      
      void onResult(BLEAdvertisedDevice advertisedDevice) {
        if (foundDevice) return; // Only process once
        
        if (advertisedDevice.getAddress().toString() == BATTERY_MAC_ADDRESS) {
          foundDevice = true;
          Serial.println("Captured real battery advertising data:");
          Serial.printf("Name: %s\n", advertisedDevice.getName().c_str());
          Serial.printf("Address: %s\n", advertisedDevice.getAddress().toString().c_str());
          
          // Show raw advertising payload
          uint8_t* payload = advertisedDevice.getPayload();
          size_t payloadLength = advertisedDevice.getPayloadLength();
          Serial.printf("Raw advertising payload (%d bytes):\n", payloadLength);
          for (int i = 0; i < payloadLength; i++) {
            Serial.printf("%02X ", payload[i]);
            if ((i + 1) % 16 == 0) Serial.println();
          }
          if (payloadLength % 16 != 0) Serial.println();
          
          // Now replicate this exact advertising data
          BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
          pAdvertising->stop();
          
          // Use the high-level API instead of low-level ESP32 calls
          pAdvertising->addServiceUUID("0000ff00-0000-1000-8000-00805f9b34fb");
          
          BLEAdvertisementData advertisementData;
          advertisementData.setName(DEVICE_NAME);
          advertisementData.setCompleteServices(BLEUUID("0000ff00-0000-1000-8000-00805f9b34fb"));
          advertisementData.setFlags(0x06); // BR/EDR Not Supported + LE General Discoverable Mode
          
          pAdvertising->setAdvertisementData(advertisementData);
          pAdvertising->setScanResponse(true);
          pAdvertising->setMinPreferred(0x06);
          pAdvertising->setMaxPreferred(0x12);
          
          BLEDevice::startAdvertising();
          
          Serial.println("Replicated advertising data - device should now be discoverable!");
          scanPtr->stop();
        }
      }
  };
  
  pScan->setAdvertisedDeviceCallbacks(new AdvertisingCaptureCallback(pScan), true);
  Serial.println("Scanning for 10 seconds to capture battery advertising...");
  pScan->start(10, false);
  
  // Reconnect to battery
  delay(2000);
  if (pClient->connect(batteryAddress)) {
    Serial.println("Reconnected to real battery!");
    batteryConnected = true;
  }
}

void setup() {
  Serial.begin(115200);
  Serial.println("ESP32 BLE Transparent Proxy Starting...");
  
  // Initialize BLE
  BLEDevice::init(DEVICE_NAME);  // Appear as the battery to the phone
  
  // Create BLE Server (for phone to connect to)
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  
  // First connect to real battery as client
  Serial.println("Connecting to real battery...");
  pClient = BLEDevice::createClient();
  
  if (pClient->connect(batteryAddress)) {
    Serial.println("Connected to real battery!");
    batteryConnected = true;
    
    // Clone all services from battery
    cloneServicesFromBattery();
    
    // Capture and replicate exact advertising data
    captureAndReplicateAdvertising();
    
    Serial.println("ESP32 is now advertising as iTECH240X battery...");
    Serial.println("Connect your phone to this ESP32 instead of the real battery!");
    
  } else {
    Serial.println("Failed to connect to real battery!");
    Serial.println("Make sure the battery is on and in range.");
  }
}

void loop() {
  if (!deviceConnected && batteryConnected) {
    delay(500);
    BLEDevice::startAdvertising();
  }
  
  delay(1000);
}
