// SPDX-License-Identifier: GPL-3.0-or-later
// Kessel lock surface. Standalone (no end-4 modules); layout follows the user's
// own adaptation of end-4/dots-hyprland's lock screen and clock widget:
// the screen frosts over into the blurred wallpaper + dark overlay, frosted centre card (time, date, avatar,
// "$ whoami", username), a "Locked" pill, and a bottom toolbar
// (keyboard layout · password · battery / sleep / power / reboot).
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Widgets

MouseArea {
    id: root
    required property LockContext context
    readonly property bool requirePasswordToPower: true
    readonly property string user: Quickshell.env("USER") || "user"
    // set by shell.qml: which output this surface covers (for its screenshot)
    property string screenName: ""

    function forceFieldFocus() { passwordBox.forceActiveFocus() }
    Connections {
        target: root.context
        function onShouldReFocus() { root.forceFieldFocus() }
        function onFailedChanged() { if (root.context.failed) shake.restart() }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: forceFieldFocus()
    onPositionChanged: forceFieldFocus()

    // entrance animation
    property real toolbarScale: 0.92
    property real toolbarOpacity: 0
    Behavior on toolbarScale { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
    Behavior on toolbarOpacity { NumberAnimation { duration: 260 } }
    Component.onCompleted: { forceFieldFocus(); toolbarScale = 1; toolbarOpacity = 1 }

    property bool ctrlHeld: false
    Keys.onPressed: event => {
        root.context.resetClearTimer()
        if (event.key === Qt.Key_Control) root.ctrlHeld = true
        if (event.key === Qt.Key_Escape) { root.context.currentText = ""; root.context.resetTargetAction() }
        forceFieldFocus()
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control) root.ctrlHeld = false
        forceFieldFocus()
    }

    // ── background: the screen frosts over, then becomes the wallpaper ───────
    // lock.sh saves a screenshot of each output just before locking. The first
    // frame shows it sharp (no black flash), then the blur and the dark overlay
    // ease in, and the blurred wallpaper crossfades in underneath. Without a
    // screenshot the wallpaper simply fades in from black. Both images load
    // synchronously: the screenshot is raw (PPM) and the wallpaper a small copy,
    // so the very first frame already has them.
    property real frost: 0        // 0 = sharp screenshot → 1 = blurred + overlay
    property real wallIn: 0       // 0 = screenshot → 1 = blurred wallpaper
    Behavior on frost  { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
    Behavior on wallIn { NumberAnimation { duration: 800; easing.type: Easing.InOutSine } }
    Timer { running: true; interval: 30;  onTriggered: root.frost = 1 }
    Timer { running: true; interval: 420; onTriggered: root.wallIn = 1 }

    Rectangle { anchors.fill: parent; color: Style.base }
    Image {
        id: wall
        anchors.fill: parent
        source: "file://" + Style.lockWallpaper
        fillMode: Image.PreserveAspectCrop
        // synchronous only for theme.sh's small copy; anything else (e.g. no copy
        // yet) must never hold up the lock
        asynchronous: !Style.lockWallpaper.endsWith("-lock.jpg")
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        blurEnabled: true
        blurMax: 64
        blur: 1.0
        saturation: -0.1
        opacity: shotFx.visible ? root.wallIn : Math.max(root.wallIn, root.frost)
        visible: wall.status === Image.Ready
    }
    Image {
        id: shot
        anchors.fill: parent
        source: root.screenName !== "" ? "file://" + Quickshell.env("XDG_RUNTIME_DIR") + "/kessel-lock/" + root.screenName + ".ppm" : ""
        fillMode: Image.Stretch
        asynchronous: false
        cache: false
        visible: false
    }
    MultiEffect {
        id: shotFx
        anchors.fill: parent
        source: shot
        blurEnabled: true
        blurMax: 64
        blur: root.frost
        saturation: -0.1 * root.frost
        opacity: 1 - root.wallIn
        visible: shot.status === Image.Ready && opacity > 0.001
    }
    Rectangle { anchors.fill: parent; color: Style.overlay; opacity: root.frost }

    // ── centre card ──────────────────────────────────────────────────────────
    SystemClock { id: clock; precision: SystemClock.Seconds }

    Rectangle {
        id: centerCard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -40
        width: centerInfo.implicitWidth + 80
        height: centerInfo.implicitHeight + 56
        radius: 28
        color: Style.card
        border.width: 1
        border.color: Style.cardBorder
        opacity: root.toolbarOpacity
        scale: root.toolbarScale
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 1.0
            shadowOpacity: Style.dark ? 0.55 : 0.18
            shadowColor: "black"
            shadowVerticalOffset: 8
        }

        ColumnLayout {
            id: centerInfo
            anchors.centerIn: parent
            spacing: 0

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(clock.date, "HH:mm")
                font.pixelSize: Math.min(84, root.height * 0.11)
                font.family: Style.mono
                font.weight: Font.Bold
                color: Style.text
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                font.pixelSize: 20
                font.family: Style.mono
                color: Style.subtext
                topPadding: 6
            }

            Item { Layout.preferredHeight: Math.min(48, root.height * 0.04) }

            // avatar: ~/.face first. The lock runs as the user, so it can read it,
            // and it's the current picture. The SDDM copy (made by sddm-theme.sh
            // install) and AccountsService's can be stale; they're only fallbacks.
            Item {
                Layout.alignment: Qt.AlignHCenter
                readonly property real s: Math.min(160, root.height * 0.17)
                Layout.preferredWidth: s
                Layout.preferredHeight: s
                ClippingRectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    Image {
                        id: avatar
                        anchors.fill: parent
                        readonly property var sources: [
                            "file://" + Quickshell.env("HOME") + "/.face",
                            "file://" + Quickshell.env("HOME") + "/.face.icon",
                            "file:///usr/share/sddm/faces/" + root.user + ".face.icon",
                            "file:///var/lib/AccountsService/icons/" + root.user
                        ]
                        property int idx: 0
                        source: sources[idx]
                        sourceSize: Qt.size(320, 320)
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        // next candidate one tick later: changing source from inside its
                        // own status change is a binding loop that stops the chain early
                        onStatusChanged: if (status === Image.Error && idx < sources.length - 1) Qt.callLater(() => idx++)
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: avatar.status !== Image.Ready
                    text: Style.iAccount
                    font.family: Style.iconFont
                    font.pixelSize: parent.s
                    color: Style.subtext
                }
            }

            Item { Layout.preferredHeight: 20 }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "$ whoami"
                font.pixelSize: 15
                font.family: Style.mono
                color: Style.faint
                bottomPadding: 6
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.user
                font.pixelSize: 36
                font.family: Style.mono
                font.weight: Font.Medium
                color: Style.text
            }
        }
    }

    // "Locked" pill (the clock widget's locked state), kept below the card
    Rectangle {
        id: lockedPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: centerCard.bottom
        anchors.topMargin: 16
        width: lockedRow.implicitWidth + 24
        height: lockedRow.implicitHeight + 10
        radius: height / 2
        color: Style.pill
        opacity: root.toolbarOpacity
        Row {
            id: lockedRow
            anchors.centerIn: parent
            spacing: 6
            Text { text: Style.iLock; font.family: Style.iconFont; font.pixelSize: 18; color: Style.subtext; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "Locked"; font.family: Style.mono; font.pixelSize: 16; color: Style.subtext; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // ── main toolbar: password ───────────────────────────────────────────────
    Toolbar {
        id: mainIsland
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        Item {
            id: field
            Layout.preferredWidth: 260
            Layout.preferredHeight: 38
            Layout.leftMargin: 8

            TextInput {
                id: passwordBox
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                enabled: !root.context.unlockInProgress && !root.context.exiting
                color: "transparent"                 // shapes are drawn below
                selectionColor: "transparent"
                selectedTextColor: "transparent"
                cursorVisible: false
                // Qt re-sets cursorVisible itself on focus-in, overriding the plain
                // `false` above the moment this field is focused (it always is).
                // Re-assert it every time, or the native blink cursor comes back.
                onActiveFocusChanged: cursorVisible = false
                font.pixelSize: 16
                focus: true
                onTextChanged: if (root.context.currentText !== text) root.context.currentText = text
                onAccepted: root.context.tryUnlock(root.ctrlHeld)
                Keys.onPressed: root.context.resetClearTimer()
                Connections {
                    target: root.context
                    function onCurrentTextChanged() { if (passwordBox.text !== root.context.currentText) passwordBox.text = root.context.currentText }
                }
            }
            // No visible caret, so there's nothing to click "between" — the shapes
            // (fixed 22px pitch) and the real masked text (font-metric width) never
            // line up anyway. A click just focuses and goes to the end, instead of
            // letting Qt silently jump the edit point to a mismatched position.
            MouseArea {
                anchors.fill: parent
                onClicked: { passwordBox.forceActiveFocus(); passwordBox.cursorPosition = passwordBox.text.length }
            }
            // placeholder / status
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.context.currentText.length === 0
                text: root.context.unlockInProgress ? "Checking…"
                    : root.context.failed ? "Incorrect password"
                    : root.context.targetAction === LockContext.Action.Poweroff ? "Password to shut down"
                    : root.context.targetAction === LockContext.Action.Reboot ? "Password to restart"
                    : root.context.fingerprintReady && root.context.fingerprintFailed && root.context.fingerprintMessage !== ""
                        ? root.context.fingerprintMessage
                    : root.context.fingerprintReady ? "Password or fingerprint"
                    : "Enter password"
                color: root.context.failed || (root.context.fingerprintReady && root.context.fingerprintFailed) ? Style.red : Style.faint
                font.family: Style.mono
                font.pixelSize: 15
            }
            // password characters as Material shapes (end-4 style)
            //
            // A ListModel, not an int Repeater model + mutated var array: the
            // first attempt at this (push()/length= on a plain `var` array) did
            // NOT reliably notify bindings reading shapeKinds[index] -- shapes
            // still reshuffled on some keystrokes. ListModel's append()/remove()
            // are real, guaranteed-incremental operations Repeater is built to
            // handle one-at-a-time, so earlier positions are truly never touched.
            ListModel { id: shapeKinds }
            // Keep in sync with ShapeChar.qml's own `kinds` list.
            readonly property var shapeKindPool: ["circle", "square", "cookie4", "cookie6", "cookie9", "cookie12",
                "clover4", "clover8", "sunny", "verySunny", "softBurst", "burst", "flower",
                "triangle", "pentagon", "gem", "diamond", "pill", "puffy", "heart"]
            function syncShapeKinds() {
                const n = Math.min(root.context.currentText.length, 18)
                while (shapeKinds.count < n)
                    shapeKinds.append({ kind: field.shapeKindPool[Math.floor(Math.random() * field.shapeKindPool.length)] })
                while (shapeKinds.count > n) shapeKinds.remove(shapeKinds.count - 1)
            }
            Connections { target: root.context; function onCurrentTextChanged() { field.syncShapeKinds() } }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    model: shapeKinds
                    ShapeChar { color: Style.accent; size: 18; forced: model.kind }
                }
            }
            SequentialAnimation {
                id: shake
                property real d: 10
                NumberAnimation { target: field; property: "Layout.leftMargin"; to: 8 + shake.d; duration: 45 }
                NumberAnimation { target: field; property: "Layout.leftMargin"; to: 8 - shake.d; duration: 70 }
                NumberAnimation { target: field; property: "Layout.leftMargin"; to: 8 + shake.d / 2; duration: 60 }
                NumberAnimation { target: field; property: "Layout.leftMargin"; to: 8; duration: 50 }
            }
        }

        ToolbarButton {
            id: confirmButton
            toggled: true
            enabled: !root.context.unlockInProgress
            icon: root.context.targetAction === LockContext.Action.Poweroff ? Style.iPower
                : root.context.targetAction === LockContext.Action.Reboot ? Style.iReboot
                : root.ctrlHeld ? Style.iCoffee : Style.iArrow
            onClicked: root.context.tryUnlock(root.ctrlHeld)
        }
    }

    // ── left toolbar: keyboard layout ────────────────────────────────────────
    Toolbar {
        id: leftIsland
        anchors.right: mainIsland.left
        anchors.rightMargin: 10
        anchors.verticalCenter: mainIsland.verticalCenter
        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        Row {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 8
            Text { text: Style.iKeyboard; font.family: Style.iconFont; font.pixelSize: 20; color: Style.subtext; anchors.verticalCenter: parent.verticalCenter }
            Text { id: layoutText; text: "us"; font.family: Style.mono; font.pixelSize: 15; color: Style.subtext; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    Process {
        id: kbProbe
        running: true
        command: ["sh", "-c", "hyprctl devices -j | jq -r '[.keyboards[] | select(.main)][0] | .active_keymap // .layout // \"us\"'"]
        stdout: StdioCollector { onStreamFinished: { const t = text.trim(); if (t) layoutText.text = t.length > 14 ? t.slice(0, 12) + "…" : t } }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "activelayout") kbProbe.running = true }
    }

    // ── right toolbar: battery, sleep, power, reboot ─────────────────────────
    Toolbar {
        id: rightIsland
        anchors.left: mainIsland.right
        anchors.leftMargin: 10
        anchors.verticalCenter: mainIsland.verticalCenter
        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        Row {
            readonly property var bat: UPower.displayDevice
            readonly property bool has: (bat?.isLaptopBattery ?? false) && (bat?.isPresent ?? false)
            visible: has
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            spacing: 4
            Text {
                text: !UPower.onBattery ? Style.iBolt : Style.iBattery
                font.family: Style.iconFont; font.pixelSize: 20
                color: parent.has && UPower.onBattery && parent.bat.percentage < 0.15 ? Style.red : Style.subtext
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: parent.has ? Math.round(parent.bat.percentage * 100) : ""
                font.family: Style.mono; font.pixelSize: 15
                color: Style.subtext
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        ToolbarButton { icon: Style.iSleep; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
        ToolbarButton {
            icon: Style.iPower
            toggled: root.context.targetAction === LockContext.Action.Poweroff
            tint: Style.red
            onClicked: root.guard(LockContext.Action.Poweroff)
        }
        ToolbarButton {
            icon: Style.iReboot
            toggled: root.context.targetAction === LockContext.Action.Reboot
            tint: Style.red
            onClicked: root.guard(LockContext.Action.Reboot)
        }
    }

    // Power actions need the password: the first click arms, the password confirms.
    function guard(action) {
        if (!root.requirePasswordToPower) { root.context.unlocked(action); return }
        if (root.context.targetAction === action) root.context.resetTargetAction()
        else root.context.targetAction = action
        root.context.shouldReFocus()
    }
}
