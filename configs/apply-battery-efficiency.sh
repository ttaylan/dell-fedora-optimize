#!/usr/bin/env bash
# Ultra-Low-Power Battery Efficiency Profile (i7-11390H + Iris Xe)

# 1. Disable CPU Turbo Boost (cap at 2.9 GHz base clock to avoid 1.35V spikes)
[ -w /sys/devices/system/cpu/intel_pstate/no_turbo ] && echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
[ -w /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost ] && echo 0 > /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost

# 2. Set CPU Energy Performance Preference (EPP) to maximum power saving
for cpu in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
    [ -w "$cpu/scaling_governor" ] && echo powersave > "$cpu/scaling_governor" 2>/dev/null
    [ -w "$cpu/energy_performance_preference" ] && echo power > "$cpu/energy_performance_preference" 2>/dev/null
done

# 3. Cap Intel RAPL Package Power Limits to U-series 12W PL1 / 15W PL2 envelope
[ -w /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw ] && echo 12000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null
[ -w /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw ] && echo 15000000 > /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw 2>/dev/null

# 4. Cap Intel Iris Xe 3D GPU Boost to 700 MHz (VA-API hardware video decode unaffected)
for card in /sys/class/drm/card[0-9]; do
    [ -w "$card/gt_boost_freq_mhz" ] && echo 700 > "$card/gt_boost_freq_mhz" 2>/dev/null
    [ -w "$card/gt_max_freq_mhz" ] && echo 700 > "$card/gt_max_freq_mhz" 2>/dev/null
done

# 5. Dell EC Platform Profile -> quiet (passive/silent thermal table)
[ -w /sys/firmware/acpi/platform_profile ] && echo quiet > /sys/firmware/acpi/platform_profile 2>/dev/null

# 6. Power-efficient kernel workqueues & PCIe ASPM powersupersave
[ -w /sys/module/workqueue/parameters/power_efficient ] && echo Y > /sys/module/workqueue/parameters/power_efficient 2>/dev/null
[ -w /sys/module/pcie_aspm/parameters/policy ] && echo powersupersave > /sys/module/pcie_aspm/parameters/policy 2>/dev/null

exit 0
