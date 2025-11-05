import asyncio
from bleak import BleakClient
from rich.live import Live
from rich.table import Table
from rich.panel import Panel
import json
import os
import time
from secrets import DEVICE_ADDRESS
HANDLE_UUIDS = {
    "notify": "0000ff01-0000-1000-8000-00805f9b34fb",  # Handle 16 (notify)
    "write": "0000ff02-0000-1000-8000-00805f9b34fb",   # Handle 20 (write)
}

POLL_CMD = "dda50300fffd77"
FINAL_BLOCK_CMD = "dda50400fffc77"


# Set this to any number of seconds to slow down polling, or 0 to disable delay
POLL_DELAY = 0.0

# Isolator control commands
ISOLATOR_COMMANDS = {
    "c": "dd5ae1020001ff1c77",  # Enable charge isolate
    "d": "dd5ae1020002ff1b77",  # Enable discharge isolate
    "o": "dd5ae1020000ff1d77",  # Disable both
    "b": "dd5ae1020003ff1a77",  # Enable both
}
CONFIRM_NOTIFICATION = "dde10000000077"
FINAL_NOTIFICATION = "dd010000000077"
SECOND_WRITE = "dd5a01020000fffd77"
ISOLATE_JSON_PATH = os.path.join(os.path.dirname(__file__), "isolate.json")

