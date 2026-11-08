// SPDX-License-Identifier: GPL-3.0-or-later
// Live microphone level for the privacy pill's "you're talking" pulse.
// Runs cava on the default input only while an app is using the mic and it
// isn't muted. (Privacy ignores cava's own capture stream, so measuring
// doesn't count as "microphone in use".)
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property bool wanted: Privacy.mic && !Audio.micMuted && Audio.micReady && Cava.available
    readonly property string source: Audio.source?.name ?? ""
    property real level: 0               // 0..1, fast attack / slow release
    readonly property bool talking: level > 0.18

    readonly property string conf: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kessel-cava-mic.conf"

    // Fixed sensitivity (autosens would slowly turn room noise into "talking").
    Process {
        id: writer
        running: root.wanted && root.source !== ""
        command: ["sh", "-c", 'cat > "$1" <<EOF\n[general]\nbars = 4\nframerate = 25\nautosens = 0\nsensitivity = 160\nlower_cutoff_freq = 120\nhigher_cutoff_freq = 4000\n[input]\nmethod = pipewire\nsource = $2\n[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\nascii_max_range = 100\nbar_delimiter = 59\nframe_delimiter = 10\nchannels = mono\n[smoothing]\nnoise_reduction = 35\nEOF', "sh", root.conf, root.source]
    }
    Process {
        id: proc
        running: root.wanted && root.source !== "" && !writer.running
        command: ["cava", "-p", root.conf]
        stdout: SplitParser {
            onRead: line => {
                let peak = 0
                for (const v of line.split(";")) peak = Math.max(peak, (parseInt(v) || 0) / 100)
                // fast attack, slow release: syllables don't flicker the pulse
                root.level = peak > root.level ? peak : root.level * 0.85 + peak * 0.15
            }
        }
        onRunningChanged: if (!running) root.level = 0
    }
    // (switching the default mic mid-call takes effect the next time it starts)
}
