# Dell Core i7-11390H / Intel Iris Xe Optimization Suite (Fedora Wayland)

Complete, one-command hardware, kernel, BIOS, power-longevity, hibernation, and Xbox Remote Play optimization repository for Dell Inspiron / Latitude (Intel Core i7-11390H + Intel Iris Xe Graphics + 16 GB RAM + NVMe Btrfs).

## Quick Restore After OS Reinstall

Clone this repository and run:

```bash
chmod +x install.sh
./install.sh
```

Then reboot once so the kernel boot parameters, initramfs (`dracut`), and Dell BIOS attributes take effect.

---

## Included Optimizations

### 1. Ultra-Low-Power Battery Efficiency (`configs/apply-battery-efficiency.sh`)
Reshapes the 35W H-series CPU into a cool, silent 12W U-series efficiency envelope (~8–10.5 hours active battery life):
- **CPU Turbo Boost Disabled (`no_turbo = 1`):** Caps CPU at its **2.9 GHz** base frequency across 8 threads, eliminating 1.35 V / 51 W voltage spikes.
- **CPU Energy Performance Preference (`EPP = power`):** Keeps cores at minimum voltage/frequency (400–1400 MHz) during light browsing.
- **Intel RAPL Package Power Caps:** `PL1 = 12 W` sustained, `PL2 = 15 W` short-term boost.
- **Intel Iris Xe 3D Clock Cap (`700 MHz`):** Halves GPU animation/scroll power spikes without affecting dedicated VA-API hardware video decoding.
- **Dell EC Platform Profile (`quiet`):** Uses Dell's passive/silent thermal table (0 RPM fan during normal use).
- **PCIe ASPM (`powersupersave`) & Kernel Power-Efficient Workqueues (`workqueue.power_efficient=1`):** Enables deep `L1.2` PCIe sleep and consolidates background kernel timers.

### 2. Automatic `suspend-then-hibernate` (0% Overnight Drain)
- Creates a dedicated 16 GB No-CoW Btrfs swapfile at `/var/swap/swapfile` (`pri=0`, keeping fast in-RAM `zram0` at `pri=100` for everyday use).
- Configures kernel `resume=UUID=...` and `resume_offset=...` + `dracut` `resume` module.
- **First 2 hours of lid close:** Stays in instant-wake `s2idle` Suspend (`<1s` wake).
- **After 2 hours on battery:** Automatically hibernates to NVMe and powers off completely (`0.0 W`).

### 3. Dell Battery Management & `BD_PROCHOT` Un-Throttler
- **`battery-mode` CLI (`battery-mode.py`):**
  - `battery-mode status` — View live battery health and thresholds
  - `battery-mode calibrate` — 100% full charge mode for new battery calibration
  - `battery-mode protect` — Locks charging between **60% and 80%** to maximize lithium-ion lifespan
  - `battery-mode adaptive` — Enables Dell Adaptive charging
- **`disable-bd-prochot.py` (`MSR 0x1FC`):** Automatically clears bit 0 of `MSR 0x1FC` at boot and on AC/battery plug events so third-party batteries never trigger Dell's 200 MHz CPU throttle.
- **Dell BIOS Settings (`dell-wmi-sysman`):** Keeps `Fastboot = Thorough` (so replacement battery microcontroller completes its SMBus handshake at POST), sets `WarningsAndErr = ContWrnErr` and `PowerWarn = Disabled`, and disables Dell telemetry, SupportAssist OS Recovery, BIOSConnect, and network boot stacks.

### 4. Xbox Remote Play Gaming Mode (`xbox-gaming-mode.py`)
- Disables Wi-Fi power-save while streaming for 0 ms jitter/ping, then restores it on exit.
- Enables Intel Iris Xe VA-API zero-copy hardware video decoding and 5.3 ms PipeWire audio latency.
- Smart AC/Battery detection: uses `performance` + `gamemoderun` when plugged into AC, and keeps the cool 12W efficiency profile when streaming on battery.

### 5. Kernel, GPU, Btrfs & Daemon Cleanup
- **Intel Iris Xe GuC (`v70.1.1`) & HuC (`v7.9.3`) Firmware Offload:** `i915.enable_guc=3`.
- **Network Stack (`configs/99-pc-optimization.conf`):** TCP `bbr` + `fq` qdisc + 16 MB UDP/TCP WebRTC buffers.
- **Btrfs Mount Tuning:** `noatime,commit=60` on `/` and `/home`.
- **Service Diet:** Masks background `gnome-software.service`, removes `ibus-typing-booster`, and disables 25+ unused enterprise/VM daemons (saving ~1.1 GiB of idle RAM).
