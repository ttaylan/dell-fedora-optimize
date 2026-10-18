#!/usr/bin/env python3
"""
Dell Battery Health & Charge Threshold Manager
Allows switching between:
- 'calibrate' (100% full charge cycle for calibrating a newly installed battery)
- 'protect'   (60% start / 80% stop charge threshold for maximum battery lifespan)
- 'adaptive'  (Dell firmware adaptive charging mode)
- 'status'    (Displays current battery health, capacity, and thresholds)
"""

import os
import sys
import subprocess

BAT_PATH = "/sys/class/power_supply/BAT0"


def read_sysfs(name: str) -> str:
    path = os.path.join(BAT_PATH, name)
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except Exception:
        return "N/A"


def show_status():
    status = read_sysfs("status")
    capacity = read_sysfs("capacity")
    charge_types = read_sysfs("charge_types")
    start_thresh = read_sysfs("charge_control_start_threshold")
    end_thresh = read_sysfs("charge_control_end_threshold")

    try:
        full_now = int(read_sysfs("charge_full")) / 1_000_000
        full_design = int(read_sysfs("charge_full_design")) / 1_000_000
        health_pct = (full_now / full_design) * 100 if full_design > 0 else 0.0
        health_str = f"{health_pct:.1f}% ({full_now:.2f} Ah / {full_design:.2f} Ah design)"
    except Exception:
        health_str = "N/A"

    print("=== Dell Battery Status ===")
    print(f"  State:            {status} ({capacity}%)")
    print(f"  Battery Health:   {health_str}")
    print(f"  Charge Mode:      {charge_types}")
    print(f"  Start Threshold:  {start_thresh}%")
    print(f"  Stop Threshold:   {end_thresh}%")


def apply_mode(mode: str):
    if mode == "calibrate":
        # Note: Dell EC requires end_threshold >= start_threshold
        cmd = (
            f"echo 100 > {BAT_PATH}/charge_control_end_threshold && "
            f"echo 95 > {BAT_PATH}/charge_control_start_threshold && "
            f"echo Standard > {BAT_PATH}/charge_types"
        )
        desc = "Calibration Mode (Start: 95%, Stop: 100%, Mode: Standard)"
    elif mode == "protect":
        # Set start threshold first (60 <= current end_threshold), then end threshold (80)
        cmd = (
            f"echo Custom > {BAT_PATH}/charge_types && "
            f"echo 60 > {BAT_PATH}/charge_control_start_threshold && "
            f"echo 80 > {BAT_PATH}/charge_control_end_threshold"
        )
        desc = "Lifespan Protection Mode (Start: 60%, Stop: 80%, Mode: Custom)"
    elif mode == "adaptive":
        cmd = f"echo Adaptive > {BAT_PATH}/charge_types"
        desc = "Dell Adaptive Charging Mode"
    else:
        print("Usage: battery-mode [status | calibrate | protect | adaptive]")
        sys.exit(1)

    print(f"Applying {desc}...")
    subprocess.run(["pkexec", "bash", "-c", cmd], check=True)
    print("Done!\n")
    show_status()


def main():
    if len(sys.argv) < 2 or sys.argv[1].lower() == "status":
        show_status()
        print("\nCommands:")
        print("  battery-mode status     - View current battery health & thresholds")
        print("  battery-mode calibrate  - Charge to 100% (use for 1st cycle on new battery)")
        print("  battery-mode protect    - Lock charge between 60% and 80% (maximizes battery life)")
        print("  battery-mode adaptive   - Enable Dell firmware Adaptive charging")
    else:
        apply_mode(sys.argv[1].lower())


if __name__ == "__main__":
    main()
