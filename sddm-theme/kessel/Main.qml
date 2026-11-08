// SPDX-License-Identifier: GPL-3.0-or-later
// Kessel SDDM theme (Qt 6). Visually matches ~/.config/quickshell/kessel-lock:
// blurred wallpaper + dark overlay, frosted card (time · date · avatar ·
// "$ whoami" · user), and a bottom toolbar (session + keyboard · password ·
// sleep / power / reboot). Uses only SDDM's own QML API, no Quickshell.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: root
    width: Screen.width
    height: Screen.height

    // Theme (written into theme.conf by ~/Scripts/sddm-theme.sh from the desktop theme):
    // dark = pitch black, light = eggshell — same as the lock screen.
    readonly property bool dark: (config.stringValue("mode") || "dark") !== "light"
    readonly property color base: config.stringValue("base") || (dark ? "#000000" : "#f0ead6")
    readonly property color fg: config.stringValue("text") || (dark ? "#e8e8e8" : "#1d1b16")
    readonly property color accent: config.stringValue("accent") || "#8aadf4"
    readonly property color red: config.stringValue("red") || "#e06c75"
    readonly property color subtext: a(fg, 0.68)
    readonly property color faint: a(fg, 0.45)
    readonly property color toolbarColor: a(base, dark ? 0.82 : 0.86)
    readonly property color onAccent: dark ? "#000000" : "#ffffff"
    function a(c, alpha) { return Qt.rgba(c.r, c.g, c.b, alpha) }
    readonly property string mono: "JetBrainsMono Nerd Font Mono"
    readonly property string nf: "JetBrainsMono Nerd Font Propo"   // icons: real widths, so they centre (regular build spills right)
    function g(cp) { return String.fromCodePoint(cp) }

    // ── state ────────────────────────────────────────────────────────────────
    property int userIndex: Math.max(0, userModel.lastIndex)
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool busy: false
    property bool failed: false
    readonly property string userName: userData(userIndex, "name") || userModel.lastUser || ""

    // read a role from userModel by index (works on Qt 6 SDDM)
    function userData(i, role) {
        const roleId = Qt.UserRole + ({ name: 1, realName: 2, homeDir: 3, icon: 4 })[role]
        return userModel.data(userModel.index(i, 0), roleId)
    }
    function sessionName(i) { return sessionModel.data(sessionModel.index(i, 0), Qt.UserRole + 4) || "Session" }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.failed = true
            password.text = ""
            shake.restart()
            password.forceActiveFocus()
        }
        function onLoginSucceeded() { root.busy = false }
    }
    function login() {
        if (busy || password.text.length === 0) return
        busy = true
        failed = false
        sddm.login(userName, password.text, sessionIndex)
    }

    // ── background ───────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: root.base }
    Image {
        id: wall
        anchors.fill: parent
        source: config.stringValue("background")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        blurEnabled: true
        blurMax: 64
        blur: 1.0
        saturation: -0.1
        visible: wall.status === Image.Ready
    }
    Rectangle { anchors.fill: parent; color: root.a(root.base, root.dark ? 0.62 : 0.58) }

    MouseArea { anchors.fill: parent; onPressed: password.forceActiveFocus() }

    // entrance
    property real enter: 0
    Behavior on enter { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
    Component.onCompleted: { enter = 1; password.forceActiveFocus() }

    // ── centre card ──────────────────────────────────────────────────────────
    Timer { id: tick; interval: 1000; running: true; repeat: true; property date now: new Date(); onTriggered: now = new Date() }

    Rectangle {
        id: centerCard
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40
        width: info.implicitWidth + 80
        height: info.implicitHeight + 56
        radius: 28
        color: root.a(root.base, root.dark ? 0.45 : 0.55)
        border.width: 1
        border.color: root.a(root.fg, 0.07)
        opacity: root.enter
        scale: 0.92 + 0.08 * root.enter
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 1.0; shadowOpacity: root.dark ? 0.55 : 0.18; shadowColor: "black"; shadowVerticalOffset: 8 }

        ColumnLayout {
            id: info
            anchors.centerIn: parent
            spacing: 0
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(tick.now, "HH:mm")
                font.pixelSize: Math.min(84, root.height * 0.11)
                font.family: root.mono
                font.weight: Font.Bold
                color: root.fg
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(tick.now, "dddd, d MMMM")
                font.pixelSize: 20
                font.family: root.mono
                color: root.subtext
                topPadding: 6
            }
            Item { Layout.preferredHeight: Math.min(48, root.height * 0.04) }

            // avatar (round) with ‹ › user switching when there is more than one user
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 18
                Text {
                    visible: userModel.count > 1
                    text: root.g(0xF0141)
                    font.family: root.nf; font.pixelSize: 28; color: root.faint
                    MouseArea { anchors.fill: parent; anchors.margins: -10; cursorShape: Qt.PointingHandCursor
                                onClicked: root.userIndex = (root.userIndex + userModel.count - 1) % userModel.count }
                }
                Item {
                    readonly property real s: Math.min(160, root.height * 0.17)
                    Layout.preferredWidth: s
                    Layout.preferredHeight: s
                    Image {
                        id: face
                        anchors.fill: parent
                        // SDDM's generic default face counts as "no avatar" → light fallback icon
                        readonly property string src: root.userData(root.userIndex, "icon") || ""
                        source: src.endsWith("/faces/.face.icon") ? "" : src
                        sourceSize: Qt.size(320, 320)
                        fillMode: Image.PreserveAspectCrop
                        visible: false
                    }
                    Rectangle { id: faceMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
                    MultiEffect {
                        anchors.fill: parent
                        source: face
                        maskEnabled: true
                        maskSource: faceMask
                        visible: face.status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: face.status !== Image.Ready
                        text: root.g(0xF0009)
                        font.family: root.nf
                        font.pixelSize: parent.s
                        color: root.subtext
                    }
                }
                Text {
                    visible: userModel.count > 1
                    text: root.g(0xF0142)
                    font.family: root.nf; font.pixelSize: 28; color: root.faint
                    MouseArea { anchors.fill: parent; anchors.margins: -10; cursorShape: Qt.PointingHandCursor
                                onClicked: root.userIndex = (root.userIndex + 1) % userModel.count }
                }
            }
            Item { Layout.preferredHeight: 20 }
            Text { Layout.alignment: Qt.AlignHCenter; text: "$ whoami"; font.pixelSize: 15; font.family: root.mono; color: root.faint; bottomPadding: 6 }
            Text { Layout.alignment: Qt.AlignHCenter; text: root.userName; font.pixelSize: 36; font.family: root.mono; font.weight: Font.Medium; color: root.fg }
        }
    }

    // "Welcome" pill (the lock screen's "Locked" pill)
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: centerCard.bottom
        anchors.topMargin: 16
        width: pillRow.implicitWidth + 24
        height: pillRow.implicitHeight + 10
        radius: height / 2
        color: root.a(root.fg, 0.08)
        opacity: root.enter
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            Text { text: root.g(0xF0379); font.family: root.nf; font.pixelSize: 18; color: root.subtext; anchors.verticalCenter: parent.verticalCenter }
            Text { text: sddm.hostName || "Welcome"; font.family: root.mono; font.pixelSize: 16; color: root.subtext; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // ── toolbars ─────────────────────────────────────────────────────────────
    component Toolbar: Rectangle {
        default property alias items: row.data
        implicitHeight: 52
        implicitWidth: row.implicitWidth + 16
        radius: height / 2
        color: root.toolbarColor
        border.width: 1
        border.color: root.a(root.fg, 0.08)
        opacity: root.enter
        scale: 0.92 + 0.08 * root.enter
        RowLayout { id: row; anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 4 }
    }
    component Btn: Rectangle {
        id: b
        property string icon: ""
        property bool toggled: false
        property color tint: root.accent
        signal clicked()
        Layout.preferredWidth: 38; Layout.preferredHeight: 38; Layout.alignment: Qt.AlignVCenter
        radius: 19
        color: toggled ? tint : (bma.containsMouse ? root.a(root.fg, 0.10) : "transparent")
        opacity: enabled ? 1 : 0.5
        Text { anchors.centerIn: parent; text: b.icon; font.family: root.nf; font.pixelSize: 20; color: b.toggled ? root.onAccent : root.subtext }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }

    Toolbar {
        id: mainBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20

        Item {
            id: field
            Layout.preferredWidth: 260
            Layout.preferredHeight: 38
            Layout.leftMargin: 8
            TextInput {
                id: password
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                enabled: !root.busy
                color: "transparent"
                selectionColor: "transparent"
                selectedTextColor: "transparent"
                cursorVisible: false
                font.pixelSize: 16
                focus: true
                onAccepted: root.login()
                onTextChanged: if (text.length > 0) root.failed = false
                Keys.onEscapePressed: text = ""
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: password.text.length === 0
                text: root.busy ? "Logging in…" : root.failed ? "Incorrect password" : "Enter password"
                color: root.failed ? root.red : root.faint
                font.family: root.mono
                font.pixelSize: 15
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Repeater {
                    model: Math.min(password.text.length, 24)
                    ShapeChar { color: root.accent; size: 18 }   // Material shapes, as on the lock screen
                }
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: field; property: "Layout.leftMargin"; to: 18; duration: 45 }
                NumberAnimation { target: field; property: "Layout.leftMargin"; to: -2; duration: 70 }
                NumberAnimation { target: field; property: "Layout.leftMargin"; to: 13; duration: 60 }
                NumberAnimation { target: field; property: "Layout.leftMargin"; to: 8; duration: 50 }
            }
        }
        Btn { icon: root.g(0xF0054); toggled: true; enabled: !root.busy; onClicked: root.login() }
    }

    // left: keyboard layout (hidden when SDDM reports none)
    Toolbar {
        visible: keyboard.layouts.length > 0
        anchors.right: mainBar.left
        anchors.rightMargin: 10
        anchors.verticalCenter: mainBar.verticalCenter
        Row {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 8
            Text { text: root.g(0xF030C); font.family: root.nf; font.pixelSize: 20; color: root.subtext; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: keyboard.layouts.length > 0 ? keyboard.layouts[keyboard.currentLayout].shortName : ""
                font.family: root.mono; font.pixelSize: 15; color: root.subtext
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    enabled: keyboard.layouts.length > 1
                    onClicked: keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
                }
            }
        }
    }

    // ── session switcher: a small icon top-left; click to expand ─────────────
    Rectangle {
        id: sessionSwitcher
        property bool open: false
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 16
        width: open ? Math.max(260, sessionList.implicitWidth + 24) : 40
        height: open ? 40 + sessionList.implicitHeight + 12 : 40
        radius: open ? 20 : 20
        color: root.toolbarColor
        border.width: 1
        border.color: root.a(root.fg, 0.08)
        clip: true
        opacity: root.enter
        Behavior on width  { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        // header: icon (+ current session name when open)
        Item {
            width: parent.width
            height: 40
            // centred in the 40×40 circle by box, not by a fixed x (Nerd Font
            // glyph advances don't match their ink, so x: 10 sat off-centre)
            Text {
                width: 40; height: 40
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.g(0xF0379)
                font.family: root.nf; font.pixelSize: 18
                color: sessionSwitcher.open ? root.accent : root.subtext
            }
            Text {
                x: 40
                anchors.verticalCenter: parent.verticalCenter
                visible: sessionSwitcher.open
                text: "Session"
                font.family: root.mono; font.pixelSize: 13
                color: root.faint
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: sessionSwitcher.open = !sessionSwitcher.open
            }
        }
        Column {
            id: sessionList
            x: 6; y: 42
            visible: sessionSwitcher.open
            spacing: 2
            Repeater {
                model: sessionModel
                Rectangle {
                    required property int index
                    required property string name
                    readonly property bool current: index === root.sessionIndex
                    width: Math.max(248, label.implicitWidth + 44)
                    height: 32
                    radius: 10
                    color: current ? root.a(root.accent, 0.18) : (sma.containsMouse ? root.a(root.fg, 0.08) : "transparent")
                    Text {
                        id: label
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.name
                        font.family: root.mono; font.pixelSize: 14
                        color: parent.current ? root.accent : root.fg
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.current
                        text: root.g(0xF012C)
                        font.family: root.nf; font.pixelSize: 14; color: root.accent
                    }
                    MouseArea {
                        id: sma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.sessionIndex = parent.index; sessionSwitcher.open = false; password.forceActiveFocus() }
                    }
                }
            }
        }
    }

    // right: sleep, power, reboot (hidden if SDDM offers none)
    Toolbar {
        visible: sddm.canSuspend || sddm.canPowerOff || sddm.canReboot
        anchors.left: mainBar.right
        anchors.leftMargin: 10
        anchors.verticalCenter: mainBar.verticalCenter
        Btn { visible: sddm.canSuspend; icon: root.g(0xF0594); onClicked: sddm.suspend() }
        Btn { visible: sddm.canPowerOff; icon: root.g(0xF0425); tint: root.red; onClicked: sddm.powerOff() }
        Btn { visible: sddm.canReboot; icon: root.g(0xF0709); tint: root.red; onClicked: sddm.reboot() }
    }
}
