// SPDX-License-Identifier: GPL-3.0-or-later
// Kessel lock screen — a separate Quickshell config that runs only while the
// session is locked, then exits. Started by ~/.config/hypr/scripts/lock.sh,
// which falls back to hyprlock if this cannot lock securely.
//
// Preview without locking (for development):  KESSEL_LOCK_PREVIEW=1 qs -c kessel-lock
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell

    LockContext {
        id: ctx
        onUnlocked: action => {
            if (action === LockContext.Action.Poweroff) { Quickshell.execDetached(["systemctl", "poweroff"]); return }
            if (action === LockContext.Action.Reboot)   { Quickshell.execDetached(["systemctl", "reboot"]); return }
            if (ctx.keepAwake) Quickshell.execDetached(["qs", "-c", "kessel", "ipc", "call", "island", "stayAwake", "true"])
            ctx.exiting = true          // drop focus first (see LockContext.exiting)
            if (!shell.preview) lockLoader.item.locked = false
        }
        onExitingChanged: if (exiting) quitTimer.start()
    }

    // Preview is decided once, from the environment — never through a binding
    // that could briefly read wrong and engage a real lock.
    readonly property bool preview: Quickshell.env("KESSEL_LOCK_PREVIEW") === "1"

    // ── the real lock (not even created in preview) ──────────────────────────
    LazyLoader {
        id: lockLoader
        active: !shell.preview
        WlSessionLock {
            locked: true
            WlSessionLockSurface {
                id: lockSurf
                color: "black"
                LockSurface { anchors.fill: parent; context: ctx; screenName: lockSurf.screen?.name ?? "" }
            }
        }
    }
    // exit after focus has been dropped and the unlock has reached the compositor
    Timer { id: quitTimer; interval: 250; onTriggered: Qt.quit() }

    // lock.sh asks whether the compositor confirmed the lock
    IpcHandler {
        target: "lockstate"
        function secure(): string { return lockLoader.item && lockLoader.item.secure ? "yes" : "no" }
    }

    // ── preview (no session lock) ────────────────────────────────────────────
    Variants {
        model: shell.preview ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "black"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "kessel-lock-preview"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            LockSurface {
                anchors.fill: parent
                context: ctx
                screenName: modelData.name
                Keys.onEscapePressed: ctx.exiting = true
            }
        }
    }
}
