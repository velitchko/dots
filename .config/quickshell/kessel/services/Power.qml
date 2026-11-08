// SPDX-License-Identifier: GPL-3.0-or-later
// Battery (UPower) + power profiles (power-profiles-daemon). Hidden on desktops/VMs.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import ".."

Singleton {
    id: root
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: (battery?.isLaptopBattery ?? false) && (battery?.isPresent ?? false)
    readonly property real percent: hasBattery ? battery.percentage : 0     // 0..1
    readonly property bool charging: hasBattery && !UPower.onBattery
    readonly property string timeLeft: !hasBattery ? ""
        : charging ? (battery.timeToFull > 0 ? Time.hms(battery.timeToFull) + " to full" : "Charging")
        : (battery.timeToEmpty > 0 ? Time.hms(battery.timeToEmpty) + " left" : "")
    readonly property string icon: charging ? Icons.batCharging
        : percent > 0.9 ? Icons.bat100 : percent > 0.6 ? Icons.bat70 : percent > 0.3 ? Icons.bat40
        : percent > 0.1 ? Icons.bat20 : Icons.batAlert

    // power-profiles-daemon is optional (laptop profile). PowerProfiles.profile is
    // only meaningful when the daemon exists; we probe it with powerprofilesctl.
    property bool profilesAvailable: false
    readonly property int profile: PowerProfiles.profile
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    function setProfile(p) { PowerProfiles.profile = p }

    // Why the mode buttons are missing (laptops only): shown in their place.
    // Re-probed while missing, so enabling the service shows up without a restart.
    property string profilesReason: ""
    Timer { interval: 10000; repeat: true; running: root.hasBattery && !root.profilesAvailable; onTriggered: if (!probe.running) probe.running = true }
    Process {
        id: probe
        running: true
        command: ["sh", "-c", "command -v powerprofilesctl >/dev/null || { echo missing; exit 1; }; powerprofilesctl get >/dev/null 2>&1 || { echo stopped; exit 1; }"]
        stdout: StdioCollector {
            onStreamFinished: root.profilesReason = text.trim() === "missing" ? "Power modes: install.sh --with-laptop"
                : text.trim() === "stopped" ? "Power modes: sudo systemctl enable --now power-profiles-daemon" : ""
        }
        onExited: code => root.profilesAvailable = code === 0
    }
}
