#!/usr/bin/env python3
r"""USB-HID driver for iPhone acceptance runs on Windows.

The iOS 26 CoreDevice ``touch_session`` helper refuses to start unless the
device is unlocked and an app is in the foreground ("Remote control requires
iOS 27.0 or later").  Driving ``UniversalHIDServiceService`` directly works on
iOS 26 while the device is unlocked, so this tool talks to that service
straight and never opens a display session.

Known limit: while the phone is locked iOS silently drops HID touch reports.
Use ``wake`` to turn the display on, then unlock manually.

Examples::

    python phone_hid.py wake
    python phone_hid.py tap 603 2400
    python phone_hid.py swipe 603 2400 603 900 0.35
    python phone_hid.py text "hello"
    python phone_hid.py paste "altstore://install?url=http://10.0.0.2:8089/a.ipa"
    python phone_hid.py key enter
    python phone_hid.py shot C:\tmp\screen.png
"""

from __future__ import annotations

import argparse
import asyncio
import os
import subprocess
import sys

SITE_PACKAGES = os.environ.get(
    "PYMOBILEDEVICE3_SITE",
    r"C:\Users\hzwangxiuguo\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\site-packages",
)
if SITE_PACKAGES not in sys.path:
    sys.path.insert(0, SITE_PACKAGES)

from pymobiledevice3.remote import userspace_tunnel
from pymobiledevice3.remote.core_device.hid_service import (
    ASCII_TO_HID,
    HID_BUTTON_STATE_DOWN,
    HID_BUTTON_STATE_UP,
    IndigoHIDService,
    KEY_BACKSPACE,
    KEY_ENTER,
    KEY_LEFT_GUI,
    KEY_LEFT_SHIFT,
    TOUCHSCREEN_STATE_CONTACT,
    TOUCHSCREEN_STATE_RELEASE,
    TOUCHSCREEN_STATE_TOUCHING,
    UniversalHIDServiceService,
)

UDID = os.environ.get("WHALE_UDID", "00008140-001429613442801C")
WIDTH = 1206
HEIGHT = 2622
KEYBOARD_SERVICE_ID = 512

LOCK_USAGE_PAGE = 0x0C
LOCK_USAGE_CODE = 0x30


def touch_x(pixel: float) -> int:
    return round(pixel / WIDTH * 65535)


def touch_y(pixel: float) -> int:
    # dtuhidd reports use a bottom-left origin: y = 0 is the bottom edge.
    return round((HEIGHT - pixel) / HEIGHT * 65535)


async def press_lock(rsd) -> None:
    async with IndigoHIDService(rsd) as service:
        await service.send_button(LOCK_USAGE_PAGE, LOCK_USAGE_CODE, HID_BUTTON_STATE_DOWN)
        await asyncio.sleep(0.5)
        await service.send_button(LOCK_USAGE_PAGE, LOCK_USAGE_CODE, HID_BUTTON_STATE_UP)
    await asyncio.sleep(0.2)


async def tap(service, x: float, y: float, hold: float = 0.06) -> None:
    nx, ny = touch_x(x), touch_y(y)
    await service.send_touchscreen(TOUCHSCREEN_STATE_CONTACT, nx, ny)
    await asyncio.sleep(hold)
    await service.send_touchscreen(TOUCHSCREEN_STATE_RELEASE, nx, ny)


async def swipe(service, x1: float, y1: float, x2: float, y2: float, duration: float) -> None:
    steps = max(8, int(duration / 0.02))
    nx, ny = touch_x(x1), touch_y(y1)
    await service.send_touchscreen(TOUCHSCREEN_STATE_CONTACT, nx, ny)
    for index in range(1, steps + 1):
        ratio = index / steps
        nx = touch_x(x1 + (x2 - x1) * ratio)
        ny = touch_y(y1 + (y2 - y1) * ratio)
        await service.send_touchscreen(TOUCHSCREEN_STATE_TOUCHING, nx, ny)
        await asyncio.sleep(duration / steps)
    await service.send_touchscreen(TOUCHSCREEN_STATE_RELEASE, nx, ny)


async def type_text(service, text: str) -> None:
    for character in text:
        mapping = ASCII_TO_HID.get(character)
        if mapping is None:
            raise SystemExit(f"unsupported character for HID keyboard: {character!r}")
        usage, shifted = mapping
        keys = [KEY_LEFT_SHIFT, usage] if shifted else [usage]
        await service.send_keyboard(KEYBOARD_SERVICE_ID, keys)
        await asyncio.sleep(0.015)
        await service.send_keyboard(KEYBOARD_SERVICE_ID, [])
        await asyncio.sleep(0.015)


async def key_combo(service, name: str) -> None:
    combos = {
        "enter": [KEY_ENTER],
        "backspace": [KEY_BACKSPACE],
        "cmd-v": [KEY_LEFT_GUI, 0x19],
        "cmd-a": [KEY_LEFT_GUI, 0x04],
    }
    if name not in combos:
        raise SystemExit(f"unknown key: {name}")
    await service.send_keyboard(KEYBOARD_SERVICE_ID, combos[name])
    await asyncio.sleep(0.08)
    await service.send_keyboard(KEYBOARD_SERVICE_ID, [])


def copy_to_device(text: str) -> None:
    subprocess.run(
        [sys.executable, "-m", "pymobiledevice3", "developer", "core-device", "copy", text],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def screenshot(path: str) -> None:
    subprocess.run(
        [sys.executable, "-m", "pymobiledevice3", "developer", "core-device", "screen-capture", "screenshot", path],
        check=True,
        stdout=subprocess.DEVNULL,
    )


async def run(args) -> None:
    if args.command == "shot":
        screenshot(args.values[0])
        return

    rsd = await userspace_tunnel.establish_userspace_rsd(serial=UDID)
    try:
        if args.command == "wake":
            await press_lock(rsd)
            return
        if args.command == "lock":
            await press_lock(rsd)
            return

        async with UniversalHIDServiceService(rsd) as service:
            if args.command == "tap":
                await tap(service, float(args.values[0]), float(args.values[1]))
            elif args.command == "swipe":
                duration = float(args.values[4]) if len(args.values) > 4 else 0.35
                await swipe(
                    service,
                    float(args.values[0]),
                    float(args.values[1]),
                    float(args.values[2]),
                    float(args.values[3]),
                    duration,
                )
            elif args.command == "text":
                await type_text(service, " ".join(args.values))
            elif args.command == "key":
                await key_combo(service, args.values[0])
            elif args.command == "paste":
                copy_to_device(" ".join(args.values))
                await key_combo(service, "cmd-v")
    finally:
        await rsd.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["wake", "lock", "tap", "swipe", "text", "key", "paste", "shot"])
    parser.add_argument("values", nargs="*")
    args = parser.parse_args()
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
