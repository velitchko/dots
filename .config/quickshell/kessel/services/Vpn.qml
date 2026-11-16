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
        if (backendKey === "") { geoIp = ""; geoLabel = ""; geoRetryNeeded = false; return }
        startGeoLookup()
    }
    property string geoIp: ""
    property string geoLabel: ""
    // which backendKey the in-flight (or just-finished) lookup was for, so a
    // result that arrives after a backend switch is never shown under the
    // wrong name; geoRetryNeeded covers the switch-during-lookup case, where
    // the request for the new backend is deferred rather than dropped
    property string geoFor: ""
    property bool geoRetryNeeded: false
    function startGeoLookup() {
        if (geoProc.running) { geoRetryNeeded = true; return }
        geoFor = backendKey
        geoRetryNeeded = false
        geoProc.running = true
    }
    Process {
        id: geoProc
        command: ["sh", "-c", "curl -s --max-time 3 https://ipinfo.io/json"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.geoFor === root.backendKey) {
                    try {
                        const j = JSON.parse(text)
                        root.geoIp = j.ip ?? ""
                        root.geoLabel = (j.city && j.country) ? `${j.city}, ${j.country}` : ""
                    } catch (e) { root.geoIp = ""; root.geoLabel = "" }
                }
                if (root.geoRetryNeeded && root.backendKey !== "") root.startGeoLookup()
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
  timeout 3 tailscale status --json 2>/dev/null
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
pgrep -x openconnect >/dev/null 2>&1 && echo "OCPROC=1" || echo "OCPROC=0"
ip -o link show type tun 2>/dev/null | grep -v ' tailscale0:' | grep -q 'UP' && echo "OCTUN=1" || echo "OCTUN=0"
`]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!proc.running) proc.running = true }

    function parse(t) {
        const [tsBlock, afterTs] = t.split("==END_TS==\n")
        if (afterTs === undefined) return // truncated probe output: skip this tick, retry next
        const [wgBlock, ocBlock] = afterTs.split("==END_WG==\n")
        if (ocBlock === undefined) return

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
        // both the process and its tunnel interface must be up: pgrep alone
        // is true for the whole auth/handshake window before any tunnel
        // exists, which would light the icon and cache the real, non-VPN
        // egress IP under the OpenConnect label
        root._openconnectUp = ocLines[1] === "OCPROC=1" && ocLines[2] === "OCTUN=1"
    }
}
