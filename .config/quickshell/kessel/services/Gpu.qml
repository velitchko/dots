// SPDX-License-Identifier: GPL-3.0-or-later
// GPU load / VRAM / temperature for whatever GPUs this machine has, sampled
// every 2 s like Stats. Sources, by driver:
//   nvidia      nvidia-smi (ships with the driver)            load, VRAM, temp
//   amdgpu      sysfs gpu_busy_percent + mem_info + hwmon     load, VRAM, temp
//   i915 / xe   hwmon only (load needs root via perf)          temp, if exposed
// A runtime-suspended GPU (hybrid laptop dGPU) is reported as "off" and never
// queried: reading it would wake it and cost battery. No GPU, no data:
// `present` stays false and the UI hides its GPU bits.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // every detected GPU: [{ driver, name, busy (0..1 or -1), vramUsed, vramTotal (bytes), temp (°C or -1), on }]
    property var all: []
    // the one shown in the resting row: awake first, then one that reports
    // load, then the most VRAM (a discrete card over an APU)
    readonly property var primary: all.length ? all[0] : null
    readonly property bool present: primary !== null
    readonly property bool on: present && primary.on
    readonly property real busy: present ? primary.busy : -1
    readonly property real temp: present ? primary.temp : -1
    property var busyHist: []
    property string _primaryKey: ""

    function shortName(n) {
        return n.replace(/\(TM\)|\(R\)/g, "").replace(/^(NVIDIA|AMD|Intel)\s+/, "")
                .replace(/^(GeForce|Radeon)\s+/, "").replace(/\s+/g, " ").trim()
    }

    Process {
        id: proc
        // one line per GPU: driver|name|busy%|vramUsedBytes|vramTotalBytes|milli°C|on/off
        command: ["sh", "-c", `
for c in /sys/class/drm/card[0-9]*; do
  case "$c" in *-*) continue;; esac
  d="$c/device"; [ -e "$d/driver" ] || continue
  drv=$(basename "$(readlink "$d/driver")")
  case "$drv" in nvidia|amdgpu|i915|xe) ;; *) continue;; esac
  if [ "$(cat "$d/power/runtime_status" 2>/dev/null)" = suspended ]; then echo "$drv||||||off"; continue; fi
  t=$(cat "$d"/hwmon/hwmon*/temp*_input 2>/dev/null | sort -n | tail -1)
  case "$drv" in
    nvidia)
      command -v nvidia-smi >/dev/null || continue
      nvidia-smi --id="$(basename "$(readlink -f "$d")")" --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null |
        awk -F', ' '{ printf "nvidia|%s|%s|%.0f|%.0f|%.0f|on\\n", $1, $2, $3*1048576, $4*1048576, $5*1000 }' ;;
    amdgpu)
      n=$(cat "$d/product_name" 2>/dev/null); [ -n "$n" ] || n="AMD GPU"
      echo "amdgpu|$n|$(cat "$d/gpu_busy_percent" 2>/dev/null)|$(cat "$d/mem_info_vram_used" 2>/dev/null)|$(cat "$d/mem_info_vram_total" 2>/dev/null)|$t|on" ;;
    *)
      echo "$drv|Intel GPU||||$t|on" ;;
  esac
done`]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!proc.running) proc.running = true }

    function num(s) { const n = parseFloat(s); return isFinite(n) ? n : -1 }

    function parse(t) {
        const out = []
        for (const l of t.split("\n")) {
            const f = l.split("|")
            if (f.length < 7) continue
            const on = f[f.length - 1] === "on"
            const busy = num(f[2])
            const temp = num(f[f.length - 2])
            const g = {
                driver: f[0],
                name: on ? shortName(f[1]) : (f[0] === "nvidia" ? "NVIDIA" : f[0] === "amdgpu" ? "AMD" : "Intel") + " GPU",
                busy: busy >= 0 ? Math.min(1, busy / 100) : -1,
                vramUsed: Math.max(0, num(f[3])),
                vramTotal: Math.max(0, num(f[4])),
                temp: temp > 1000 && temp < 125000 ? temp / 1000 : -1,
                on: on
            }
            // an awake GPU we can't read anything from isn't worth a chip
            if (on && g.busy < 0 && g.temp < 0) continue
            out.push(g)
        }
        out.sort((a, b) => (b.on - a.on) || ((b.busy >= 0) - (a.busy >= 0)) || (b.vramTotal - a.vramTotal))
        all = out

        // restart the history when the shown GPU changes (a laptop dGPU waking up)
        const key = out.length ? out[0].driver + out[0].name : ""
        if (key !== _primaryKey) { _primaryKey = key; busyHist = [] }
        if (out.length && out[0].busy >= 0) busyHist = Stats.push(busyHist, out[0].busy)
    }
}
