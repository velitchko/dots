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
    // Time left. UPower's timeToEmpty/timeToFull come from the *instantaneous*
    // power draw, so they jump with every load spike (and were shown to the
    // second). We average the draw (exponential moving average over ~2-3 min),
    // restart when the charger is (un)plugged, wait for a few samples, and
    // round the result: "3 h 15 min".
    property real avgRate: 0        // W, smoothed
    property int samples: 0
    function sample() {
        if (!hasBattery) return
        const r = Math.abs(battery.changeRate ?? 0)
        if (r < 0.1) return                       // no reading yet / idle full battery
        avgRate = samples === 0 ? r : avgRate + 0.12 * (r - avgRate)
        samples++
    }
    onChargingChanged: { avgRate = 0; samples = 0; sample() }
    Connections { target: root.battery; ignoreUnknownSignals: true; function onChangeRateChanged() { root.sample() } }
    Timer { interval: 15000; repeat: true; running: root.hasBattery; onTriggered: root.sample() }
    readonly property bool settled: samples >= 4
    readonly property real secondsLeft: {
        if (!hasBattery || avgRate <= 0) return 0
        const e = battery.energy ?? 0, cap = battery.energyCapacity ?? 0
        const wh = charging ? Math.max(0, cap - e) : e
        return wh / avgRate * 3600
    }
    function duration(sec) {
        const min = Math.round(sec / 60)
        if (min < 2) return "a minute"
        if (min < 60) return min + " min"
        const r = Math.round(min / 5) * 5        // an estimate: 5-minute steps
        const h = Math.floor(r / 60), m = r % 60
        return m === 0 ? h + " h" : h + " h " + m + " min"
    }
    readonly property string timeLeft: !hasBattery ? ""
        : charging ? (percent >= 0.995 ? "Full" : !settled || secondsLeft <= 0 ? "Charging" : duration(secondsLeft) + " to full")
        : (!settled || secondsLeft <= 0 ? "Estimating…" : duration(secondsLeft) + " left")
    readonly property string icon: charging ? Icons.batCharging
        : percent > 0.9 ? Icons.bat100 : percent > 0.6 ? Icons.bat70 : percent > 0.3 ? Icons.bat40
        : percent > 0.1 ? Icons.bat20 : Icons.batAlert

    // power-profiles-daemon is optional (laptop profile). PowerProfiles.profile is
    // only meaningful when the daemon exists; we probe it over D-Bus.
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
        // Ask the daemon over D-Bus (what Quickshell itself uses). powerprofilesctl
        // was used before, but it is a Python script that needs python-gobject (only
        // an optional dependency), so it failed with the daemon running.
        command: ["sh", "-c", "busctl --system get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile >/dev/null 2>&1 && exit 0; "
            + "systemctl list-unit-files power-profiles-daemon.service tuned-ppd.service --no-legend 2>/dev/null | grep -q . && echo stopped || echo missing; exit 1"]
        stdout: StdioCollector {
            onStreamFinished: root.profilesReason = text.trim() === "missing" ? "Power modes: install.sh --with-laptop"
                : text.trim() === "stopped" ? "Power modes: sudo systemctl enable --now power-profiles-daemon" : ""
        }
        onExited: code => root.profilesAvailable = code === 0
    }
}
