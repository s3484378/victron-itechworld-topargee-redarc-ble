# Itechworld BLE Reverse Engineering Guide

## Overview
This document details the current understanding of the BLE protocol for the Itechworld 240x battery, including how to connect, subscribe, send commands, and decode the notification data blocks. It is based on reverse engineering efforts using Python, Bleak, and live packet analysis. Other batteries may use the same protocol, but I haven't tested.

---

## BLE Connection Details
- **Device Address:** (example) `aa:bb:cc:dd:ee:ff`
- **Notify Handle/UUID:**
  - Handle: `0x0010`
  - UUID: `0000ff01-0000-1000-8000-00805f9b34fb`
- **Write Handle/UUID:**
  - Handle: `0x0014`
  - UUID: `0000ff02-0000-1000-8000-00805f9b34fb`

---

## How to Read Data
1. **Connect to the device** using its BLE address.
2. **Subscribe to notifications** on the Notify UUID (`0000ff01-...`).
3. **Send write commands** to the Write UUID (`0000ff02-...`) to trigger data updates:
   - `dda50300fffd77` (triggers 3 notifications)
   - `dda50400fffc77` (triggers 1 notification)
4. **Collect notifications**. Each notification is a data block (hex string).
5. **Repeat** as needed to get live updates.

---

## Data Block Structure
Each notification is a block of hex data. There are four main blocks per cycle:
- **dda50300fffd77 Block 1**
- **dda50300fffd77 Block 2**
- **dda50300fffd77 Block 3**
- **dda50400fffc77 Block 1**


### Decoded Fields
#### dda50300fffd77 Block 1
- **Bytes 4+5 (hex):** Voltage, signed int (big endian), divide by 100, unit: V
- **Bytes 6+7 (hex):** Current, signed int (big endian), divide by 100, unit: A
- **Bytes 8+9 (hex):** Remaining amp hours, signed int (big endian), divide by 100, unit: Ah

#### dda50300fffd77 Block 2
- **Nibble 9:** Isolator status
  - "3": Charge isolator OFF, Discharge isolator OFF
  - "1": Charge isolator OFF, Discharge isolator ON
  - "2": Charge isolator ON, Discharge isolator OFF
  - Other: Unknown (shows raw nibble)

#### dda50400fffc77 Block 1
- **Bytes 4+5 (hex):** Cell 1 voltage, signed int (big endian), divide by 1000, unit: V
- **Bytes 6+7 (hex):** Cell 2 voltage, signed int (big endian), divide by 1000, unit: V
- **Bytes 8+9 (hex):** Cell 3 voltage, signed int (big endian), divide by 1000, unit: V
- **Bytes 10+11 (hex):** Cell 4 voltage, signed int (big endian), divide by 1000, unit: V

### Example Decoding (dda50300fffd77 Block 1)
Suppose the block is:
```
... 0531 ... 61f0 ...
```
- Bytes 4+5: `0531` → 0x0531 → 1329 → 13.29 V
- Bytes 6+7: (see code)
- Bytes 8+9: `61f0` → 0x61f0 → 25072 → 250.72 Ah

---

## Live Analysis Features
- **Live Table:** Shows all blocks, highlights changing nibbles in red (per cycle) and green (across script restarts).
- **Analysis Panels:** Show all undecoded byte pairs in multiple formats (unsigned/signed, big/little endian), highlight values close to targets (e.g., 18.7, 187, 1870).
---

## How to Use the Python Script
1. Install requirements: `pip install -r requirements.txt`
2. Create your own `secrets.py` file in this folder with your device's BLE address:
  ```python
  # secrets.py
  DEVICE_ADDRESS = "your:device:mac:address"
  ```
  This file is ignored by git and must be created manually after cloning.
3. Run the script: `python ble_att_replicate.py`
4. Watch the terminal for live updates and analysis.
5. To detect changes after toggling settings in the app, stop the script, change the setting, and re-run the script. Changed bytes will be highlighted in green.

---

## Isolator Control: isolate.json

The script uses an `isolate.json` file to control the charge/discharge isolator relays on the device. To send a command:

1. Edit `isolate.json` and set the `command` field to one of the following values:
   - `c` — Enable charge isolate
   - `d` — Enable discharge isolate
   - `o` — Disable both
   - `b` — Enable both
2. The script will detect the change, send the corresponding BLE command, and clear the field after execution.
3. The result of the command is shown in the live panel for a short time.

Example `isolate.json`:
```json
{
  "command": "c"
}
```

This mechanism allows you to control the device relays from outside the script (e.g., another program or manual edit) without restarting the polling loop.

---

## Next Steps / Unknowns
- Some fields remain undecoded. The script helps you spot patterns and changes for further reverse engineering.
- Try toggling settings in the app and look for green highlights to identify which bytes are affected.
- If you discover new field meanings, update this document and the script accordingly.

---

## Credits
Reverse engineering and script by Ben & GitHub Copilot.
