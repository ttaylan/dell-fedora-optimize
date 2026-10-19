#!/usr/bin/env bash
# Ultra-Low-Power Battery Efficiency Profile (i7-11390H + Iris Xe)

# 0. Ensure Dell BD_PROCHOT (MSR 0x1FC bit 0) 200MHz throttle is cleared on every boot/wake/plug
[ -x /usr/local/bin/disable-bd-prochot.py ] && /usr/local/bin/disable-bd-prochot.py 2>/dev/null || true

# 1. Disable CPU Turbo Boost (cap at 2.9 GHz base clock to avoid 1.35V spikes)
[ -e /sys/devices/system/cpu/intel_pstate/no_turbo ] && echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true
[ -e /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost ] && echo 0 > /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost 2>/dev/null || true

# 2. Set CPU Energy Performance Preference (EPP) to maximum power saving
for cpu in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
    [ -e "$cpu/scaling_governor" ] && echo powersave > "$cpu/scaling_governor" 2>/dev/null || true
    [ -e "$cpu/energy_performance_preference" ] && echo power > "$cpu/energy_performance_preference" 2>/dev/null || true
done

# 3. Cap Intel RAPL Package Power Limits to U-series 12W PL1 / 15W PL2 envelope
[ -e /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw ] && echo 12000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || true
[ -e /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw ] && echo 15000000 > /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw 2>/dev/null || true

# 4. Cap Intel Iris Xe 3D GPU Boost to 700 MHz (VA-API hardware video decode unaffected)
for card in /sys/class/drm/card[0-9]; do
    [ -e "$card/gt_boost_freq_mhz" ] && echo 700 > "$card/gt_boost_freq_mhz" 2>/dev/null || true
    [ -e "$card/gt_max_freq_mhz" ] && echo 700 > "$card/gt_max_freq_mhz" 2>/dev/null || true
done

# 5. Dell EC Platform Profile -> quiet (passive/silent thermal table)
[ -e /sys/firmware/acpi/platform_profile ] && echo quiet > /sys/firmware/acpi/platform_profile 2>/dev/null || true

# 6. PCIe ASPM powersupersave (workqueue.power_efficient=1 is set via kernel cmdline)
[ -e /sys/module/pcie_aspm/parameters/policy ] && echo powersupersave > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true

exit 0
