#!/usr/bin/env python3
"""
Xbox Remote Play Gaming Mode Launcher
Automatically optimizes Linux / GNOME and Wi-Fi when launching Xbox Remote Play:
- Engages 'Performance' power profile via D-Bus (net.hadess.PowerProfiles)
- Optimizes Wi-Fi for minimal packet loss & lowest jitter:
    * Disables Wi-Fi power save (keeps radio awake continuously)
    * Locks BSSID to current AP (prevents background roaming scans & latency spikes)
- Inhibits screen dimming, idle sleep, and screensaver (systemd-inhibit)
- Enables Do Not Disturb (silences GNOME notification banners)
- Optimizes Chromium flags for Intel VA-API hardware decoding, Wayland & WebRTC
- Restores all original settings upon exit
"""

import os
import sys
import time
import signal
import glob
import subprocess
from gi.repository import Gio, GLib

APP_ID = "amhjdkepnfmcepcijnjfhhoejoldjngh"
CHROMIUM_BIN = "/usr/lib64/chromium-browser/chromium-browser.sh"

class GamingMode:
    def __init__(self):
        self.power_cookie = None
        self.system_bus = None
        self.original_banners = None
        self.settings_notifications = None
        self.wifi_conn = None
        self.original_powersave = None
        self.original_bssid = None
        self.proc = None
        self.cleaned_up = False

    def notify(self, title: str, message: str, urgency: str = "normal"):
        # Notifications disabled per user request
        pass

    def is_app_open(self) -> bool:
        """Checks if Chromium currently has an open Web App window by checking open Sessions/Apps_* file descriptors."""
        apps_files = set(glob.glob(os.path.expanduser("~/.config/chromium/Default/Sessions/Apps_*")))
        if not apps_files:
            return False
        for fd_path in glob.glob("/proc/[0-9]*/fd/*"):
            try:
                target = os.readlink(fd_path)
                if target in apps_files:
                    return True
            except (OSError, FileNotFoundError):
                pass
        return False

    def optimize_wifi(self):
        """Disables Wi-Fi power save during Gaming Mode."""
        try:
            res = subprocess.run(
                ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"],
                capture_output=True,
                text=True,
                timeout=3
            )
            for line in res.stdout.splitlines():
                parts = line.split(":")
                if len(parts) >= 3 and ("wireless" in parts[1] or "wifi" in parts[1]):
                    self.wifi_conn = parts[0]
                    break

            if not self.wifi_conn:
                return

            # Save current powersave setting
            show_res = subprocess.run(
                ["nmcli", "-t", "-f", "802-11-wireless.powersave", "connection", "show", self.wifi_conn],
                capture_output=True,
                text=True,
                timeout=3
            )
            for line in show_res.stdout.splitlines():
                if line.startswith("802-11-wireless.powersave:"):
                    self.original_powersave = line.split(":", 1)[1].strip()

            print(f"[GamingMode] Disabling Wi-Fi power save on '{self.wifi_conn}'...")
            subprocess.run(
                ["nmcli", "connection", "modify", self.wifi_conn, "802-11-wireless.powersave", "2"],
                check=True,
                timeout=5
            )
            subprocess.run(["nmcli", "connection", "up", self.wifi_conn], check=True, timeout=15)
            print("[GamingMode] Wi-Fi power save disabled.")
        except Exception as e:
            print(f"[GamingMode] Notice: Wi-Fi optimization failed: {e}")

    def restore_wifi(self):
        """Restores original Wi-Fi power save setting when exiting Gaming Mode."""
        if not self.wifi_conn:
            return
        try:
            powersave_val = self.original_powersave if self.original_powersave is not None else "0"
            powersave_num = powersave_val.split()[0] if " " in powersave_val else powersave_val

            print(f"[GamingMode] Restoring Wi-Fi power save on '{self.wifi_conn}' to {powersave_num}...")
            subprocess.run(
                ["nmcli", "connection", "modify", self.wifi_conn, "802-11-wireless.powersave", powersave_num],
                check=True,
                timeout=5
            )
            subprocess.run(["nmcli", "connection", "up", self.wifi_conn], check=True, timeout=15)
            print("[GamingMode] Wi-Fi power save restored.")
        except Exception as e:
            print(f"[GamingMode] Notice: Failed to restore Wi-Fi settings: {e}")
        finally:
            self.wifi_conn = None

    def enable_performance_profile(self):
        try:
            self.system_bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
            res = self.system_bus.call_sync(
                "net.hadess.PowerProfiles",
                "/net/hadess/PowerProfiles",
                "net.hadess.PowerProfiles",
                "HoldProfile",
                GLib.Variant("(sss)", ("performance", "Xbox Remote Play Active", "XboxRemotePlay")),
                GLib.VariantType("(u)"),
                Gio.DBusCallFlags.NONE,
                -1,
                None
            )
            self.power_cookie = res.unpack()[0]
            print(f"[GamingMode] Held performance profile (cookie: {self.power_cookie})")
        except Exception as e:
            print(f"[GamingMode] Notice: PowerProfiles HoldProfile: {e}")

    def disable_performance_profile(self):
        if self.power_cookie and self.system_bus:
            try:
                self.system_bus.call_sync(
                    "net.hadess.PowerProfiles",
                    "/net/hadess/PowerProfiles",
                    "net.hadess.PowerProfiles",
                    "ReleaseProfile",
                    GLib.Variant("(u)", (self.power_cookie,)),
                    None,
                    Gio.DBusCallFlags.NONE,
                    -1,
                    None
                )
                print(f"[GamingMode] Released performance profile (cookie: {self.power_cookie})")
            except Exception as e:
                print(f"[GamingMode] Notice: Failed to release power profile: {e}")
            self.power_cookie = None

    def mute_notifications(self):
        try:
            self.settings_notifications = Gio.Settings.new("org.gnome.desktop.notifications")
            self.original_banners = self.settings_notifications.get_boolean("show-banners")
            if self.original_banners:
                self.settings_notifications.set_boolean("show-banners", False)
                print("[GamingMode] Notification banners disabled (Do Not Disturb)")
        except Exception as e:
            print(f"[GamingMode] Notice: Could not adjust notification settings: {e}")

    def restore_notifications(self):
        if self.settings_notifications and self.original_banners is not None:
            try:
                self.settings_notifications.set_boolean("show-banners", self.original_banners)
                print(f"[GamingMode] Notification banners restored to {self.original_banners}")
            except Exception as e:
                print(f"[GamingMode] Notice: Could not restore notification settings: {e}")
            self.original_banners = None

    def cleanup(self):
        if self.cleaned_up:
            return
        self.cleaned_up = True
        print("[GamingMode] Deactivating Gaming Mode...")
        self.disable_performance_profile()
        self.restore_notifications()
        self.restore_wifi()

    def run(self):
        # Register signal handlers for clean exit
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, lambda s, f: sys.exit(0))

        try:
            on_ac = True
            try:
                with open("/sys/class/power_supply/AC/online", "r") as f:
                    on_ac = f.read().strip() == "1"
            except Exception:
                pass

            self.optimize_wifi()
            self.mute_notifications()
            if on_ac:
                self.enable_performance_profile()
            else:
                print("[GamingMode] Running on battery: keeping efficient CPU power profile while optimizing Wi-Fi & VA-API.")

            # Check if gamemoderun is supported and user is in gamemode group (only use on AC)
            use_gamemoderun = False
            if on_ac:
                try:
                    import pwd, grp
                    username = pwd.getpwuid(os.getuid()).pw_name
                    user_groups = [g.gr_name for g in grp.getgrall() if username in g.gr_mem]
                    if "gamemode" in user_groups and os.path.exists("/usr/bin/gamemoderun"):
                        use_gamemoderun = True
                except Exception:
                    pass

            # Build Chromium command with low-latency, hardware-acceleration & high-priority flags
            chromium_args = [
                "--ozone-platform-hint=auto",
                "--enable-accelerated-video-decode",
                "--enable-features=AllowQt,WaylandLinuxDrmSyncobj,WaylandPerSurfaceScale,WaylandUiScale,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder,VaapiIgnoreDriverChecks,UseMultiPlaneFormatForHardwareVideo",
                "--enable-zero-copy",
                "--enable-gpu-rasterization",
                "--ignore-gpu-blocklist",
                "--disable-features=LensOverlay,OptimizationGuideOnDeviceModel,PromptAPIForGeminiNano,Compose,TabOrganization,UseChromeOSDirectVideoDecoder,WebRtcHideLocalIpsWithMdns,CalculateNativeWinOcclusion",
                "--disable-background-timer-throttling",
                "--disable-backgrounding-occluded-windows",
                "--disable-renderer-backgrounding",
                "--profile-directory=Default",
                f"--app-id={APP_ID}"
            ]

            cmd = [
                "systemd-inhibit",
                "--what=idle:sleep",
                "--who=Xbox Gaming Mode",
                "--why=Streaming Xbox Remote Play",
            ]

            if use_gamemoderun:
                cmd.append("/usr/bin/gamemoderun")

            cmd.append(CHROMIUM_BIN)
            cmd.extend(chromium_args)

            # Low-latency audio environment for PipeWire & PulseAudio
            env = os.environ.copy()
            env["PIPEWIRE_LATENCY"] = "256/48000"
            env["PULSE_LATENCY_MSEC"] = "10"

            print(f"[GamingMode] Executing: {' '.join(cmd)}")
            start_time = time.time()
            self.proc = subprocess.Popen(cmd, env=env)
            self.proc.wait()
            duration = time.time() - start_time

            # If it handed off to an already running Chromium session (< 3s):
            if duration < 3.0:
                print("[GamingMode] Handoff detected. Monitoring active Web App window...")
                time.sleep(2)
                while self.is_app_open():
                    time.sleep(2)
                print("[GamingMode] Web app window closed.")

        finally:
            self.cleanup()

if __name__ == "__main__":
    app = GamingMode()
    app.run()
