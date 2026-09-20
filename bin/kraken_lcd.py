#!/usr/bin/env python3
"""NZXT Kraken 2023 Elite (1e71:300c) LCD streamer.

Ports the CAM live-frame path from kraken-elite-screen-manager:
HID control (64-byte reports) + bulk OUT 0x02, asset mode 0x09 BGR888.
No bucket GIF. Firmware 2.x Elite only.
"""

from __future__ import annotations

import os
import select
import struct
import time

VID = 0x1E71
PID = 0x300C
WIDTH = 640
HEIGHT = 640
REPORT = 64
FRAME_BYTES = WIDTH * HEIGHT * 3
STREAM_URB = 245760
BULK_TIMEOUT_MS = 5000

BULK_MAGIC = bytes(
    [0x12, 0xFA, 0x01, 0xE8, 0xAB, 0xCD, 0xEF, 0x98, 0x76, 0x54, 0x32, 0x10]
)
STREAM_LUT1 = bytes([0x72, 0x01, 0x01, 0x00] + [0x3F] * 41)
STREAM_LUT2 = bytes([0x72, 0x02, 0x01, 0x01] + [0x1F] * 41)


class KrakenLcdError(RuntimeError):
    pass


def _pad(data: bytes) -> bytes:
    if len(data) >= REPORT:
        return data[:REPORT]
    return data + bytes(REPORT - len(data))


