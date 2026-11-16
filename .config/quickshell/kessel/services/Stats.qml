// SPDX-License-Identifier: GPL-3.0-or-later
// CPU / RAM / network throughput from /proc, sampled every 2 s.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property real cpu: 0          // 0..1
    property real mem: 0          // 0..1
    property real memUsedGiB: 0
    property real memTotalGiB: 0
    property real rxRate: 0       // bytes/s
    property real txRate: 0
    // temperature: hottest CPU-ish sensor (°C), -1 when the machine reports none (VMs)
    property real temp: -1
    property var tempHist: []
    // real filesystems (deduplicated by device): [{ mount, size, used, frac }]
    property var disks: []
    // CPU model, shortened like Gpu.shortName ("Ryzen 7 3800X", "Core i7-1165G7");
    // read once -- it doesn't change while running
    property string cpuName: "CPU"
    Process {
        running: true
        command: ["sh", "-c", "grep -m1 -E '^(model name|Model|Hardware)' /proc/cpuinfo | cut -d: -f2-"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = text.trim().replace(/\((TM|R)\)/gi, "").replace(/\s+@.*$/, "")
                    .replace(/\s+\d+-Core Processor|\s+(CPU|Processor)$|\s+with Radeon.*$/gi, "")
                    .replace(/^(AMD|Intel)\s+/, "").replace(/\s+/g, " ").trim()
                if (n) root.cpuName = n
            }
        }
    }

    Process {
        id: tempProc
        command: ["sh", "-c", 'for h in /sys/class/hwmon/hwmon*; do n=$(cat "$h/name" 2>/dev/null); case $n in coretemp|k10temp|zenpower|cpu_thermal|acpitz|thinkpad|soc_thermal) for t in "$h"/temp*_input; do [ -r "$t" ] && cat "$t"; done;; esac; done; for z in /sys/class/thermal/thermal_zone*; do case "$(cat "$z/type" 2>/dev/null)" in *x86_pkg*|*cpu*|*acpitz*|*soc*) cat "$z/temp" 2>/dev/null;; esac; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.split("\n").map(Number).filter(n => n > 1000 && n < 125000)
                root.temp = v.length ? Math.max(...v) / 1000 : -1
                if (root.temp >= 0) root.tempHist = root.push(root.tempHist, root.temp / 100)
            }
        }
    }
    Process {
        id: diskProc
        command: ["sh", "-c", "df -B1 --output=source,target,size,used -x tmpfs -x devtmpfs -x efivarfs -x overlay -x squashfs 2>/dev/null | tail -n +2"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, out = []
                for (const l of text.split("\n")) {
                    const f = l.trim().split(/\s+/)
                    if (f.length < 4 || seen[f[0]] || f[1].startsWith("/boot") || f[1] === "/efi") continue
                    seen[f[0]] = true
                    const size = +f[2], used = +f[3]
                    out.push({ mount: f[1], size: size, used: used, frac: size > 0 ? used / size : 0 })
                }
                root.disks = out
            }
        }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!tempProc.running) tempProc.running = true }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!diskProc.running) diskProc.running = true }
    function gib(b) { return (b / 1073741824).toFixed(b >= 1e11 ? 0 : 1) + "G" }

    // short histories (last 40 samples ≈ 80 s) for sparklines
    readonly property int histLen: 40
    property var cpuHist: []
    property var memHist: []
    property var rxHist: []
    property var txHist: []
    function push(arr, v) { const a = arr.slice(-(histLen - 1)); a.push(v); return a }

    property var _prevCpu: null
    property var _prevNet: null
    property real _prevT: 0

    // Short rate for the resting island: "999B", "9.9K", "42K", "1.2M", "120M", "1.1G".
    // Chips reserve the widest form ("999K") so the island doesn't jitter.
    function compact(bps) {
        const units = ["B", "K", "M", "G"]
        let v = Math.max(0, bps), i = 0
        while (v >= 999.5 && i < units.length - 1) { v /= 1024; i++ }
        const n = (i > 0 && v < 9.95) ? v.toFixed(1) : String(Math.round(v))
        return n + units[i]
    }
    // Percentage: "7%", "42%", "100%" (chips reserve "100%")
    function pct(f) { return String(Math.round(Math.max(0, Math.min(1, f)) * 100)) + "%" }

    function human(bps) {
        if (bps < 1024) return Math.round(bps) + " B/s"
        if (bps < 1048576) return (bps / 1024).toFixed(bps < 10240 ? 1 : 0) + " K/s"
        return (bps / 1048576).toFixed(1) + " M/s"
    }

    Process {
        id: proc
        command: ["cat", "/proc/stat", "/proc/meminfo", "/proc/net/dev"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: proc.running = true }

    function parse(t) {
        const lines = t.split("\n")
        const now = Date.now()
        let memTotal = 0, memAvail = 0, rx = 0, tx = 0
        for (const l of lines) {
            if (l.startsWith("cpu ")) {
                const v = l.trim().split(/\s+/).slice(1).map(Number)
                const idle = v[3] + v[4], total = v.reduce((a, b) => a + b, 0)
                if (_prevCpu) {
                    const dt = total - _prevCpu.total
                    cpu = dt > 0 ? Math.max(0, Math.min(1, 1 - (idle - _prevCpu.idle) / dt)) : 0
                }
                _prevCpu = { idle, total }
            } else if (l.startsWith("MemTotal:")) memTotal = parseInt(l.split(/\s+/)[1])
            else if (l.startsWith("MemAvailable:")) memAvail = parseInt(l.split(/\s+/)[1])
            else if (l.indexOf(":") > 0 && /^\s*[a-z0-9]+:\s+\d/.test(l)) {
                const [name, rest] = l.split(":")
                if (name.trim() === "lo") continue
                const f = rest.trim().split(/\s+/).map(Number)
                rx += f[0]; tx += f[8]
            }
        }
        if (memTotal > 0) {
            mem = 1 - memAvail / memTotal
            memTotalGiB = memTotal / 1048576
            memUsedGiB = (memTotal - memAvail) / 1048576
        }
        if (_prevNet && now > _prevT) {
            const s = (now - _prevT) / 1000
            rxRate = Math.max(0, (rx - _prevNet.rx) / s)
            txRate = Math.max(0, (tx - _prevNet.tx) / s)
        }
        _prevNet = { rx, tx }
        _prevT = now
        cpuHist = push(cpuHist, cpu)
        memHist = push(memHist, mem)
        rxHist = push(rxHist, rxRate)
        txHist = push(txHist, txRate)
    }
}
