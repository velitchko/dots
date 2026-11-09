// SPDX-License-Identifier: GPL-3.0-or-later
// Backlight via brightnessctl. Hidden when there is no /sys/class/backlight device (VMs, desktops).
// Mirrors Audio.qml's shape: the OSD reacts to the actual sysfs value changing,
// not to who changed it -- so hardware brightness keys (which run brightnessctl
// directly, never through this file) show the OSD exactly like our own slider
// does, the same way wpctl from a hardware key shows the volume OSD.
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

    function set(v) {
        if (!available) return
        v = Math.max(0.01, Math.min(1, v))
        Quickshell.execDetached(["brightnessctl", "-q", "-d", device, "set", Math.round(v * 100) + "%"])
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
}
