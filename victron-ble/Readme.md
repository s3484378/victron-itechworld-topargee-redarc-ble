# Victron BLE Scripts

This folder contains Python scripts for scanning and decoding BLE advertisements from Victron devices (SmartShunt/BMV and SmartSolar MPPT). These scripts use the Bleak library for BLE scanning and cryptography for decrypting payloads.

## Overview
- `shunt_scanner.py`: Scans for SmartShunt/BMV BLE advertisements, decrypts and parses battery data.
- `smartsolar_scanner.py`: Scans for SmartSolar MPPT BLE advertisements, decrypts and parses solar charger data.
- `secrets.py`: Stores device MAC addresses and bind keys. You must create this file with your own device info (see below).

## Setup
1. Install dependencies:
   ```sh
   pip install -r requirements.txt
   ```
2. Create `secrets.py` in this folder:
   ```python
   SHUNT_TARGET_MAC = "your:shunt:mac:address"
   SHUNT_BINDKEY = "yourshuntbindkeyhex"
   SMARTSOLAR_TARGET_MAC = "your:solar:mac:address"
   SMARTSOLAR_BINDKEY = "yoursolarbindkeyhex"
   ```

## How the Scripts Work

### 1. BLE Scanning
- The scripts use Bleak to scan for BLE advertisements.
- Each device advertises manufacturer data containing encrypted payloads.
- The script filters advertisements by the target MAC address (from `secrets.py`).

### 2. Extracting and Decrypting Data
- The manufacturer data contains a payload:
  - Header bytes
  - Counter bytes (used as nonce for decryption)
  - Encrypted data
  - Bind key check byte
- The script checks the bind key byte matches your bind key.
- The counter bytes are used to build a 16-byte nonce for AES-CTR decryption.
- The encrypted payload is decrypted using the bind key and nonce.

### 3. Parsing the Decrypted Data
- The decrypted data is a packed binary structure:
  - For SmartShunt/BMV: fields include battery voltage, current, state of charge, consumed Ah, aux voltage, alarm reason, and more.
  - For SmartSolar: fields include battery voltage, current, PV power, yield today, load current, state, error, and more.
- The scripts unpack these fields using Python's `struct` module and bitwise operations.
- Parsed values are formatted and displayed in a live updating table using Rich.

### 4. Displaying Results
- The scripts use Rich to show a live table of decoded fields and values.
- For SmartSolar, raw bytes for each field and the full hex string are also shown for debugging.
- The table updates in real time as new BLE advertisements are received and decoded.

## Notes
- You must provide your own MAC addresses and bind keys in `secrets.py`.
- The scripts only process advertisements from the specified MAC addresses.
- If the bind key does not match, the script will warn and skip the packet.
- These scripts do not connect to the device; they only scan and decode advertisements.

## Example Output
```
+----------------------+---------+
| Field                | Value   |
+----------------------+---------+
| Battery Voltage (V)  | 13.25   |
| Battery Current (A)  | -2.10   |
| State of Charge (%)  | 98.5    |
| Consumed Ah          | -12.3   |
| Aux Voltage (V)      | 0.00    |
| ...                  | ...     |
+----------------------+---------+
```

## Troubleshooting
- If you see "Bindkey mismatch!", check your bind key in `secrets.py`.
- If you see "Decrypted data too short!", the advertisement may be malformed or the device is not supported.
- Make sure your Python environment has all required packages from `requirements.txt`.
