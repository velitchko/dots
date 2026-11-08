// SPDX-License-Identifier: GPL-3.0-or-later
// Network state via NetworkManager (Quickshell.Networking). Works wired-only
// and with Wi-Fi. Password entry uses connectWithPsk.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking
import ".."

Singleton {
    id: root

    readonly property bool available: Networking.backend === NetworkBackendType.NetworkManager
    readonly property var devices: Networking.devices.values
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevice: devices.find(d => d.type === DeviceType.Wired) ?? null
    readonly property bool hasWifi: wifiDevice !== null
    readonly property bool wifiEnabled: Networking.wifiEnabled
    // rfkill / airplane switch: the software toggle can't override it
    readonly property bool wifiBlocked: !Networking.wifiHardwareEnabled
    readonly property bool wiredConnected: wiredDevice?.connected ?? false

    readonly property var networks: hasWifi
        ? wifiDevice.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))
        : []
    readonly property var activeWifi: networks.find(n => n.connected) ?? null

    readonly property bool online: wiredConnected || activeWifi !== null
    readonly property string label: activeWifi ? activeWifi.name
        : wiredConnected ? "Wired" : hasWifi && wifiEnabled ? "Not connected" : "Offline"
    readonly property string icon: activeWifi ? wifiIcon(activeWifi.signalStrength)
        : wiredConnected ? Icons.ethernet : hasWifi && wifiEnabled ? Icons.wifiOff : Icons.netOff

    function wifiIcon(s) {
        return s > 0.75 ? Icons.wifi4 : s > 0.5 ? Icons.wifi3 : s > 0.25 ? Icons.wifi2 : Icons.wifi1
    }
    function setWifi(on) { Networking.wifiEnabled = on }
    function scan(on) { if (hasWifi) wifiDevice.scannerEnabled = on }

    // Open / OWE networks connect without asking; saved ones reuse their secret.
    function isOpen(n) { return n.security === WifiSecurityType.Open || n.security === WifiSecurityType.Owe }
    // WPA-Enterprise (eduroam, …) needs a username/certificate: NetworkManager's editor.
    function isEnterprise(n) {
        return n.security === WifiSecurityType.Wpa2Eap || n.security === WifiSecurityType.WpaEap
            || n.security === WifiSecurityType.Wpa3SuiteB192 || n.security === WifiSecurityType.Leap
            || n.security === WifiSecurityType.DynamicWep
    }
    function needsPassword(n) { return !n.known && !isOpen(n) && !isEnterprise(n) }

    // Last failure, shown under the list; "wrong password" re-opens the prompt.
    property string error: ""
    property var errorNetwork: null
    signal passwordRejected(var network)
    Instantiator {
        model: root.hasWifi ? root.wifiDevice.networks : null
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectionFailed(reason) {
                const n = modelData
                root.errorNetwork = n
                if (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout) {
                    root.error = "Wrong password for " + n.name
                    root.passwordRejected(n)
                } else root.error = "Couldn't connect to " + n.name
                errorClear.restart()
            }
        }
    }
    Timer { id: errorClear; interval: 8000; onTriggered: { root.error = ""; root.errorNetwork = null } }

    function connect(n, psk) {
        error = ""
        if (psk !== undefined && psk !== "") n.connectWithPsk(psk)
        else n.connect()
    }
    function disconnect(n) { n.disconnect() }
    function forget(n) { n.forget() }
    // Hidden networks, enterprise logins, VPNs, static IPs
    function openEditor() { Quickshell.execDetached(["sh", "-c", "command -v nm-connection-editor >/dev/null && exec nm-connection-editor || exec kitty -e nmtui"]) }
}
