// SPDX-License-Identifier: GPL-3.0-or-later
// Light/dark + wallpaper, delegated to ~/.config/hypr/scripts/theme.sh.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/theme.sh"
    readonly property string wallDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string current: Theme.c.wallpaper ?? ""
    property var wallpapers: []
    // path → small cached JPEG. Wallpapers are often 4K–8K PNGs that take seconds
    // to decode; thumbnails are made once (ffmpeg) in ~/.cache/kessel/thumbs.
    property var thumbs: ({})
    function thumb(path) { return "file://" + (thumbs[path] ?? path) }
    property bool busy: false

    // The mode the user last asked for. Theme.dark only changes once theme.sh
    // has finished, so a toggle decided from it during a switch picked the old
    // direction again. UI shows and toggles from this instead.
    property string wantMode: ""
    readonly property bool dark: wantMode !== "" ? wantMode === "dark" : Theme.dark

    function toggleMode() { setMode(dark ? "light" : "dark") }
    function setMode(m) { wantMode = m; run(["mode", m]) }
    function setWallpaper(path) { run(["wallpaper", path]) }
    // A click while theme.sh runs used to be dropped (proc.running was already
    // true). Now requests queue, at most one per kind ("mode", "wallpaper"): a
    // newer one of the same kind replaces the waiting one. Commands are absolute
    // (no "toggle"), so collapsing is correct.
    property var pending: []
    function run(args) {
        if (proc.running) { pending = pending.filter(a => a[0] !== args[0]).concat([args]); return }
        busy = true
        proc.command = [script].concat(args)
        proc.running = true
    }
    Process {
        id: proc
        onExited: {
            root.busy = false
            if (root.pending.length) { const next = root.pending[0]; root.pending = root.pending.slice(1); root.run(next) }
            else root.wantMode = ""
        }
    }

    function refresh() { if (!lister.running) lister.running = true }
    Process {
        id: lister
        command: ["sh", "-c", 'mkdir -p "$1"; f() { find -L "$@" -maxdepth 2 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) ! -iname "*lock*" 2>/dev/null | sort; }; l="$(f "$1")"; [ -n "$l" ] && echo "$l" || f /usr/share/hypr', "sh", root.wallDir]
        stdout: StdioCollector { onStreamFinished: { root.wallpapers = text.split("\n").filter(l => l !== ""); thumber.running = true } }
    }
    Process {
        id: thumber
        // One line per wallpaper: "<path>\t<thumb>". The name hashes path + mtime,
        // so an edited image gets a fresh thumbnail.
        command: ["sh", "-c", 'd="${XDG_CACHE_HOME:-$HOME/.cache}/kessel/thumbs"; mkdir -p "$d"; for f in "$@"; do t="$d/$(printf "%s %s" "$f" "$(stat -c %Y "$f")" | md5sum | cut -c1-16).jpg"; [ -s "$t" ] || ffmpeg -nostdin -loglevel error -y -i "$f" -vf "scale=480:-2" -frames:v 1 -q:v 4 "$t" 2>/dev/null; [ -s "$t" ] && printf "%s\\t%s\\n" "$f" "$t"; done', "sh"].concat(root.wallpapers)
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {}
                for (const l of text.split("\n")) { const p = l.split("\t"); if (p.length === 2) m[p[0]] = p[1] }
                root.thumbs = m
            }
        }
    }
}
