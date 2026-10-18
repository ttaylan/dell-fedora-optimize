#!/usr/bin/env bash
# ==============================================================================
# Dell Core i7-11390H / Intel Iris Xe (Fedora Wayland) Complete Optimization Suite
# Run after a fresh Fedora install:
#   chmod +x install.sh && ./install.sh
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

echo "=== Installing User CLI Tools & GNOME Desktop Preferences ==="
mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/.local/share/applications"
chmod +x "$REPO_DIR/xbox-gaming-mode.py" "$REPO_DIR/battery-mode.py"
ln -sf "$REPO_DIR/xbox-gaming-mode.py" "$TARGET_HOME/.local/bin/xbox-gaming-mode"
ln -sf "$REPO_DIR/battery-mode.py" "$TARGET_HOME/.local/bin/battery-mode"
chown -h "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/bin/xbox-gaming-mode" "$TARGET_HOME/.local/bin/battery-mode"

# Apply GNOME dconf preferences (dark mode, touchpad, privacy, keybindings, ddcutil extension)
sudo -u "$TARGET_USER" dconf load / < "$REPO_DIR/configs/gnome-settings.dconf" 2>/dev/null || true

# Install Brightness Control using ddcutil GNOME Extension
sudo -u "$TARGET_USER" python3 -c '
import urllib.request, json, subprocess
try:
    url = "https://extensions.gnome.org/extension-info/?uuid=display-brightness-ddcutil@themightydeity.github.com&shell_version=50"
    data = json.loads(urllib.request.urlopen(url, timeout=10).read().decode())
    dl_url = "https://extensions.gnome.org" + data["download_url"]
    zip_path = "/tmp/display-brightness-ddcutil.zip"
    urllib.request.urlretrieve(dl_url, zip_path)
    subprocess.run(["gnome-extensions", "install", "--force", zip_path], check=False)
except Exception as e:
    print("Notice: Could not auto-download ddcutil GNOME extension:", e)
'

# Mask background GNOME Software daemon & disable Evolution alarm daemon for user
sudo -u "$TARGET_USER" systemctl --user mask gnome-software.service 2>/dev/null || true
mkdir -p "$TARGET_HOME/.config/autostart"
if [ -f /etc/xdg/autostart/org.gnome.Evolution-alarm-notify.desktop ]; then
    cp /etc/xdg/autostart/org.gnome.Evolution-alarm-notify.desktop "$TARGET_HOME/.config/autostart/"
    echo "Hidden=true" >> "$TARGET_HOME/.config/autostart/org.gnome.Evolution-alarm-notify.desktop"
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/autostart/org.gnome.Evolution-alarm-notify.desktop"
fi

echo "=== Applying Root System, DNF, Codecs, Kernel, BIOS, Power & Hibernation Optimizations ==="
pkexec bash -c "
set -euo pipefail

# 0. DNF Optimization, RPM Fusion, Hardware VA-API Codecs, ddcutil, Flathub & Bloat Removal
cp '$REPO_DIR/configs/dnf.conf' /etc/dnf/dnf.conf

FEDORA_VER=\$(rpm -E %fedora)
dnf install -y \
    \"https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-\${FEDORA_VER}.noarch.rpm\" \
    \"https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-\${FEDORA_VER}.noarch.rpm\" 2>/dev/null || true

dnf swap -y ffmpeg-free ffmpeg --allowerasing 2>/dev/null || true
dnf install -y intel-media-driver libva-utils gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly fuse-libs gnome-tweaks gamemode ddcutil 2>/dev/null || true
dnf remove -y ibus-typing-booster 'libreoffice*' unoconv 2>/dev/null || true

groupadd -f i2c
usermod -aG i2c '$TARGET_USER' 2>/dev/null || true
cp '$REPO_DIR/configs/60-ddcutil-i2c.rules' /etc/udev/rules.d/60-ddcutil-i2c.rules

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
flatpak remote-modify --no-filter --enable flathub 2>/dev/null || true

