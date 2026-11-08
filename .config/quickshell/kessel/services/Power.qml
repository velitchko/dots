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
    // Time left. UPower's timeToEmpty/timeToFull follow the *instantaneous*
    // power draw, so they jump with every load spike. We average the draw
    // (exponential moving average) and round the result ("3 h 15 min").
    // Until the average has 3 readings (~20-30 s) UPower's own estimate is shown,
    // so there's a number at once. Batteries that report no draw (changeRate 0)
    // get it from how fast the stored energy changes instead.
    property real avgRate: 0        // W, smoothed
    property int samples: 0
    property real lastEnergy: -1    // Wh, for batteries without changeRate
    property real lastEnergyAt: 0
    function sample() {
        if (!hasBattery) return
        let r = Math.abs(battery.changeRate ?? 0)
        const e = battery.energy ?? 0, now = Date.now()
        if (r < 0.1 && lastEnergy >= 0 && now - lastEnergyAt >= 60000 && Math.abs(e - lastEnergy) > 0.01)
            r = Math.abs(e - lastEnergy) / ((now - lastEnergyAt) / 3600000)
        if (lastEnergy < 0 || now - lastEnergyAt >= 60000) { lastEnergy = e; lastEnergyAt = now }
        if (r < 0.1) return                       // no reading yet / idle full battery
        avgRate = samples === 0 ? r : avgRate + 0.15 * (r - avgRate)
        samples++
    }
    onChargingChanged: { avgRate = 0; samples = 0; lastEnergy = -1; sample() }
    Connections { target: root.battery; ignoreUnknownSignals: true; function onChangeRateChanged() { root.sample() } }
    Timer { interval: 10000; repeat: true; running: root.hasBattery; triggeredOnStart: true; onTriggered: root.sample() }
    readonly property bool settled: samples >= 3
    readonly property real secondsLeft: {
        if (!hasBattery) return 0
        if (settled && avgRate > 0) {
            const e = battery.energy ?? 0, cap = battery.energyCapacity ?? 0
            return (charging ? Math.max(0, cap - e) : e) / avgRate * 3600
        }
        return charging ? (battery.timeToFull ?? 0) : (battery.timeToEmpty ?? 0)   // warm-up: UPower's
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
        : charging ? (percent >= 0.995 ? "Full" : secondsLeft > 0 ? duration(secondsLeft) + " to full" : "Charging")
        : (secondsLeft > 0 ? duration(secondsLeft) + " left" : "Estimating…")
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
