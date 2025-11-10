import asyncio
from bleak import BleakScanner
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
import binascii
from rich.console import Console
from rich.table import Table
from rich.live import Live

from secrets import SHUNT_TARGET_MAC, SHUNT_BINDKEY
# Device-specific constants
TARGET_MAC = SHUNT_TARGET_MAC
BINDKEY = bytes.fromhex(SHUNT_BINDKEY)
console = Console()
last_data_counter = None
latest_fields = None
BINDKEY = bytes.fromhex("d34e4630af7248d953df4d0f5d26311e")

# Helper functions
def decrypt_payload(payload, counter_lsb, counter_msb):
    # Nonce: 2 bytes counter + 14 zero bytes (16 bytes total)
    nonce_counter = bytearray(16)
    nonce_counter[0] = counter_lsb
    nonce_counter[1] = counter_msb
    cipher = Cipher(
        algorithms.AES(BINDKEY),
        modes.CTR(bytes(nonce_counter)),
        backend=default_backend()
    )
    decryptor = cipher.decryptor()
    return decryptor.update(payload) + decryptor.finalize()

def parse_shunt_data(data):
    # SmartShunt/BMV bit-packed structure (16 bytes)
    import struct
    if len(data) < 15:
        print("Decrypted data too short!")
        return None
    # Pad to 16 bytes if needed
    if len(data) == 15:
        data = data + b'\x00'
    # Unpack header fields
    time_to_go = struct.unpack('<H', data[0:2])[0]
    battery_voltage_raw = struct.unpack('<h', data[2:4])[0]
    battery_voltage = battery_voltage_raw * 0.01
    alarm_reason = struct.unpack('<H', data[4:6])[0]
    aux_input_raw = struct.unpack('<H', data[6:8])[0]
    # Bit-packed fields
    remaining_bits = struct.unpack('<Q', data[8:16])[0]
    aux_input_type = remaining_bits & 0x3
    remaining_bits >>= 2
    battery_current_raw = remaining_bits & 0x3FFFFF
    if battery_current_raw & 0x200000:
        battery_current_raw |= 0xFFC00000
    battery_current_raw = struct.unpack('<i', struct.pack('<I', battery_current_raw & 0xFFFFFFFF))[0]
    battery_current = battery_current_raw * 0.001
    remaining_bits >>= 22
    consumed_ah_raw = remaining_bits & 0xFFFFF
    consumed_ah = -(consumed_ah_raw * 0.1)
    remaining_bits >>= 20
    state_of_charge_raw = remaining_bits & 0x3FF
    state_of_charge = state_of_charge_raw * 0.1
    # Aux voltage
    aux_voltage = 0.0 if aux_input_raw == 0xFFFF else aux_input_raw * 0.01
    return {
        "Time to Go (min)": time_to_go,
        "Battery Voltage (V)": battery_voltage,
        "Battery Current (A)": battery_current,
        "Consumed Ah": consumed_ah,
        "State of Charge (%)": state_of_charge,
        "Aux Voltage (V)": aux_voltage,
        "Alarm Reason": alarm_reason,
        "Aux Input Type": aux_input_type,
    }

# BLE advertisement callback
def adv_callback(device, adv_data):
    global last_data_counter, latest_fields
    if device.address.upper() != TARGET_MAC:
        return
    mfg_data = adv_data.manufacturer_data
    if not mfg_data:
        return
    payload = mfg_data.get(0x02E1)
    if not payload or len(payload) < 8:
        return
    # Extract header and encrypted payload
    counter_lsb = payload[5]
    counter_msb = payload[6]
    encryption_key_0 = payload[7]
    encrypted = payload[8:]
    # Check bindkey first byte matches
    if encryption_key_0 != BINDKEY[0]:
        console.print("[red]Bindkey mismatch![/red]")
        return
    data_counter = counter_lsb | (counter_msb << 8)
    if last_data_counter == data_counter:
        return  # Only update when data changes
    last_data_counter = data_counter
    try:
        decrypted = decrypt_payload(encrypted, counter_lsb, counter_msb)
        fields = parse_shunt_data(decrypted)
        if fields:
            latest_fields = fields
    except Exception as e:
        console.print(f"[red]Decryption/parsing error: {e}[/red]")

async def main():
    print(f"Scanning for SmartShunt ({TARGET_MAC})...")
    def detection_callback(device, adv_data):
        adv_callback(device, adv_data)

    scanner = BleakScanner(detection_callback)
    await scanner.start()
    try:
        with Live(refresh_per_second=4, console=console) as live:
            while True:
                await asyncio.sleep(0.5)
                if latest_fields:
                    table = Table(title=f"SmartShunt {TARGET_MAC}")
                    table.add_column("Field", style="cyan", no_wrap=True)
                    table.add_column("Value", style="magenta")
                    for k, v in latest_fields.items():
                        # Round floats and ints to 2 decimal places
                        if isinstance(v, float):
                            table.add_row(str(k), f"{v:.2f}")
                        elif isinstance(v, int) and k != "Alarm Reason" and k != "Aux Input Type":
                            table.add_row(str(k), f"{v:.2f}")
                        else:
                            table.add_row(str(k), str(v))
                    live.update(table)
    except KeyboardInterrupt:
        await scanner.stop()
        print("Scan stopped.")

if __name__ == "__main__":
    asyncio.run(main())