# 1. Kernel Sysctl, BBR Autoload, ZRAM & Journald Capping
mkdir -p /etc/modules-load.d /etc/systemd/journald.conf.d
cp '$REPO_DIR/configs/bbr.conf' /etc/modules-load.d/bbr.conf
modprobe tcp_bbr 2>/dev/null || true
cp '$REPO_DIR/configs/99-pc-optimization.conf' /etc/sysctl.d/99-pc-optimization.conf
cp '$REPO_DIR/configs/zram-generator.conf' /etc/systemd/zram-generator.conf
cp '$REPO_DIR/configs/00-journal-size.conf' /etc/systemd/journald.conf.d/00-journal-size.conf
sysctl --system >/dev/null

# 2. Intel Iris Xe GuC/HuC Firmware Offload, Audio Powersave & Watchdog Blacklist
cp '$REPO_DIR/configs/i915.conf' /etc/modprobe.d/i915.conf
cp '$REPO_DIR/configs/blacklist-watchdog.conf' /etc/modprobe.d/blacklist-watchdog.conf
cp '$REPO_DIR/configs/audio-powersave.conf' /etc/modprobe.d/audio-powersave.conf

# 3. Dell BD_PROCHOT 200MHz Throttle Disabler
cp '$REPO_DIR/configs/disable-bd-prochot.py' /usr/local/bin/disable-bd-prochot.py
chmod +x /usr/local/bin/disable-bd-prochot.py
cp '$REPO_DIR/configs/disable-bd-prochot.service' /etc/systemd/system/disable-bd-prochot.service
cp '$REPO_DIR/configs/99-disable-bd-prochot.rules' /etc/udev/rules.d/99-disable-bd-prochot.rules

# 4. Ultra-Low-Power Battery Efficiency Profile (2.9GHz Base, 12W/15W RAPL, 700MHz GPU, Quiet EC)
cp '$REPO_DIR/configs/ppd.conf' /etc/tuned/ppd.conf
cp '$REPO_DIR/configs/apply-battery-efficiency.sh' /usr/local/bin/apply-battery-efficiency.sh
chmod +x /usr/local/bin/apply-battery-efficiency.sh
cp '$REPO_DIR/configs/battery-efficiency.service' /etc/systemd/system/battery-efficiency.service
cp '$REPO_DIR/configs/80-laptop-powersave.rules' /etc/udev/rules.d/80-laptop-powersave.rules

# 5. Chromium Intel VA-API Hardware Acceleration & Gamemode Group
if [ -f /etc/chromium/chromium.conf ]; then
    sed -i 's/^#*GRAPHIC_DRIVER=.*/GRAPHIC_DRIVER=intel/' /etc/chromium/chromium.conf
fi
usermod -aG gamemode '$TARGET_USER' 2>/dev/null || true

# 6. Btrfs Mount Optimization (noatime,commit=60) & NVMe TRIM
sed -i -E 's/(subvol=(root|home),compress=zstd:1)( )/\1,noatime,commit=60 /g' /etc/fstab
systemctl enable --now fstrim.timer 2>/dev/null || true

# 7. Create 16GB Btrfs Swapfile & Configure suspend-then-hibernate (2h delay)
if [ ! -d /var/swap ]; then
    btrfs subvolume create /var/swap
fi
if [ ! -f /var/swap/swapfile ]; then
    btrfs filesystem mkswapfile --size 16g --uuid clear /var/swap/swapfile
fi
chmod 600 /var/swap/swapfile
chcon -t swapfile_t /var/swap/swapfile 2>/dev/null || true
if ! swapon --show | grep -q '/var/swap/swapfile'; then
    swapon -p 0 /var/swap/swapfile
fi
if ! grep -q '/var/swap/swapfile' /etc/fstab; then
    echo '/var/swap/swapfile none swap defaults,pri=0 0 0' >> /etc/fstab
fi

