"""
Idiomatic ctypes wrapper for libzgbc.

Usage:

    from pathlib import Path
    from zgbc import GameBoy, Buttons

    gb = GameBoy()
    gb.load_rom(Path("roms/pokered.gb").read_bytes())
    gb.skip_boot()

    while True:
        gb.set_input(Buttons.A | Buttons.START)
        gb.frame()
        frame_rgba = gb.get_frame_rgba()
        audio = gb.get_audio_samples()
        # ... feed into your renderer/audio device ...
"""

from __future__ import annotations

import ctypes
import os
import sys
from pathlib import Path
from typing import Optional

__all__ = [
    "GameBoy",
    "Buttons",
    "FRAME_WIDTH",
    "FRAME_HEIGHT",
    "SAMPLE_RATE",
]

FRAME_WIDTH = 160
FRAME_HEIGHT = 144
SAMPLE_RATE = 44_100


class Buttons:
    A = 1 << 0
    B = 1 << 1
    SELECT = 1 << 2
    START = 1 << 3
    RIGHT = 1 << 4
    LEFT = 1 << 5
    UP = 1 << 6
    DOWN = 1 << 7


def _default_library_names() -> list[str]:
    if sys.platform.startswith("win"):
        return ["zgbc.dll"]
    if sys.platform == "darwin":
        return ["libzgbc.dylib", "zgbc.dylib"]
    return ["libzgbc.so"]


def load_library(path: Optional[os.PathLike[str] | str] = None) -> ctypes.CDLL:
    """
    Load libzgbc using ctypes.

    If *path* is None, tries LD_LIBRARY_PATH / PATH lookups with common names.
    """

    if path is not None:
        return ctypes.CDLL(os.fspath(path))

    env_path = os.environ.get("ZGBC_LIB")
    if env_path:
        return ctypes.CDLL(env_path)

    last_err: Optional[Exception] = None
    for name in _default_library_names():
        try:
            return ctypes.CDLL(name)
        except OSError as err:  # pragma: no cover - platform dependent
            last_err = err
    raise RuntimeError(
        "Unable to locate libzgbc; set ZGBC_LIB or pass path explicitly"
    ) from last_err


class GameBoy:
    """
    Thin OO wrapper around the C API.

    All heavy lifting stays in the native core; this class just helps loading ROMs,
    running frames, and fetching frame/audio buffers from Python.
    """

    def __init__(
        self,
        rom: Optional[bytes | os.PathLike[str] | str] = None,
        *,
        lib: Optional[ctypes.CDLL] = None,
    ) -> None:
        self._lib = lib or load_library()
        self._lib.zgbc_new.restype = ctypes.c_void_p
        self._lib.zgbc_free.argtypes = [ctypes.c_void_p]
        self._lib.zgbc_load_rom.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_uint8),
            ctypes.c_size_t,
        ]
        self._lib.zgbc_load_rom.restype = ctypes.c_bool
        self._lib.zgbc_frame.argtypes = [ctypes.c_void_p]
        self._lib.zgbc_set_input.argtypes = [ctypes.c_void_p, ctypes.c_uint8]
        self._lib.zgbc_set_render_graphics.argtypes = [ctypes.c_void_p, ctypes.c_bool]
        self._lib.zgbc_set_render_audio.argtypes = [ctypes.c_void_p, ctypes.c_bool]
        self._lib.zgbc_get_frame_rgba.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_uint32),
        ]
        self._lib.zgbc_get_audio_samples.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_int16),
            ctypes.c_size_t,
        ]
        self._lib.zgbc_get_audio_samples.restype = ctypes.c_size_t
        self._lib.zgbc_write.argtypes = [
            ctypes.c_void_p,
            ctypes.c_uint16,
            ctypes.c_uint8,
        ]

        self._handle = self._lib.zgbc_new()
        if not self._handle:
            raise RuntimeError("zgbc_new() returned NULL")

        if rom is not None:
            self.load_rom(rom)

    def __del__(self) -> None:
        handle, self._handle = getattr(self, "_handle", None), None
        if handle:
            try:
                self._lib.zgbc_free(handle)
            except Exception:  # pragma: no cover - best effort cleanup
                pass

    # ------------------------------------------------------------------ lifecycle
    def load_rom(self, rom: bytes | os.PathLike[str] | str) -> None:
        data = Path(rom).read_bytes() if isinstance(rom, (str, os.PathLike)) else rom
        buf = (ctypes.c_uint8 * len(data)).from_buffer_copy(data)
        if not self._lib.zgbc_load_rom(self._handle, buf, len(data)):
            raise RuntimeError("zgbc_load_rom() failed")

    def skip_boot(self) -> None:
        # Equivalent to toggling the boot ROM off
        self._lib.zgbc_write(self._handle, ctypes.c_uint16(0xFF50), ctypes.c_uint8(1))

    # ------------------------------------------------------------------ execution
    def frame(self) -> None:
        self._lib.zgbc_frame(self._handle)

    def set_input(self, buttons: int) -> None:
        self._lib.zgbc_set_input(self._handle, ctypes.c_uint8(buttons & 0xFF))

    def set_headless(self, graphics: bool, audio: bool) -> None:
        self._lib.zgbc_set_render_graphics(self._handle, graphics)
        self._lib.zgbc_set_render_audio(self._handle, audio)

    # ------------------------------------------------------------------ outputs
    def get_frame_rgba(self) -> memoryview:
        buf = (ctypes.c_uint32 * (FRAME_WIDTH * FRAME_HEIGHT))()
        self._lib.zgbc_get_frame_rgba(self._handle, buf)
        return memoryview(buf).cast("B")

    def get_audio_samples(self, max_samples: int = 2048) -> memoryview:
        buf = (ctypes.c_int16 * max_samples)()
        count = self._lib.zgbc_get_audio_samples(self._handle, buf, max_samples)
        return memoryview(buf)[: count * 2].cast("h")