async def main():
    last_isolate_cmd = ""
    last_isolate_result = ""
    last_isolate_time = 0
    async with BleakClient(DEVICE_ADDRESS) as client:
        print("Connected to BLE device.")
        notify_uuid = HANDLE_UUIDS["notify"]
        write_uuid = HANDLE_UUIDS["write"]

        cycle_data = ["", "", "", ""]
        notif_counter = 0
        poll_count = 0
        latest_block4 = ""

        def notification_handler(sender, data):
            nonlocal cycle_data, notif_counter, latest_block4
            notif_counter += 1
            # Fill the first empty slot in cycle_data
            for idx in range(4):
                if not cycle_data[idx]:
                    cycle_data[idx] = data.hex()
                    if idx == 3:
                        latest_block4 = cycle_data[3]
                    break

        await client.start_notify(notify_uuid, notification_handler)


        async def check_isolate_json():
            nonlocal last_isolate_cmd, last_isolate_result, last_isolate_time
            try:
                with open(ISOLATE_JSON_PATH, "r") as f:
                    data = json.load(f)
                cmd = data.get("command", "").strip().lower()
            except Exception:
                cmd = ""
            if cmd and cmd != last_isolate_cmd and cmd in ISOLATOR_COMMANDS:
                notifications = []
                def handler(sender, data):
                    hexval = data.hex()
                    notifications.append(hexval)
                await client.stop_notify(notify_uuid)
                await client.start_notify(notify_uuid, handler)
                await client.write_gatt_char(write_uuid, bytes.fromhex(ISOLATOR_COMMANDS[cmd]), response=False)
                for _ in range(20):
                    await asyncio.sleep(0.1)
                    if CONFIRM_NOTIFICATION in notifications:
                        break
                await client.write_gatt_char(write_uuid, bytes.fromhex(SECOND_WRITE), response=False)
                for _ in range(20):
                    await asyncio.sleep(0.1)
                    if FINAL_NOTIFICATION in notifications:
                        last_isolate_result = f"{cmd} command successful"
                        last_isolate_time = time.time()
                        # Clear the command from isolate.json
                        try:
                            with open(ISOLATE_JSON_PATH, "w") as f:
                                json.dump({"command": ""}, f)
                        except Exception:
                            pass
                        break
                else:
                    last_isolate_result = f"{cmd} command failed"
                    last_isolate_time = time.time()
                await client.stop_notify(notify_uuid)
                await client.start_notify(notify_uuid, notification_handler)
                last_isolate_cmd = cmd

        try:
            prev_cycle_data = ["", "", "", ""]
            with Live(refresh_per_second=4) as live:
                while True:
                    # Check isolate.json for isolator command
                    await check_isolate_json()
                    poll_count += 1
                    cycle_data = ["", "", "", ""]
                    notif_counter = 0
                    # Poll for 03 blocks
                    await client.write_gatt_char(write_uuid, bytes.fromhex(POLL_CMD), response=False)
                    # Wait for up to 5 seconds for 3 notifications
                    for _ in range(50):
                        await asyncio.sleep(0.1)
                        if cycle_data[0] and cycle_data[1] and cycle_data[2]:
                            break
                    # If not all 3 blocks received, poll again
                    if not (cycle_data[0] and cycle_data[1] and cycle_data[2]):
                        continue
                    # Every 10 polls, update the final block
                    if poll_count % 10 == 0:
                        await client.write_gatt_char(write_uuid, bytes.fromhex(FINAL_BLOCK_CMD), response=False)
                        # Wait for up to 2 seconds for notification
                        for _ in range(20):
                            await asyncio.sleep(0.1)
                            if cycle_data[3]:
                                latest_block4 = cycle_data[3]
                                break
                    # Always show latest polled value for block 4
                    if not cycle_data[3]:
                        cycle_data[3] = latest_block4

                    def highlight_diff(curr, prev):
                        if not curr:
                            return ""
                        if not prev:
                            return curr
                        out = ""
                        for c, p in zip(curr, prev):
                            if c != p:
                                out += f"[red]{c}[/red]"
                            else:
                                out += c
                        if len(curr) > len(prev):
                            out += f"[red]{curr[len(prev):]}[/red]"
                        return out

                    table = Table(show_header=True, header_style="bold magenta")
                    table.add_column("Block", justify="center")
                    table.add_column("Data", justify="left")
                    table.add_column("Decoded", justify="left")
                    for idx, label in enumerate(["03 Block 1", "03 Block 2", "03 Block 3", "04 Block 1"]):
                        decoded = ""
                        data_field = highlight_diff(cycle_data[idx], prev_cycle_data[idx])
                        if idx == 0:
                            block1 = cycle_data[0] if cycle_data[0] else ""
                            decoded_parts = []
                            if len(block1) >= 16:
                                hex_6_7 = block1[12:16]
                                b_6_7 = bytes.fromhex(hex_6_7)
                                val_big = int.from_bytes(b_6_7, 'big', signed=True)
                                decoded_parts.append(f"{val_big/100:.2f}A")
                            if len(block1) >= 12:
                                hex_4_5 = block1[8:12]
                                b_4_5 = bytes.fromhex(hex_4_5)
                                val_v = int.from_bytes(b_4_5, 'big', signed=True)
                                decoded_parts.append(f"{val_v/100:.2f}V")
                            if len(block1) >= 20:
                                hex_8_9 = block1[16:20]
                                b_8_9 = bytes.fromhex(hex_8_9)
                                val_ah = int.from_bytes(b_8_9, 'big', signed=True)
                                decoded_parts.append(f"{val_ah/100:.2f}Ah")
                            decoded = ", ".join(decoded_parts)
                        elif idx == 1:
                            block2 = cycle_data[1] if cycle_data[1] else ""
                            decoded_parts = []
                            # Charge/Discharge isolator status from nibble 9
                            if len(block2) >= 10:
                                nib9 = block2[9]
                                if nib9 == "3":
                                    charge_status = "OFF"
                                    discharge_status = "OFF"
                                elif nib9 == "1":
                                    charge_status = "OFF"
                                    discharge_status = "ON"
                                elif nib9 == "2":
                                    charge_status = "ON"
                                    discharge_status = "OFF"
                                else:
                                    charge_status = discharge_status = f"Unknown ({nib9})"
                                decoded_parts.append(f"Charge isolator: {charge_status}")
                                decoded_parts.append(f"Discharge isolator: {discharge_status}")
                            else:
                                # Fallback to raw nibbles if not enough data
                                if len(block2) >= 1:
                                    decoded_parts.append(f"Charge isolator: {block2[0]}")
                                if len(block2) >= 10:
                                    decoded_parts.append(f"Discharge isolator: {block2[9]}")
                            decoded = ", ".join(decoded_parts)
                        elif idx == 3:
                            block4 = cycle_data[3] if cycle_data[3] else ""
                            decoded_parts = []
                            if len(block4) >= 12:
                                hex_4_5 = block4[8:12]
                                b_4_5 = bytes.fromhex(hex_4_5)
                                cell1 = int.from_bytes(b_4_5, 'big', signed=True)
                                decoded_parts.append(f"Cell1: {cell1/1000:.3f}V")
                            if len(block4) >= 16:
                                hex_6_7 = block4[12:16]
                                b_6_7 = bytes.fromhex(hex_6_7)
                                cell2 = int.from_bytes(b_6_7, 'big', signed=True)
                                decoded_parts.append(f"Cell2: {cell2/1000:.3f}V")
                            if len(block4) >= 20:
                                hex_8_9 = block4[16:20]
                                b_8_9 = bytes.fromhex(hex_8_9)
                                cell3 = int.from_bytes(b_8_9, 'big', signed=True)
                                decoded_parts.append(f"Cell3: {cell3/1000:.3f}V")
                            if len(block4) >= 24:
                                hex_10_11 = block4[20:24]
                                b_10_11 = bytes.fromhex(hex_10_11)
                                cell4 = int.from_bytes(b_10_11, 'big', signed=True)
                                decoded_parts.append(f"Cell4: {cell4/1000:.3f}V")
                            decoded = ", ".join(decoded_parts)
                        table.add_row(label, data_field, decoded)
                    from rich.layout import Layout
                    layout = Layout()
                    layout.split_column(
                        Layout(table, name="table")
                    )
                    # Show isolator command result if recent
                    panel_title = f"Poll {poll_count}"
                    if last_isolate_result and time.time() - last_isolate_time < 2:
                        panel_title += f" | [green]{last_isolate_result}[/green]"
                    live.update(Panel(layout, title=panel_title, expand=False))
                    prev_cycle_data = cycle_data.copy()
                    # Add poll delay for troubleshooting
                    if POLL_DELAY > 0:
                        await asyncio.sleep(POLL_DELAY)
        except (KeyboardInterrupt, asyncio.CancelledError):
            print("\nInterrupted by user. Exiting gracefully.")
        finally:
            await client.stop_notify(notify_uuid)
            print("Done. Disconnecting.")

if __name__ == "__main__":
    asyncio.run(main())
