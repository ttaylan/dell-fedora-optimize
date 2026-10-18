#!/usr/bin/env python3
import os, struct, subprocess
subprocess.run(["modprobe", "msr"], check=False)
with open("/dev/cpu/0/msr", "rb") as f:
    f.seek(0x1FC)
    val = struct.unpack("<Q", f.read(8))[0]
if val & 1:
    new_val = val & ~1
    for cpu in range(16):
        p = f"/dev/cpu/{cpu}/msr"
        if os.path.exists(p):
            with open(p, "wb") as f:
                f.seek(0x1FC)
                f.write(struct.pack("<Q", new_val))
