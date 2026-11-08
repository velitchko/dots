// SPDX-License-Identifier: GPL-3.0-or-later
// Bluetooth via BlueZ (Quickshell.Bluetooth). Hidden when there is no adapter.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

Singleton {
    id: root
    // defaultAdapter can stay null although BlueZ lists a controller (seen on a
    // laptop where `bluetoothctl list` showed one): fall back to the first adapter.
    readonly property var adapter: Bluetooth.defaultAdapter ?? (Bluetooth.adapters.values.length > 0 ? Bluetooth.adapters.values[0] : null)
    readonly property bool available: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false
    // Named devices only: a scan also reports dozens of anonymous beacons.
    readonly property var devices: available
        ? adapter.devices.values.filter(d => d.paired || d.connected || (d.deviceName ?? "") !== "")
            .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || (a.name || "").localeCompare(b.name || ""))
        : []
    readonly property var connected: devices.filter(d => d.connected)
    readonly property var paired: devices.filter(d => d.paired)
    readonly property var nearby: devices.filter(d => !d.paired)

    // Why there's no adapter, for the quick-settings subtitle. Re-checked every
    // few seconds while missing, so enabling the service shows up without a restart.
    property string missingReason: "No adapter"
    property bool hwPresent: false
    function refresh() { if (!available && !probe.running) probe.running = true }
    Timer { interval: 5000; repeat: true; running: !root.available; onTriggered: root.refresh() }
    Process {
        id: probe
        running: !root.available
        command: ["sh", "-c", "command -v bluetoothctl >/dev/null || { echo nobluez; exit; }; systemctl is-active --quiet bluetooth || { echo stopped; exit; }; "
            + "if timeout 3 bluetoothctl list 2>/dev/null | grep -q '^Controller'; then echo hw; else echo nohw; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = text.trim()
                root.hwPresent = r === "hw"
                root.missingReason = r === "nobluez" ? "Not installed (install.sh --with-laptop)"
                    : r === "stopped" ? "Service off: sudo systemctl enable --now bluetooth"
                    : r === "hw" ? "Adapter found but not visible to the island: click to restart it"
                    : "No adapter (check rfkill / firmware)"
            }
        }
    }
    // The island lost track of BlueZ (e.g. started before bluetoothd): restart it.
    function restartIsland() { Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/island.sh", "restart"]) }

    function setEnabled(on) {
        if (!available) return
        // A soft rfkill block makes "Powered = true" fail silently.
        if (on) unblock.running = true
        else adapter.enabled = false
    }
    Process { id: unblock; command: ["sh", "-c", "rfkill unblock bluetooth 2>/dev/null; true"]; onExited: if (root.adapter) root.adapter.enabled = true }

    function scan(on) { if (available && adapter.enabled) adapter.discovering = on }

    // Click: connected → disconnect; paired → connect; new → pair.
    // Pairing goes through scripts/bt-pair.sh: BlueZ rejects a pairing nobody
    // answers, and Quickshell can't register the agent that would. The script
    // holds bluetoothctl's agent, then trusts and connects the device.
    property string pairingAddress: ""
    property string pairError: ""
    function toggleDevice(d) {
        if (d.connected) d.disconnect()
        else if (d.paired) d.connect()
        else pair(d)
    }
    function pair(d) {
        if (pairer.running) return
        pairError = ""
        pairingAddress = d.address
        pairer.command = [Quickshell.env("HOME") + "/.config/hypr/scripts/bt-pair.sh", d.address]
        pairer.running = true
    }
    Process {
        id: pairer
        stdout: StdioCollector {
            onStreamFinished: {
                const r = text.trim()
                if (r.startsWith("failed")) root.pairError = r.replace(/^failed:\s*/, "")
            }
        }
        onExited: { root.pairingAddress = ""; errorClear.restart() }
    }
    Timer { id: errorClear; interval: 10000; onTriggered: root.pairError = "" }
    function forget(d) { d.forget() }
}
