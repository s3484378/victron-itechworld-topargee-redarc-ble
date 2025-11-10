import asyncio
import sys
import threading
import queue
import msvcrt
from bleak import BleakClient

from secrets import DEVICE_ADDRESS
WRITE_UUID = "0000fff1-0000-1000-8000-00805f9b34fb"   # Handle: 0x0024
NOTIFY_UUID = "0000fff4-0000-1000-8000-00805f9b34fb"  # Handle: 0x002d

TANK_CAP_CMD = "5ac300ffffffffffffffffffffffffffffffff"
LITRES_USED_CMD = "5ac700ffffffffffffffffffffffffffffffff"

# Calculate XOR checksum for a command
def xor_checksum(data_bytes):
    result = 0
    for b in data_bytes:
        result ^= b
    return result

class BLEPoller:
    def __init__(self, client):
        self.client = client
        self.tank_capacity = None
        self.litres_used = None
        self.device_name = None
        self.polling = True
        self.poll_lock = asyncio.Lock()
        self.last_notification = None
        self.last_cmd = None
        self.notification_event = asyncio.Event()

    async def notification_handler(self, sender, data):
        self.last_notification = data
        self.notification_event.set()

    async def get_device_name(self):
        name_cmd = "5ac000ffffffffffffffffffffffffffffffff"
        name_bytes = bytes.fromhex(name_cmd)
        name_checksum = xor_checksum(name_bytes)
        name_full_cmd = name_bytes + bytes([name_checksum])
        self.last_cmd = "name"
        self.notification_event.clear()
        await self.client.write_gatt_char(WRITE_UUID, name_full_cmd)
        try:
            await asyncio.wait_for(self.notification_event.wait(), timeout=3)
            data = self.last_notification
            if data and len(data) >= 10:
                name_bytes = data[4:10]
                try:
                    name_str = name_bytes.decode('ascii').rstrip('\x00').rstrip('\xff')
                    if name_str:
                        self.device_name = name_str
                        return name_str
                except Exception:
                    pass
        except asyncio.TimeoutError:
            return None
        return None

    async def poll_once(self):
        async with self.poll_lock:
            # Query tank capacity
            tank_bytes = bytes.fromhex(TANK_CAP_CMD)
            tank_checksum = xor_checksum(tank_bytes)
            tank_full_cmd = tank_bytes + bytes([tank_checksum])
            self.last_cmd = "capacity"
            self.notification_event.clear()
            await self.client.write_gatt_char(WRITE_UUID, tank_full_cmd)
            try:
                await asyncio.wait_for(self.notification_event.wait(), timeout=3)
                data = self.last_notification
                if data and len(data) >= 8:
                    payload = data[4:-1]
                    if len(payload) >= 4:
                        self.tank_capacity = int.from_bytes(payload[2:4], 'big')
            except asyncio.TimeoutError:
                pass
            # Query litres used
            litres_bytes = bytes.fromhex(LITRES_USED_CMD)
            litres_checksum = xor_checksum(litres_bytes)
            litres_full_cmd = litres_bytes + bytes([litres_checksum])
            self.last_cmd = "used"
            self.notification_event.clear()
            await self.client.write_gatt_char(WRITE_UUID, litres_full_cmd)
            try:
                await asyncio.wait_for(self.notification_event.wait(), timeout=3)
                data = self.last_notification
                if data and len(data) >= 8:
                    payload = data[4:-1]
                    if len(payload) >= 4:
                        self.litres_used = int.from_bytes(payload[2:4], 'big')
            except asyncio.TimeoutError:
                pass

    def print_status(self):
        if self.tank_capacity is not None and self.litres_used is not None:
            current_usage = self.tank_capacity - self.litres_used
            percent = (current_usage / self.tank_capacity * 100) if self.tank_capacity else 0
            print(f"Current Usage: {current_usage}L | Remaining: {percent:.1f}%")
        else:
            print("Waiting for tank data...")

    async def polling_loop(self):
        while self.polling:
            if getattr(self, 'pause_polling', False):
                await asyncio.sleep(0.1)
                continue
            await self.poll_once()
            self.print_status()
            await asyncio.sleep(1)

    async def reset_tank(self, litres_used):
        async with self.poll_lock:
            used_bytes = litres_used.to_bytes(2, 'big')
            cmd_prefix = bytes.fromhex("5ac701040000")
            padding = bytes([0xff] * (20 - len(cmd_prefix) - len(used_bytes) - 1))
            cmd = cmd_prefix + used_bytes + padding
            checksum = xor_checksum(cmd)
            full_cmd = cmd + bytes([checksum])
            await self.client.write_gatt_char(WRITE_UUID, full_cmd)
            print(f"Sent reset command: {full_cmd.hex()}")
            await asyncio.sleep(1)

    async def set_tank_capacity(self, capacity):
        async with self.poll_lock:
            cap_bytes = capacity.to_bytes(2, 'big')
            cmd_prefix = bytes.fromhex("5ac301040000")
            padding = bytes([0xff] * (20 - len(cmd_prefix) - len(cap_bytes) - 1))
            cmd = cmd_prefix + cap_bytes + padding
            checksum = xor_checksum(cmd)
            full_cmd = cmd + bytes([checksum])
            await self.client.write_gatt_char(WRITE_UUID, full_cmd)
            print(f"Sent tank capacity set command: {full_cmd.hex()}")
            await asyncio.sleep(1)

