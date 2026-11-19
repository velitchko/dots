// SPDX-License-Identifier: GPL-3.0-or-later
// Backlight via brightnessctl, plus DDC/CI external monitors via ddcutil.
// Available when there is a /sys/class/backlight device (laptops) OR at least
// one DDC-capable monitor (desktops); hidden otherwise (VMs).
// Mirrors Audio.qml's shape: the OSD reacts to the actual sysfs value changing,
// not to who changed it -- so hardware brightness keys (which run brightnessctl
// directly, never through this file) show the OSD exactly like our own slider
// does, the same way wpctl from a hardware key shows the volume OSD.
//
// External monitors (DDC/CI via ddcutil; scripts/ddc-brightness.sh sets up the
// udev rule it needs) get the same percentage set() applies to the laptop
// panel -- one slider, every screen the same brightness, not independent
// per-monitor control. A monitor that doesn't actually support the
// brightness VCP code just no-ops (ddcutil's own failure, never surfaced
// here) rather than needing its own capability check.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root
    readonly property bool available: device !== "" || ddcBuses.length > 0
    property string device: ""
    property real value: 0      // 0..1
    property int _max: 1
    property var ddcBuses: []   // I2C bus numbers from the last `ddcutil detect`

    function set(v) {
        if (!available) return
        v = Math.max(0.01, Math.min(1, v))
        if (device !== "")
            Quickshell.execDetached(["brightnessctl", "-q", "-d", device, "set", Math.round(v * 100) + "%"])
        else
            applyRaw(v * root._max)   // no sysfs file to echo the change back on desktops
        root._ddcPending = Math.round(v * 100)
        if (!root._ddcBusy) root._ddcDispatch()
    }

    // DDC/CI writes measured at ~0.5-0.7s each on real hardware -- much longer than a
    // drag's event rate. Firing one write per event (or per fixed interval) overlaps
    // writes on the same I2C bus, which visibly desyncs/stalls the monitor mid-drag.
    // So: at most one write in flight; a new value just replaces _ddcPending, and
    // whichever write is already running picks up the latest value the moment it exits.
    property int _ddcPending: -1
    property bool _ddcBusy: false
    function _ddcDispatch() {
        if (root._ddcPending < 0 || root.ddcBuses.length === 0) return
        const pct = String(root._ddcPending)
        root._ddcPending = -1
        root._ddcBusy = true
        ddcWriter.command = ["sh", "-c", root.ddcBuses.map(b => "ddcutil --bus " + b + " setvcp 10 " + pct + " --noverify").join("; ")]
        ddcWriter.running = true
    }
    Process {
        id: ddcWriter
        onExited: {
            root._ddcBusy = false
            root._ddcDispatch()
        }
    }

    property bool armed: false
    Timer { interval: 1500; running: true; onTriggered: root.armed = true }

    function applyRaw(raw) {
        const v = Math.max(0, Math.min(1, raw / root._max))
        const changed = Math.abs(v - root.value) > 0.001
        root.value = v
        if (changed && root.armed) IslandState.showOsd(Icons.brightness, Math.round(v * 100) + "%", v)
    }

    FileView {
        id: brightnessFile
        path: root.device ? "/sys/class/backlight/" + root.device + "/brightness" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.applyRaw(parseInt(text()) || 0)
    }

    // brightnessctl -m → "device,class,current,percent,max"
    Process {
        id: probe
        running: true
        command: ["sh", "-c", "ls /sys/class/backlight/ 2>/dev/null | grep -q . && command -v brightnessctl >/dev/null && brightnessctl -m -c backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",")
                if (f.length >= 5) {
                    root._max = parseInt(f[4]) || 1
                    root.device = f[0]
                }
            }
        }
    }

    // Re-detect DDC-capable external monitors on startup and on hotplug
    // (Quickshell.screens changing). Debounced: a hotplug can fire this
    // more than once in quick succession while outputs settle.
    readonly property int screenCount: Quickshell.screens.length
    onScreenCountChanged: ddcDebounce.restart()
    Timer { id: ddcDebounce; interval: 1000; onTriggered: ddcProbe.running = true }
    Component.onCompleted: ddcDebounce.restart()

    Process {
        id: ddcProbe
        // "Display N" blocks are DDC-capable monitors; "Invalid display" blocks (e.g.
        // the laptop panel's own i2c bus) are skipped -- probing them wastes several
        // seconds per change on EREMOTEIO retries. Anchoring the second grep to the
        // line end also avoids matching the stray digit inside the literal "i2c".
        command: ["sh", "-c", "command -v ddcutil >/dev/null 2>&1 && ddcutil detect --brief 2>/dev/null | grep -A1 '^Display [0-9]\\+' | grep -oE 'i2c-[0-9]+' | grep -oE '[0-9]+$' || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.ddcBuses = text.trim().split("\n").filter(l => l !== "")
                // Desktop: no backlight file to read, so seed the slider from the first monitor.
                if (root.device === "" && root.ddcBuses.length > 0) {
                    ddcRead.command = ["ddcutil", "--bus", String(root.ddcBuses[0]), "getvcp", "10", "--brief"]
                    ddcRead.running = true
                }
            }
        }
    }

    // `getvcp 10 --brief` → "VCP 10 C <current> <max>"
    Process {
        id: ddcRead
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(/\s+/)
                if (f.length >= 5 && f[0] === "VCP") {
                    const cur = parseInt(f[3]), max = parseInt(f[4]) || 100
                    root.value = Math.max(0, Math.min(1, cur / max))
                }
            }
        }
    }
}
