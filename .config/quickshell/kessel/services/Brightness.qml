// SPDX-License-Identifier: GPL-3.0-or-later
// Backlight via brightnessctl. Hidden when there is no /sys/class/backlight device (VMs, desktops).
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
    property bool available: false
    property string device: ""
    property real value: 0      // 0..1
    property int _max: 1
    property var ddcBuses: []   // I2C bus numbers from the last `ddcutil detect`

    function set(v) {
        if (!available) return
        v = Math.max(0.01, Math.min(1, v))
        Quickshell.execDetached(["brightnessctl", "-q", "-d", device, "set", Math.round(v * 100) + "%"])
        const pct = String(Math.round(v * 100))
        for (const bus of root.ddcBuses)
            Quickshell.execDetached(["ddcutil", "--bus", String(bus), "setvcp", "10", pct, "--noverify"])
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
                    root.available = true
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
        command: ["sh", "-c", "command -v ddcutil >/dev/null 2>&1 && ddcutil detect --brief 2>/dev/null | grep -oE 'i2c-[0-9]+' | grep -oE '[0-9]+' || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.ddcBuses = text.trim().split("\n").filter(l => l !== "")
            }
        }
    }
}
