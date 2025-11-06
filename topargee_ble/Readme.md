## Decoded
### Litres Used (Tank Discharge)
Write: 5ac700ffffffffffffffffffffffffffffffff9d
Notifications:
	- 5ac7010400000009ffffffffffffffffffffff6e → 9 litres used
	- 5ac701040000000dffffffffffffffffffffff6a → 13 litres used
	- 5ac701040000000fffffffffffffffffffffff68 → 15 litres used
Breakdown:
	- Strip the header (first 4 bytes: 5a c7 01 04) and checksum (last byte), and remove all 0xff padding.
	- Litres used is bytes 2 and 3 after the header, interpreted as a big-endian 16-bit integer.
	- For example, bytes `00 09` = 9, `00 0d` = 13, `00 0f` = 15.
Decoded: Litres Used = 9L, 13L, 15L

### How Device Name is Determined
The device name is found in the notification data after sending the name request command. In the notification hex string, the name is encoded as ASCII characters following the initial 4 bytes (command header, typically starting with `5a`) and before the trailing checksum and any `ff` padding bytes. For example, in:

`5ac0010654726f6f7079ffffffffffffffffff4d`

The bytes `54726f6f7079` (after the header and before the checksum/`ff` padding) decode to the string "Troopy".

### Device Name
Write: 5ac000ffffffffffffffffffffffffffffffff9a
Notification: 5ac0010654726f6f7079ffffffffffffffffff4d
Decoded: Device Name = Troopy

### Tank Capacity
Write: 5ac300ffffffffffffffffffffffffffffffff99
Notification: 5ac301040000005fffffffffffffffffffffff3c
Breakdown:
	- Strip the header (first 4 bytes: 5a c3 01 04) and checksum (last byte: 3c), and remove all 0xff padding.
	- Tank capacity is bytes 2 and 3 after the header, interpreted as a big-endian 16-bit integer.
	- For example, bytes `00 5f` = 95, and bytes `01 04` = 260.
Decoded: Tank Capacity = 95L (for 005f), 260L (for 0104)
# Topargee BLE Device Reverse Engineering Notes
## Live Monitoring & Control Script

### File: topargee_monitor_and_control.py

This script provides live monitoring and interactive control of the Topargee BLE water tank device.

**Features:**
- Continuously polls and displays tank capacity and litres used every 2 seconds.
- Prints current usage and remaining percentage.
- Shows the device name at startup.
- Allows you to instantly:
  - Reset the tank meter to full (0 litres used)
  - Reset the tank meter to a custom value
  - Update the tank capacity
  - Quit the program
- Polling automatically pauses during configuration changes and resumes after.
- All actions are performed instantly by pressing 1, 2, 3, or 4 (no Enter required).
- Graceful exit with Ctrl+C.

**How to use:**
1. Ensure you have Python 3.8+ and the bleak library installed.
2. Run the script:
	```
	python topargee_monitor_and_control.py
	```
3. Watch live tank status updates in the terminal.
4. At any time, press:
	- `1` to reset tank meter to full
	- `2` to reset tank meter to a custom value (you will be prompted for litres used)
	- `3` to update tank capacity (you will be prompted for the new capacity)
	- `4` to quit
5. Press Ctrl+C to exit gracefully.

**Note:**
- This script is designed for Windows (uses msvcrt for instant keypress detection).
- For other platforms, adapt input handling as needed.
## Write Command Construction

### Reset Tank Meter (Set litres used)
- Command format: `5ac701040000<litres_used_be><padding><checksum>`
- `litres_used_be` is the litres used as a 16-bit big-endian integer (e.g., 0000 for full tank, 0005 for 5 litres used).
- Padding: Fill with 0xff to reach 19 bytes before checksum.
- Checksum: XOR of all preceding bytes.
- Example (reset to full):
	- Command: `5ac7010400000000ffffffffffffffffffffff`
	- Checksum: XOR of all bytes above (append as last byte)
- Example (reset to 5 litres used):
	- Command: `5ac7010400000005ffffffffffffffffffffff`
	- Checksum: XOR of all bytes above (append as last byte)

### Update Tank Capacity
- Command format: `5ac301040000<capacity_be><padding><checksum>`
- `capacity_be` is the tank capacity as a 16-bit big-endian integer (e.g., 006e for 110 litres).
- Padding: Fill with 0xff to reach 19 bytes before checksum.
- Checksum: XOR of all preceding bytes.
- Example (set to 110 litres):
	- Command: `5ac301040000006effffffffffffffffffffff`
	- Checksum: XOR of all bytes above (append as last byte)

### Query Tank Capacity
- Command: `5ac300ffffffffffffffffffffffffffffffff`
- Checksum: XOR of all bytes above (append as last byte)

All commands are written to handle 0x0024 (UUID: 0000fff1-0000-1000-8000-00805f9b34fb).

## Device Information
 - **Service UUID:** 0000fff0-0000-1000-8000-00805f9b34fb
 - **Write Characteristic UUID:** 0000fff1-0000-1000-8000-00805f9b34fb (Handle: 0x0024)
 - **Notify Characteristic UUID:** 0000fff4-0000-1000-8000-00805f9b34fb (Handle: 0x002d)
 - **Device Name (discovered):** Troopy

## Communication Protocol
- Data is sent to the device using GATT Write Requests to the write characteristic.
- Notifications are received from the notify characteristic after sending data.

## Message Format
- Messages are 20 bytes long, sent as hex strings.
- The last byte of each message is a checksum.
- The checksum matches the XOR of all preceding bytes in the message.

## Observations
- The first byte is always `5a` (likely a header or command marker).
- The second byte changes and may represent different commands or states.
- The third byte is usually `00`, except for credential/PIN messages.
- The middle section is mostly `ff` (padding or unused).
 - The message `5ac6010430303030...` contains ASCII `30303030` = "0000", likely a PIN code.
 - The message `5ac0010654726f6f7079...` contains ASCII `54726f6f7079` = "Troopy", which matches the device name.
 - The last byte is always the XOR checksum of the preceding bytes.

## Next Steps
- Further analyze the meaning of the command bytes and message structure.
- Investigate other message types and device features.
