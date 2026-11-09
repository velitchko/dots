// SPDX-License-Identifier: GPL-3.0-or-later
// One black capsule that changes shape. The surface is a fixed transparent
// canvas (resizing a layer surface mid-animation clips); only the pill takes input.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."
import "../services"
import "../components"

PanelWindow {
    id: win

    // Only the island on the focused monitor shows panels / notifications.
    readonly property bool live: !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === screen?.name
    readonly property string layer: live ? IslandState.layer : "rest"
    readonly property bool panelOpen: layer === "panel" && !IslandState.quitting

    visible: IslandState.shown
    anchors.top: true
    margins.top: Theme.islandMargin
    // A tight sum of pill + side-chain widths kept drifting out of sync with
    // reality (subpixel rounding past the exact total, and a QML gotcha: a
    // property seeded with a plain initial value never sees an onXChanged
    // for whatever X already held at creation, so a reload landing with the
    // timer already running started undersized and let the pill overlap it
    // until the next tick nudged the sum). A layer surface narrower than its
    // content hard-clips whatever pokes past the edge -- invisible, not just
    // off-screen -- so undersizing it is never safe. Blur isn't applied to
    // this layer (see workspaces.lua's blur-fuzzel rule, the only one), so a
    // surface sized to the full screen costs nothing extra to composite:
    // just use all of it instead of re-deriving how much is "enough".
    implicitWidth: screen ? screen.width : 1100
    // Keep the surface a small strip while resting (the compositor blurs behind the
    // whole surface every frame — expensive without a GPU). Grow at once when
    // something tall opens; shrink only after the closing spring has settled.
    readonly property real tallHeight: Math.min(screen ? screen.height - 40 : 700, 700)
    readonly property bool needsTall: layer === "panel" || layer === "notification" || layer === "summary" || layer === "alarm" || layer === "polkit"
    property bool tall: false
    onNeedsTallChanged: { if (needsTall) { shrinkTimer.stop(); tall = true } else shrinkTimer.restart() }
    Timer { id: shrinkTimer; interval: 900; onTriggered: win.tall = win.needsTall }
    implicitHeight: tall ? tallHeight : Theme.islandHeight + 44   // room for the perspective tag
    // Not + Theme.islandMargin: that coupled the screen-top gap and the
    // island-to-window gap together (changing margin shifted both by the same
    // amount, so they could never be made equal -- confirmed empirically,
    // island-to-window was always exactly margin + gaps_out + border). Fixed
    // at islandHeight alone so the two gaps are independent; islandMargin is
    // tuned to split the remainder evenly between them (see Theme.qml).
    exclusiveZone: Theme.islandHeight
    color: "transparent"
    mask: Region {
        item: pill
        Region { item: gearBtn }
        Region { item: timerPill }
        Region { item: bellBtn }
        Region { item: privacyPill }
        Region { item: updatesPill }
    }

    WlrLayershell.namespace: "kessel-island"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: panelOpen || layer === "polkit" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IdleInhibitor { window: win; enabled: Session.inhibitIdle }

    // takes keyboard focus away from text fields before a graceful quit
    Item { id: focusSink; focus: false }
    Connections {
        target: IslandState
        function onQuittingChanged() { if (IslandState.quitting) focusSink.forceActiveFocus() }
    }

    // Click outside an open panel closes it.
    // The grab can report "cleared" while the panel is still being created and
    // the surface regains focus, so it is armed only after the opening animation.
    HyprlandFocusGrab {
        id: grab
        windows: [win]
        active: win.panelOpen && armTimer.armed
        onCleared: if (win.panelOpen) IslandState.closePanel()
    }
    Timer {
        id: armTimer
        property bool armed: false
        interval: 400
        onTriggered: armed = true
    }
    onPanelOpenChanged: { armTimer.armed = false; if (panelOpen) armTimer.restart() }

    // The view that currently defines the pill's size.
    readonly property Item current: layer === "polkit" ? polkitView
        : layer === "alarm" ? alarmView
        : panelOpen ? panelLoader
        : layer === "notification" ? notifView
        : layer === "osd" ? osdView
        : layer === "summary" ? summaryView
        : restView

    // Floating side buttons: gear → quick settings, bell → notifications.
    // They ride the pill's edges, so they glide outward as it morphs.
    SideButton {
        id: gearBtn
        y: 0
        x: pill.x - width - 8
        // Becomes a back arrow while a panel was opened from another panel.
        icon: IslandState.canGoBack ? Icons.back : Icons.settings
        active: IslandState.panel === "control" || IslandState.canGoBack
        onClicked: IslandState.canGoBack ? IslandState.back() : IslandState.openPanel("control")
    }
    // Countdown: pill left of the gear while a countdown runs or is paused.
    // Dims with a pause icon while paused; click opens the timer panel. (The alarm itself still takes over the island.)
    Rectangle {
        id: timerPill
        readonly property bool on: Timers.cdActive && !Alarm.ringing
        y: 0
        x: Math.max(0, gearBtn.x - width - 8)
        height: Theme.islandHeight
        width: Math.max(height, timerRow.implicitWidth + 24)
        radius: height / 2
        color: tma.containsMouse ? Qt.tint(Theme.island, Theme.a(Theme.purple, 0.22)) : Theme.island
        border.width: pill.border.width
        border.color: Theme.a(Theme.purple, tma.containsMouse ? 0.75 : 0.5)
        opacity: on ? 1 : 0
        visible: opacity > 0.01
        scale: on ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on scale { SpringAnimation { spring: Theme.springStiffness; damping: 0.4; epsilon: 0.01 } }
        Behavior on x { SpringAnimation { spring: Theme.springStiffness; damping: Theme.springDamping; epsilon: 0.25 } }
        Row {
            id: timerRow
            anchors.centerIn: parent
            spacing: 6
            Glyph { text: Timers.cdRunning ? Icons.sand : Icons.pause; color: Theme.purple; size: Theme.fontSmall + 1; optical: true; anchors.verticalCenter: parent.verticalCenter }
            Label {
                text: Time.hms(Timers.cdLeft)
                color: Timers.cdRunning ? Theme.text : Theme.subtext
                size: Theme.fontSmall
                font.bold: true
                font.features: { "tnum": 1 }          // fixed-width digits: the pill doesn't jitter
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: IslandState.openPanel("timer") }
    }
    SideButton {
        id: bellBtn
        y: 0
        x: pill.x + pill.width + 8
        icon: Notifs.dnd ? Icons.bellOff : Icons.bell
        tint: Notifs.dnd ? Theme.red : Theme.accent
        active: IslandState.panel === "notifications" || Notifs.dnd
        badge: Notifs.dnd ? 0 : Notifs.count
        onClicked: IslandState.openPanel("notifications")
    }

    // Perspective name, shown briefly *below* the island while scrolling through
    // perspectives (it never takes over the pill, so the morph goes straight on).
    // Privacy: red pill while the mic, camera or screen is in use
    Rectangle {
        id: privacyPill
        y: 0
        x: bellBtn.x + bellBtn.width + 8
        height: Theme.islandHeight
        width: Math.max(height, privRow.implicitWidth + 22)
        radius: height / 2
        // Same material as the island (opaque), tinted with the theme's error colour.
        color: Qt.tint(Theme.island, Theme.a(Theme.red, 0.16))
        border.width: pill.border.width
        border.color: Theme.a(Theme.red, 0.6)
        opacity: Privacy.any ? 1 : 0
        visible: opacity > 0.01
        scale: Privacy.any ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on scale { SpringAnimation { spring: Theme.springStiffness; damping: 0.4; epsilon: 0.01 } }
        Row {
            id: privRow
            anchors.centerIn: parent
            spacing: 4
            // Mic: click mutes / unmutes the input. While it's live, a soft halo
            // pulses with your voice (MicLevel); muted shows the crossed-out mic.
            Item {
                visible: Privacy.mic
                width: 24; height: 24
                Rectangle {
                    anchors.centerIn: parent
                    width: 22; height: 22; radius: 11
                    color: Theme.red
                    opacity: Audio.micMuted ? 0 : Math.min(0.45, MicLevel.level * 0.8)
                    scale: 0.7 + Math.min(1, MicLevel.level) * 0.5
                    Behavior on opacity { NumberAnimation { duration: 90 } }
                    Behavior on scale { NumberAnimation { duration: 90 } }
                }
                Glyph {
                    anchors.centerIn: parent
                    text: Audio.micMuted ? Icons.micOff : Icons.mic
                    color: Audio.micMuted ? Theme.subtext : Theme.red
                    size: Theme.fontSmall + 1
                    optical: true
                    scale: Audio.micMuted ? 1 : 1 + Math.min(1, MicLevel.level) * 0.18
                    Behavior on scale { NumberAnimation { duration: 90 } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Audio.toggleMicMute() }
            }
            // Camera: no general way to mute a webcam, so click jumps to the app using it.
            Item {
                visible: Privacy.camera
                width: 24; height: 24
                Glyph { anchors.centerIn: parent; text: Icons.camera; color: Theme.red; size: Theme.fontSmall + 1; optical: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Privacy.focusCamera() }
            }
            Item {
                visible: Privacy.screen
                width: 24; height: 24
                Glyph { anchors.centerIn: parent; text: Icons.screenShare; color: Theme.red; size: Theme.fontSmall + 1; optical: true }
            }
        }
        HoverHandler { id: privHover }
        Hint {
            visible: privHover.hovered && text !== ""
            text: [Privacy.mic ? (Audio.micMuted ? "Microphone muted (" + Privacy.micApps + "): click to unmute" : "Microphone: " + Privacy.micApps + ": click to mute") : "",
                   Privacy.camera ? "Camera in use: click to go to the app" : "",
                   Privacy.screen ? "Screen is being shared" : ""].filter(s => s).join("\n")
        }
    }

    // Pending updates: accent pill (after the privacy pill when that's showing)
    Rectangle {
        id: updatesPill
        y: 0
        x: privacyPill.visible ? privacyPill.x + privacyPill.width + 8 : bellBtn.x + bellBtn.width + 8
        height: Theme.islandHeight
        width: Math.max(height, updRow.implicitWidth + 22)
        radius: height / 2
        // Same material as the island (opaque), in the wallpaper accent.
        color: uma.containsMouse ? Qt.tint(Theme.island, Theme.a(Theme.accent, 0.22)) : Theme.island
        border.width: pill.border.width
        border.color: Theme.a(Theme.accent, uma.containsMouse ? 0.7 : 0.45)
        opacity: Updates.count > 0 ? 1 : 0
        visible: opacity > 0.01
        scale: Updates.count > 0 ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on scale { SpringAnimation { spring: Theme.springStiffness; damping: 0.4; epsilon: 0.01 } }
        Behavior on x { SpringAnimation { spring: Theme.springStiffness; damping: Theme.springDamping; epsilon: 0.25 } }
        Row {
            id: updRow
            anchors.centerIn: parent
            spacing: 5
            Glyph { text: Icons.packageUp; color: Theme.accent; size: Theme.fontSmall + 1; optical: true; anchors.verticalCenter: parent.verticalCenter }
            Label { text: Updates.count; color: Theme.text; size: Theme.fontSmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: uma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Updates.runUpdate() }
        Hint {
            visible: uma.containsMouse
            text: `${Updates.official} official · ${Updates.aur} AUR — click to update\n` + Updates.names.slice(0, 8).join(", ") + (Updates.count > 8 ? " …" : "")
        }
    }

    Rectangle {
        id: perspTag
        readonly property bool on: Perspectives.recentlyScrolled && win.layer === "rest"
        anchors.horizontalCenter: pill.horizontalCenter
        y: pill.height + (on ? 8 : 0)
        width: tagRow.implicitWidth + 20
        height: 24
        radius: 12
        color: Theme.island
        border.width: 1
        border.color: Theme.a(Theme.text, 0.08)
        opacity: on ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on y { SpringAnimation { spring: Theme.springStiffness; damping: 0.4; epsilon: 0.25 } }
        Row {
            id: tagRow
            anchors.centerIn: parent
            spacing: 6
            Glyph { text: Perspectives.info.icon; size: Theme.fontSmall; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
            Label { text: Perspectives.info.label; size: Theme.fontSmall; anchors.verticalCenter: parent.verticalCenter }
            Row {
                spacing: 3
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: Perspectives.available
                    Rectangle {
                        required property var modelData
                        width: 5; height: 5; radius: 2.5
                        color: modelData.id === Perspectives.current ? Theme.accent : Theme.a(Theme.text, 0.25)
                    }
                }
            }
        }
    }

    Rectangle {
        id: pill
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(Theme.islandHeight * 2, win.current.implicitWidth)
        height: Math.max(Theme.islandHeight, win.current.implicitHeight)
        radius: win.layer === "rest" || win.layer === "osd" ? height / 2 : Theme.radiusPanel
        color: Theme.island
        border.width: win.layer === "alarm" ? 2 : 1
        border.color: win.layer === "alarm" ? Theme.a(Theme.red, alarmPulse.v) : Theme.a(Theme.text, hover.hovered || win.panelOpen ? 0.12 : 0.06)
        Item {
            id: alarmPulse
            visible: false
            property real v: 1
            SequentialAnimation on v {
                running: win.layer === "alarm"
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 450; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
            }
        }
        // buzz: a short horizontal shake every ~1.2 s while the alarm rings
        transform: Translate { id: buzz; x: 0 }
        SequentialAnimation {
            running: win.layer === "alarm"
            loops: Animation.Infinite
            onStopped: buzz.x = 0
            NumberAnimation { target: buzz; property: "x"; to: -7; duration: 45 }
            NumberAnimation { target: buzz; property: "x"; to: 7; duration: 70 }
            NumberAnimation { target: buzz; property: "x"; to: -5; duration: 60 }
            NumberAnimation { target: buzz; property: "x"; to: 5; duration: 60 }
            NumberAnimation { target: buzz; property: "x"; to: 0; duration: 45 }
            PauseAnimation { duration: 950 }
        }
        clip: true
        onWidthChanged: IslandState.pillWidth = width

        Behavior on width  { SpringAnimation { spring: Theme.springStiffness; damping: Theme.springDamping; mass: Theme.springMass; epsilon: 0.25 } }
        Behavior on height { SpringAnimation { spring: Theme.springStiffness; damping: Theme.springDamping; mass: Theme.springMass; epsilon: 0.25 } }
        Behavior on radius { SpringAnimation { spring: Theme.springStiffness; damping: 0.5; mass: Theme.springMass; epsilon: 0.25 } }

        HoverHandler {
            id: hover
            onHoveredChanged: IslandState.hovered = hovered
        }
        // Scroll anywhere on the pill (rest or glance) → next / previous perspective.
        // Mouse wheels send 120 per notch; touchpads send small pixel deltas, in
        // either axis (two-finger swipe up/down or left/right).
        WheelHandler {
            enabled: win.layer === "rest" || win.layer === "summary"
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property real acc: 0
            onWheel: e => {
                const touch = e.pixelDelta.x !== 0 || e.pixelDelta.y !== 0
                const d = touch
                    ? (Math.abs(e.pixelDelta.y) >= Math.abs(e.pixelDelta.x) ? e.pixelDelta.y : e.pixelDelta.x)
                    : (Math.abs(e.angleDelta.y) >= Math.abs(e.angleDelta.x) ? e.angleDelta.y : e.angleDelta.x)
                acc += d
                const step = touch ? 60 : 120
                if (Math.abs(acc) >= step) {
                    IslandState.scrollPerspective(acc > 0 ? -1 : 1)
                    acc = 0
                }
            }
        }
        // Mouse "back" side button while a panel is open.
        TapHandler {
            acceptedButtons: Qt.BackButton
            enabled: win.panelOpen
            onTapped: IslandState.back()
        }

        RestView    { id: restView;    shown: win.current === restView }
        SummaryView { id: summaryView; shown: win.current === summaryView; minWidth: restView.implicitWidth }
        OsdView     { id: osdView;     shown: win.current === osdView }
        AlarmView { id: alarmView; shown: win.current === alarmView }
        PolkitView { id: polkitView; shown: win.current === polkitView }
        NotificationView { id: notifView; shown: win.current === notifView }

        Loader {
            id: panelLoader
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            focus: true
            active: win.panelOpen
            opacity: status === Loader.Ready ? 1 : 0
            scale: status === Loader.Ready ? 1 : 0.94
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.OutCubic } }
            Behavior on scale { SpringAnimation { spring: Theme.springStiffness * 1.2; damping: 0.45; epsilon: 0.002 } }
            source: {
                switch (IslandState.panel) {
                case "launcher":  return "panels/Launcher.qml"
                case "clipboard": return "panels/ClipboardPanel.qml"
                case "control":   return "panels/ControlCenter.qml"
                case "notifications": return "panels/NotificationsPanel.qml"
                case "notes":     return "panels/NotesPanel.qml"
                case "board":     return "panels/NotesPanel.qml"
                case "media":     return "panels/MediaPanel.qml"
                case "mixer":     return "panels/MixerPanel.qml"
                case "overview":  return "panels/Overview.qml"
                case "power":     return "panels/PowerPanel.qml"
                case "timer":     return "panels/TimerPanel.qml"
                case "wallpaper": return "panels/WallpaperPanel.qml"
                case "shortcuts": return "panels/ShortcutsPanel.qml"
                default:          return ""
                }
            }
            onLoaded: item.forceActiveFocus()
            Keys.onEscapePressed: IslandState.closePanel()
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Back || (e.key === Qt.Key_Left && (e.modifiers & Qt.AltModifier))) {
                    IslandState.back(); e.accepted = true
                }
            }
        }
    }
}
