import asyncio
from bleak import BleakScanner
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
import binascii
from rich.console import Console
from rich.table import Table
from rich.live import Live

from secrets import SMARTSOLAR_TARGET_MAC, SMARTSOLAR_BINDKEY
# Device-specific constants
TARGET_MAC = SMARTSOLAR_TARGET_MAC  # Example SmartSolar MAC
BINDKEY = bytes.fromhex(SMARTSOLAR_BINDKEY)  # Example SmartSolar bindkey
console = Console()
last_data_counter = None
latest_fields = None

# Helper functions
def decrypt_payload(payload, counter_lsb, counter_msb):
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

def parse_smartsolar_data(data):
    import struct
    if len(data) < 12:
        print("Decrypted data too short!")
        return None
    # Pad to 16 bytes if needed
    if len(data) < 16:
        data = data + b'\x00' * (16 - len(data))
    # Unpack header fields
    # SmartSolar MPPT (Solar Charger) structure based on ESPHome
    # [State (1), Error (1), Batt V (2), Batt I (2), PV Power (2), Yield Today (2), Load I (2), Reserved (4)]
    state = data[0]
    error = data[1]
    batt_v = struct.unpack('<H', data[2:4])[0] * 0.01
    batt_i = struct.unpack('<h', data[4:6])[0] * 0.1
    yield_today = struct.unpack('<H', data[6:8])[0] * 0.01
    pv_power = struct.unpack('<H', data[8:10])[0]
    # For legacy reasons, keep load_i_raw from [10:12] (not used for display)
    load_i_raw_legacy = struct.unpack('<h', data[10:12])[0]
    # Load current: 9-bit signed value, bits 96-104 (payload[12:14])
    load_bits = data[12] | (data[13] << 8)
    load_i_raw = load_bits & 0x1FF  # 9 bits
    if load_i_raw & 0x100:
        load_i_raw -= 0x200
    load_i = load_i_raw * 0.1
    # Prepare raw bytes for each field
    raw_bytes = {
        "State": data[0:1],
        "Error": data[1:2],
        "Battery Voltage (V)": data[2:4],
        "Battery Current (A)": data[4:6],
        "Yield Today (kWh)": data[6:8],
        "PV Power (W)": data[8:10],
        "Load Current (A)": data[12:14],
    }
    return {
        "State": (state, raw_bytes["State"]),
        "Error": (error, raw_bytes["Error"]),
        "Battery Voltage (V)": (batt_v, raw_bytes["Battery Voltage (V)"]),
        "Battery Current (A)": (batt_i, raw_bytes["Battery Current (A)"]),
        "PV Power (W)": (pv_power, raw_bytes["PV Power (W)"]),
        "Yield Today (kWh)": (yield_today, raw_bytes["Yield Today (kWh)"]),
        "Load Current (A)": (load_i, raw_bytes["Load Current (A)"]),
        "__full_hex__": data
    }

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
    counter_lsb = payload[5]
    counter_msb = payload[6]
    encryption_key_0 = payload[7]
    encrypted = payload[8:]
    if encryption_key_0 != BINDKEY[0]:
        console.print("[red]Bindkey mismatch![/red]")
        return
    data_counter = counter_lsb | (counter_msb << 8)
    if last_data_counter == data_counter:
        return
    last_data_counter = data_counter
    try:
        decrypted = decrypt_payload(encrypted, counter_lsb, counter_msb)
        fields = parse_smartsolar_data(decrypted)
        if fields:
            latest_fields = fields
    except Exception as e:
        console.print(f"[red]Decryption/parsing error: {e}[/red]")

async def main():
    print(f"Scanning for SmartSolar ({TARGET_MAC})...")
    def detection_callback(device, adv_data):
        adv_callback(device, adv_data)

    scanner = BleakScanner(detection_callback)
    await scanner.start()
    try:
        with Live(refresh_per_second=4, console=console) as live:
            while True:
                await asyncio.sleep(0.5)
                if latest_fields:
                    table = Table(title=f"SmartSolar {TARGET_MAC}")
                    table.add_column("Field", style="cyan", no_wrap=True)
                    table.add_column("Value", style="magenta")
                    table.add_column("Raw Bytes", style="green")
                    # Print all except __full_hex__
                    for k, v in latest_fields.items():
                        if k == "__full_hex__":
                            continue
                        value, raw = v
                        if isinstance(value, float):
                            value_str = f"{value:.2f}"
                        elif isinstance(value, int):
                            value_str = f"{value:.2f}"
                        else:
                            value_str = str(value)
                        raw_str = binascii.hexlify(raw).decode().upper()
                        table.add_row(str(k), value_str, raw_str)
                    # Add full hex string at the bottom
                    full_hex = binascii.hexlify(latest_fields["__full_hex__"]).decode().upper()
                    table.add_row("Full Data Hex", "", full_hex)
                    live.update(table)
    except KeyboardInterrupt:
        await scanner.stop()
        print("Scan stopped.")

if __name__ == "__main__":
    asyncio.run(main())
