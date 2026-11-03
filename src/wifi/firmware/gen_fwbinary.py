#!/usr/bin/env python3
"""Replace the MT7922 firmware arrays in SimpleMtkWlan's include/FwBinary.cpp with given .bin files.

Usage: gen_fwbinary.py <FwBinary.cpp in> <FwBinary.cpp out> <WIFI_MT7922_patch_mcu_1_1_hdr.bin> <WIFI_RAM_CODE_MT7922_1.bin>

The MT7921 (mt7961) arrays and the fwList table are left as they are; only the bytes and *_len of
mwx_mt7922_patch_mcu_1_1_hdr and mwx_mt7922_ram_code_1 change.
"""
import re
import sys

src, dst, patch_bin, ram_bin = sys.argv[1:5]
text = open(src).read()


def array(name, data):
    rows = [", ".join(f"0x{b:02x}" for b in data[i:i + 12]) for i in range(0, len(data), 12)]
    body = ",\n  ".join(rows)
    return f"unsigned char {name}[] = {{\n  {body}\n}};\nunsigned int {name}_len = {len(data)};"


for name, path in (("mwx_mt7922_patch_mcu_1_1_hdr", patch_bin), ("mwx_mt7922_ram_code_1", ram_bin)):
    data = open(path, "rb").read()
    pattern = re.compile(r"unsigned char " + name + r"\[\] = \{.*?\};\nunsigned int " + name + r"_len = \d+;", re.S)
    text, n = pattern.subn(lambda _: array(name, data), text)
    assert n == 1, (name, n)
    print(f"{name}: {len(data)} bytes from {path}")

open(dst, "w").write(text)
