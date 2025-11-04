import asyncio
from bleak import BleakClient

DEVICE_ADDRESS = "a5:c2:37:18:35:67"
HANDLE_UUIDS = {
    "0x0010": "0000ff01-0000-1000-8000-00805f9b34fb",  # Handle 16 (notify)
    "0x0014": "0000ff02-0000-1000-8000-00805f9b34fb",  # Handle 20 (write)
}

# Alternating pattern from your analysis
PATTERN = [
    "dd:a5:03:00:ff:fd:77",
    "dd:a5:04:00:ff:fc:77"
]
NUM_ITERATIONS = 8  # Adjust for how many cycles you want to test

# Sequence from your example
SEQUENCE = [
    ("0x52", "0x0015", "dd:a5:03:00:ff:fd:77"),  # Write Command
    ("0x1b", "0x0011", "dd:03:00:22:05:31:00:00:61:af:69:78:00:00:30:b2:00:00:00:00"),  # Write Request
    ("0x1b", "0x0011", "00:00:67:5d:03:04:01:0b:53:00:00:00:69:78:61:af:00:00:f9:ba"),  # Write Request
    ("0x1b", "0x0011", "77"),  # Write Request
]

def hexstr_to_bytes(hexstr):
    return bytes.fromhex(hexstr.replace(":", ""))

async def main():
    async with BleakClient(DEVICE_ADDRESS) as client:
        print("Connected to BLE device.")

        notify_uuid = HANDLE_UUIDS["0x0010"]
        write_uuid = HANDLE_UUIDS["0x0014"]
        notifications = []

        def notification_handler(sender, data):
            print(f"Notification from {sender}: {data.hex()}")
            notifications.append((sender, data))

        await client.start_notify(notify_uuid, notification_handler)

        for i in range(10):
            payload = PATTERN[i % 2]
            print(f"Cycle {i+1}: Writing {payload} to {write_uuid}")
            await client.write_gatt_char(write_uuid, hexstr_to_bytes(payload), response=False)
            await asyncio.sleep(1)

        await client.stop_notify(notify_uuid)
        print("Done. Disconnecting.")

if __name__ == "__main__":
    asyncio.run(main())