class KrakenLcd:
    def __init__(self):
        self._hid = None
        self._dev = None
        self._claimed = False
        self.orientation = 3  # device units 0-3; this pump is 270°
        self.brightness = 60

    def open(self) -> None:
        try:
            import usb.core
            import usb.util
        except ImportError as extra:
            raise KrakenLcdError(
                "need python hid + pyusb (%s)" % extra
            ) from extra

        found = usb.core.find(idVendor=VID, idProduct=PID)
        if found is None:
            raise KrakenLcdError("Kraken USB 1e71:300c not found")
        dev = found
        try:
            dev.get_active_configuration()
        except usb.core.USBError:
            dev.set_configuration()
        try:
            if dev.is_kernel_driver_active(0):
                dev.detach_kernel_driver(0)
        except (NotImplementedError, usb.core.USBError):
            pass
        usb.util.claim_interface(dev, 0)
        self._dev = dev
        self._claimed = True

    def _hidraw_path(self) -> str:
        import glob
        for uevent_path in glob.glob("/sys/class/hidraw/hidraw*/device/uevent"):
            text = open(uevent_path, encoding="utf-8", errors="ignore").read().upper()
            if "1E71" in text and "300C" in text:
                return "/dev/" + uevent_path.split("/")[4]
        raise KrakenLcdError("Kraken hidraw not found (usbhid unbound?)")

    def _hid_open(self) -> None:
        if self._hid is not None:
            return
        if self._dev is not None:
            try:
                if not self._dev.is_kernel_driver_active(1):
                    self._dev.attach_kernel_driver(1)
            except Exception:
                pass
        path = self._hidraw_path()
        self._hid = open(path, "rb+", buffering=0)

    def _hid_close(self) -> None:
        if self._hid is not None:
            try:
                self._hid.close()
            except Exception:
                pass
            self._hid = None
        if self._dev is not None:
            try:
                if not self._dev.is_kernel_driver_active(1):
                    self._dev.attach_kernel_driver(1)
            except Exception:
                pass

    def close(self) -> None:
        self._hid_close()
        if self._claimed and self._dev is not None:
            try:
                import usb.util
                usb.util.release_interface(self._dev, 0)
                usb.util.dispose_resources(self._dev)
            except Exception:
                pass
        self._claimed = False
        self._dev = None

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, *exc):
        self.close()
        return False

    def _write(self, data: bytes) -> None:
        if self._hid is None:
            raise KrakenLcdError("HID not open")
        n = self._hid.write(_pad(data))
        if n is not None and n < 0:
            raise KrakenLcdError("HID write failed")

    def _read(self, timeout_ms: int = 150) -> bytes | None:
        if self._hid is None:
            raise KrakenLcdError("HID not open")
        ready, _, _ = select.select([self._hid], [], [], timeout_ms / 1000.0)
        if not ready:
            return None
        raw = os.read(self._hid.fileno(), REPORT + 1)
        if not raw:
            return None
        data = bytes(raw)
        if len(data) == REPORT + 1:
            data = data[1:]
        if len(data) < REPORT:
            data = data + bytes(REPORT - len(data))
        return data[:REPORT]

    def _drain(self, timeout_ms: int = 2) -> None:
        for _ in range(8):
            if self._read(timeout_ms) is None:
                return

    def _write_then_read(self, data: bytes) -> bytes:
        self._write(data)
        return self._read(80) or bytes(REPORT)

    def read_lcd_info(self) -> tuple[int, int]:
        self._hid_open()
        try:
            self._drain()
            msg = self._write_then_read(bytes([0x30, 0x01]))
            self.brightness = msg[0x18]
            self.orientation = msg[0x1A]
            return self.brightness, self.orientation
        finally:
            self._hid_close()

    def set_brightness(self, percent: int, orientation: int | None = None) -> None:
        percent = max(0, min(100, int(percent)))
        if orientation is None:
            orientation = self.orientation
        self._hid_open()
        try:
            self._write(bytes([
                0x30, 0x02, 0x01, percent, 0x00, 0x00, 0x01, orientation & 0x03
            ]))
            self.brightness = percent
        finally:
            self._hid_close()

    def read_status(self) -> dict:
        msg = self._write_then_read(bytes([0x74, 0x01]))
        temp = msg[15] + msg[16] / 10.0
        pump = (msg[18] << 8) | msg[17]
        fan = (msg[24] << 8) | msg[23]
        return {
            "liquid": temp,
            "pump": pump,
            "fan": fan,
        }

    def enter_streaming(self, percent: int = 80) -> None:
        """LCD-only CAM handshake. No 0x70 — that re-inits the pump and
        clobbers CoolerControl's on-device fan/pump state."""
        percent = max(0, min(100, int(percent)))
        self._hid_open()
        try:
            self._drain()
            self._write_then_read(bytes([0x30, 0x01]))
            self._write_then_read(bytes([0x36, 0x03]))
            self._write_then_read(bytes([
                0x30, 0x02, 0x01, percent, 0x00, 0x00, 0x01,
                self.orientation & 0x03
            ]))
            self.brightness = percent
            self._drain()
        finally:
            self._hid_close()

    def _bulk_write(self, data: bytes, chunk: int) -> None:
        if self._dev is None:
            raise KrakenLcdError("bulk USB not open")
        offset = 0
        total = len(data)
        while offset < total:
            piece = data[offset:offset + chunk]
            written = self._dev.write(0x02, piece, timeout=BULK_TIMEOUT_MS)
            if written != len(piece):
                raise KrakenLcdError(
                    "bulk write short (%s/%s)" % (written, len(piece))
                )
            offset += written

    def push_frame_bgr(self, bgr888: bytes, with_status: bool = False) -> dict | None:
        if len(bgr888) != FRAME_BYTES:
            raise KrakenLcdError(
                "expected %s BGR888 bytes, got %s" % (FRAME_BYTES, len(bgr888))
            )
        self._hid_open()
        try:
            self._drain()
            self._write_then_read(STREAM_LUT1)
            self._write_then_read(STREAM_LUT2)
            self._write_then_read(bytes([0x36, 0x01, 0x00, 0x01, 0x09]))
            header = BULK_MAGIC + bytes([0x09, 0x00, 0x00, 0x00]) + struct.pack(
                "<I", len(bgr888)
            )
            self._bulk_write(header, len(header))
            self._bulk_write(bgr888, STREAM_URB)
            self._write_then_read(bytes([0x36, 0x02]))
            if not with_status:
                return None
            return self.read_status()
        finally:
            self._hid_close()
            time.sleep(0.15)
