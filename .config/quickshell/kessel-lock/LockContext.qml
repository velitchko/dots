// SPDX-License-Identifier: GPL-3.0-or-later
// Authentication state shared by every monitor's lock surface.
// Passwords are checked by PAM (service "hyprlock" → includes "login"), exactly
// like hyprlock; nothing is stored or logged. A fingerprint (fprintd) can unlock
// too, in parallel with the password field.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

Scope {
    id: root

    enum Action { Unlock, Poweroff, Reboot }

    readonly property bool preview: Quickshell.env("KESSEL_LOCK_PREVIEW") === "1"
    property string currentText: ""
    property bool unlockInProgress: false
    property bool failed: false
    property int targetAction: LockContext.Action.Unlock
    property bool keepAwake: false          // CTRL+Enter: unlock and keep the session awake
    // Set just before exiting: text fields give up focus first, because Qt 6.12
    // crashes tearing down a focused text input — and a crashed locker gets
    // restarted by Quickshell, which would lock the session again.
    property bool exiting: false

    signal unlocked(int action)
    signal shouldReFocus()

    function resetTargetAction() { targetAction = LockContext.Action.Unlock }
    function resetClearTimer() { clearTimer.restart() }

    // Typed-but-abandoned passwords are cleared after 10 s of inactivity.
    Timer { id: clearTimer; interval: 10000; onTriggered: root.currentText = "" }
    onCurrentTextChanged: { if (currentText.length > 0) { failed = false; clearTimer.restart() } }

    function tryUnlock(ctrlHeld) {
        if (unlockInProgress || currentText.length === 0) return
        keepAwake = !!ctrlHeld
        unlockInProgress = true
        if (!pam.start()) { fail(); return }
    }
    function fail() {
        unlockInProgress = false
        failed = true
        currentText = ""
        shouldReFocus()
    }

    PamContext {
        id: pam
        config: "hyprlock"
        onPamMessage: { if (responseRequired) respond(root.currentText) }
        onCompleted: result => {
            if (result === PamResult.Success) {
                root.unlockInProgress = false
                root.currentText = ""
                root.unlocked(root.targetAction)
            } else {
                root.fail()
            }
        }
        onError: root.fail()
    }

    // ── fingerprint (optional) ───────────────────────────────────────────────
    // Runs in parallel with the password: a fingerprint-only PAM stack shipped in
    // ./pam (no /etc/pam.d change). Active only when fprintd is installed and this
    // user has enrolled fingers; restarted after each timeout while the lock shows.
    property bool fingerprintReady: false        // fprintd + enrolled finger
    property string fingerprintMessage: ""       // e.g. "Place your finger on the sensor"
    property bool fingerprintFailed: false
    Process {
        running: true
        command: ["sh", "-c", 'command -v fprintd-list >/dev/null && fprintd-list "$USER" 2>/dev/null | grep -qi "finger"']
        onExited: code => { root.fingerprintReady = code === 0; if (root.fingerprintReady) fpRestart.start() }
    }
    PamContext {
        id: fp
        config: "fingerprint"
        configDirectory: Quickshell.shellDir + "/pam"
        onPamMessage: {
            // pam_fprintd only informs ("Place your finger…", "Failed to match");
            // it never asks for a typed response
            if (responseRequired) respond("")
            else { root.fingerprintMessage = message; root.fingerprintFailed = messageIsError }
        }
        onCompleted: result => {
            if (result === PamResult.Success && !root.unlockInProgress) {
                root.currentText = ""
                root.unlocked(root.targetAction)
            } else {
                root.fingerprintFailed = true
                fpRestart.start()          // timed out / no match: listen again
            }
        }
        onError: { root.fingerprintFailed = true; fpRestart.interval = 3000; fpRestart.start() }
    }
    Timer {
        id: fpRestart
        interval: 600
        onTriggered: if (root.fingerprintReady && !root.exiting && !fp.active) { interval = 600; fp.start() }
    }

    // Test hook for the non-locking preview only. In a real lock there is no IPC
    // that accepts a password.
    IpcHandler {
        target: "lock"
        enabled: root.preview
        function status(): string {
            return JSON.stringify({ preview: root.preview, failed: root.failed, busy: root.unlockInProgress, typed: root.currentText.length })
        }
        function tryPassword(pw: string): string { root.currentText = pw; root.tryUnlock(false); return "started" }
        function type(text: string): string { root.currentText = text; return "ok" }
        function quit(): string { root.exiting = true; return "ok" }   // preview only (handler disabled otherwise)
    }
}