async def user_input_loop(poller):
    input_queue = queue.Queue()

    def input_thread():
        try:
            while True:
                if msvcrt.kbhit():
                    key = msvcrt.getch()
                    if key in [b'1', b'2', b'3', b'4']:
                        input_queue.put((key.decode(),))
                    elif key == b'\x03':  # Ctrl+C
                        input_queue.put(("exit",))
        except Exception:
            input_queue.put(("exit",))

    print("\nOptions:")
    print("1. Reset tank meter to full (0 litres used)")
    print("2. Reset tank meter to custom value")
    print("3. Update tank capacity")
    print("4. Quit")
    print("Press 1, 2, 3, or 4 at any time to execute. Press Ctrl+C to exit.")

    t = threading.Thread(target=input_thread, daemon=True)
    t.start()

    while poller.polling:
        try:
            # Non-blocking check for user input
            if not input_queue.empty():
                choice = input_queue.get()
                poller.pause_polling = True
                if choice[0] == "1":
                    print("Entering: Reset tank meter to full (0 litres used)...")
                    await poller.reset_tank(0)
                    print("Tank meter reset to full. Resuming polling.")
                elif choice[0] == "2":
                    print("Entering: Reset tank meter to custom value...")
                    used_str = input("Enter litres used (integer): ").strip()
                    try:
                        used_val = int(used_str)
                        if not (0 <= used_val <= 65535):
                            raise ValueError
                    except ValueError:
                        print("Invalid litres used. Must be an integer between 0 and 65535.")
                        poller.pause_polling = False
                        continue
                    await poller.reset_tank(used_val)
                    print(f"Tank meter reset to {used_val} litres used. Resuming polling.")
                elif choice[0] == "3":
                    print("Entering: Update tank capacity...")
                    cap_str = input("Enter new tank capacity in litres (integer): ").strip()
                    try:
                        cap_val = int(cap_str)
                        if not (0 <= cap_val <= 65535):
                            raise ValueError
                    except ValueError:
                        print("Invalid tank capacity. Must be an integer between 0 and 65535.")
                        poller.pause_polling = False
                        continue
                    await poller.set_tank_capacity(cap_val)
                    print(f"Tank capacity updated to {cap_val}L. Resuming polling.")
                elif choice[0] == "4":
                    print("Exiting...")
                    poller.polling = False
                    break
                elif choice[0] == "exit":
                    poller.polling = False
                    break
                elif choice[0] == "invalid":
                    print("Invalid choice.")
                poller.pause_polling = False
            await asyncio.sleep(0.2)
        except KeyboardInterrupt:
            poller.polling = False
            break

async def main():
    async with BleakClient(DEVICE_ADDRESS, timeout=30.0) as client:
        poller = BLEPoller(client)
        await client.start_notify(NOTIFY_UUID, poller.notification_handler)
        print("Connected to BLE device.")
        print(f"Subscribed to notifications on {NOTIFY_UUID}")
        name = await poller.get_device_name()
        print(f"Device Name: {name if name else '[unknown]'}")
        print("\nThis script will continuously poll the tank capacity and litres used every 2 seconds.")
        print("It will print the current usage and remaining percentage.")
        print("At any time, you can enter an option to reset the tank meter or update the tank capacity. Polling will pause during updates.")
        print("Press Enter to continue polling, or enter an option number.")
        # Start polling loop in background
        polling_task = asyncio.create_task(poller.polling_loop())
        await user_input_loop(poller)
        await polling_task
        await client.stop_notify(NOTIFY_UUID)
        print("Unsubscribed from notifications.")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nExiting gracefully...")
