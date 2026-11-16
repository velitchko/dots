// SPDX-License-Identifier: GPL-3.0-or-later
// VPN status: Tailscale (mesh + exit-node mode), a non-Tailscale kernel
// WireGuard tunnel (e.g. a wg-quick ProtonVPN config), and OpenConnect.
// Tailscale mesh alone never sets fullTunnel -- it doesn't change the
// egress IP. `ip -o link show type wireguard` is used instead of `wg show`
// specifically because Tailscale's tailscale0 is a userspace TUN, not a
// kernel wireguard-type link, so it never shows up there.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool tailscaleAvailable: _tailscaleAvailable
    readonly property bool tailscaleUp: _tailscaleUp
    readonly property string tailscaleIp: _tailscaleIp
    readonly property bool exitNodeActive: _exitNodeActive
    readonly property bool wgAvailable: _wgAvailable
    readonly property string wgInterface: _wgInterface
    readonly property bool openconnectAvailable: _openconnectAvailable
    readonly property bool openconnectUp: _openconnectUp

    readonly property bool fullTunnel: exitNodeActive || wgInterface !== "" || openconnectUp
    readonly property bool anyBackendAvailable: tailscaleAvailable || wgAvailable || openconnectAvailable

    // identifies which backend is driving fullTunnel, so a switch between
    // backends (without an intervening "down") still re-triggers geolocation
    readonly property string backendKey: !fullTunnel ? ""
        : exitNodeActive ? "exit"
        : wgInterface !== "" ? "wg:" + wgInterface
        : "oc"
    onBackendKeyChanged: {
        if (backendKey === "") { geoIp = ""; geoLabel = ""; return }
        if (!geoProc.running) geoProc.running = true
    }
    property string geoIp: ""
    property string geoLabel: ""
    Process {
        id: geoProc
        command: ["sh", "-c", "curl -s --max-time 3 https://ipinfo.io/json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text)
                    root.geoIp = j.ip ?? ""
                    root.geoLabel = (j.city && j.country) ? `${j.city}, ${j.country}` : ""
                } catch (e) { root.geoIp = ""; root.geoLabel = "" }
            }
        }
    }

    property bool _tailscaleAvailable: false
    property bool _tailscaleUp: false
    property string _tailscaleIp: ""
    property bool _exitNodeActive: false
    property bool _wgAvailable: false
    property string _wgInterface: ""
    property bool _openconnectAvailable: false
    property bool _openconnectUp: false

    Process {
        id: proc
        command: ["sh", "-c", `
if command -v tailscale >/dev/null 2>&1; then
  echo "TSAVAIL=1"
  tailscale status --json 2>/dev/null
else
  echo "TSAVAIL=0"
fi
echo "==END_TS=="
if command -v ip >/dev/null 2>&1; then
  echo "WGAVAIL=1"
  ip -o link show type wireguard 2>/dev/null
else
  echo "WGAVAIL=0"
fi
echo "==END_WG=="
if command -v openconnect >/dev/null 2>&1; then
  echo "OCAVAIL=1"
else
  echo "OCAVAIL=0"
fi
pgrep -x openconnect >/dev/null 2>&1 && echo "OCUP=1" || echo "OCUP=0"
`]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!proc.running) proc.running = true }

    function parse(t) {
        const [tsBlock, afterTs] = t.split("==END_TS==\n")
        const [wgBlock, ocBlock] = afterTs.split("==END_WG==\n")

        const tsNl = tsBlock.indexOf("\n")
        const tsFirst = tsNl === -1 ? tsBlock : tsBlock.slice(0, tsNl)
        root._tailscaleAvailable = tsFirst === "TSAVAIL=1"
        let tsUp = false, tsIp = "", exitNode = false
        if (root._tailscaleAvailable) {
            try {
                const json = JSON.parse(tsBlock.slice(tsNl + 1))
                tsUp = json.BackendState === "Running"
                tsIp = (json.Self && json.Self.TailscaleIPs && json.Self.TailscaleIPs[0]) || ""
                // tailscale status --json keeps reporting the last-selected
                // ExitNodeStatus even once Tailscale is fully Stopped, so
                // this must also require the backend to actually be running.
                exitNode = tsUp && json.ExitNodeStatus !== undefined && json.ExitNodeStatus !== null
            } catch (e) { /* daemon down / bad JSON: keep defaults */ }
        }
        root._tailscaleUp = tsUp
        root._tailscaleIp = tsIp
        root._exitNodeActive = exitNode

        const wgLines = wgBlock.split("\n")
        root._wgAvailable = wgLines[0] === "WGAVAIL=1"
        let wgIface = ""
        for (const l of wgLines.slice(1)) {
            const m = l.match(/^\d+:\s+(\S+?)[@:]/)
            if (m) { wgIface = m[1]; break }
        }
        root._wgInterface = wgIface

        const ocLines = ocBlock.split("\n")
        root._openconnectAvailable = ocLines[0] === "OCAVAIL=1"
        root._openconnectUp = ocLines[1] === "OCUP=1"
    }
}