RESUME_OFFSET=\$(btrfs inspect-internal map-swapfile -r /var/swap/swapfile)
ROOT_DEV=\$(findmnt -no SOURCE / | sed 's/\[.*\]//')
ROOT_UUID=\$(blkid -s UUID -o value \"\$ROOT_DEV\")
MAJ_MIN=\$(lsblk -no MAJ:MIN \"\$ROOT_DEV\" | tr -d ' ')
echo \"\$RESUME_OFFSET\" > /sys/power/resume_offset
echo \"\$MAJ_MIN\" > /sys/power/resume

mkdir -p /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d /etc/dracut.conf.d
cp '$REPO_DIR/configs/99-suspend-then-hibernate-sleep.conf' /etc/systemd/sleep.conf.d/99-suspend-then-hibernate.conf
cp '$REPO_DIR/configs/99-suspend-then-hibernate-logind.conf' /etc/systemd/logind.conf.d/99-suspend-then-hibernate.conf
cp '$REPO_DIR/configs/99-resume.conf' /etc/dracut.conf.d/99-resume.conf
ln -sf /usr/lib/systemd/system/systemd-suspend-then-hibernate.service /etc/systemd/system/systemd-suspend.service

# 8. Kernel Boot Parameters & Initramfs Rebuild
grubby --update-kernel=ALL --args=\"i915.enable_guc=3 nowatchdog nmi_watchdog=0 8250.nr_uarts=0 pcie_aspm.policy=powersupersave workqueue.power_efficient=1 resume=UUID=\${ROOT_UUID} resume_offset=\${RESUME_OFFSET}\"
dracut -f

# 9. Dell BIOS Optimizations (Thorough Fastboot for Battery Auth + Telemetry/Recovery Off)
BIOS_DIR=/sys/class/firmware-attributes/dell-wmi-sysman/attributes
if [ -d \"\$BIOS_DIR\" ]; then
    declare -A BIOS_SETTINGS=(
        [Fastboot]=Thorough
        [WarningsAndErr]=ContWrnErr
        [PowerWarn]=Disabled
        [TelemetryAccessLvl]=Disabled
        [DcsdSwDvc]=Disabled
        [BIOSConnect]=Disabled
        [SupportAssistOSRecovery]=Disabled
        [AutoOSRecoveryThreshold]=OFF
        [HttpsBoot]=Disabled
        [UefiNwStack]=Disabled
        [DynTunML]=Enabled
        [SmartErrors]=Enabled
        [KbdBacklightTimeoutBatt]=15s
    )
    for k in \"\${!BIOS_SETTINGS[@]}\"; do
        if [ -w \"\$BIOS_DIR/\$k/current_value\" ]; then
            echo \"\${BIOS_SETTINGS[\$k]}\" > \"\$BIOS_DIR/\$k/current_value\" 2>/dev/null || true
        fi
    done
fi

# 10. Disable Boot-Blocking & Unused Background System Daemons
systemctl disable --now NetworkManager-wait-online.service rsyslog.service abrt-journal-core.service abrt-oops.service abrt-xorg.service abrtd.service switcheroo-control.service sssd.service sssd-kcm.socket pcscd.socket livesys.service livesys-late.service vboxservice.service vmtoolsd.service qemu-guest-agent.service iscsi.service iscsid.socket iscsiuio.socket mdmonitor.service lvm2-monitor.service ModemManager.service virtqemud.socket virtnetworkd.socket virtnodedevd.socket virtnwfilterd.socket virtsecretd.socket virtstoraged.socket 2>/dev/null || true

# 11. Enable & Start Optimization Services + 60%-80% Battery Protection
if [ -d /sys/class/power_supply/BAT0 ]; then
    echo Custom > /sys/class/power_supply/BAT0/charge_types 2>/dev/null || true
    echo 60 > /sys/class/power_supply/BAT0/charge_control_start_threshold 2>/dev/null || true
    echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null || true
fi
udevadm control --reload-rules
systemctl daemon-reload
systemctl enable --now disable-bd-prochot.service battery-efficiency.service
/usr/local/bin/disable-bd-prochot.py
/usr/local/bin/apply-battery-efficiency.sh
"

echo "=== All Optimizations Successfully Installed! ==="
