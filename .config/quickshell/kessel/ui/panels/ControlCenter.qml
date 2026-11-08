// SPDX-License-Identifier: GPL-3.0-or-later
// Quick settings (SUPER+A): network, Bluetooth, output/mic + devices, brightness,
// battery / power mode, music, toggles, utilities, system, session.
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../.."
import "../../services"
import "../../components"

PanelBase {
    id: root
    title: "Quick settings"
    icon: Icons.settings
    contentWidth: 760
    contentHeight: Math.max(left.height, right.height)

    headerExtra: [
        IconButton { icon: Icons.overview; size: 26; iconSize: Theme.fontSmall + 2; onClicked: IslandState.openPanel("overview") },
        IconButton { icon: Icons.volHigh; size: 26; iconSize: Theme.fontSmall + 2; onClicked: IslandState.openPanel("mixer") },
        IconButton { icon: Icons.power; size: 26; iconSize: Theme.fontSmall + 2; tint: Theme.red; onClicked: IslandState.openPanel("power") }
    ]

    property var pskTarget: null      // Wi-Fi network waiting for a password

    // ───────────────────────── left column ─────────────────────────
    Flickable {
        id: left
        width: 370
        height: Math.min(contentHeight, 560)
        contentHeight: leftCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: leftCol
            width: parent.width
            spacing: 8

            // You
            Rectangle {
                width: parent.width
                height: 64
                radius: Theme.radiusCard
                color: Theme.card
                Avatar { id: avatar; x: 10; anchors.verticalCenter: parent.verticalCenter; size: 44 }
                Column {
                    anchors.left: avatar.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Label { text: User.realName || User.name; font.bold: true }
                    Label { text: `${User.name}@${User.host || "localhost"} · up ${User.uptime}`; color: Theme.subtext; size: Theme.fontSmall }
                }
            }

            // Network
            SectionRow {
                id: wifiRow
                width: parent.width
                icon: Net.icon
                title: Net.hasWifi ? "Wi-Fi" : "Network"
                sub: Net.available ? Net.label : "NetworkManager unavailable"
                showSwitch: Net.hasWifi
                checked: Net.hasWifi ? Net.wifiEnabled : Net.online
                expandable: Net.hasWifi && Net.wifiEnabled
                onToggled: Net.setWifi(!Net.wifiEnabled)
                onExpandedChanged: Net.scan(expanded)

                Column {
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: Net.networks.slice(0, 8)
                        ListItem {
                            required property var modelData
                            icon: Net.wifiIcon(modelData.signalStrength)
                            text: modelData.name
                            sub: modelData.connected ? "Connected" : modelData.known ? "Saved" : ""
                            selected: modelData.connected
                            busy: modelData.stateChanging
                            onClicked: {
                                if (modelData.connected) Net.disconnect(modelData)
                                else if (modelData.known) Net.connect(modelData)
                                else root.pskTarget = modelData
                            }
                        }
                    }
                    SearchField {
                        visible: root.pskTarget !== null
                        width: parent.width
                        placeholder: root.pskTarget ? "Password for " + root.pskTarget.name : ""
                        input.echoMode: TextInput.Password
                        onVisibleChanged: if (visible) focusInput()
                        onAccepted: { Net.connect(root.pskTarget, text); text = ""; root.pskTarget = null }
                    }
                    Label { visible: Net.networks.length === 0; text: "Scanning…"; color: Theme.subtext; size: Theme.fontSmall; leftPadding: 10; height: 28 }
                }
            }
            SectionRow {
                visible: Net.hasWifi && Net.wiredDevice !== null
                width: parent.width
                icon: Icons.ethernet
                title: "Ethernet"
                sub: Net.wiredConnected ? "Connected" : "Disconnected"
                checked: Net.wiredConnected
            }

            // Bluetooth
            SectionRow {
                width: parent.width
                icon: Bt.enabled ? Icons.bluetooth : Icons.btOff
                title: "Bluetooth"
                sub: !Bt.available ? Bt.missingReason : !Bt.enabled ? "Off"
                    : Bt.connected.length > 0 ? Bt.connected.map(d => d.name).join(", ") : "On"
                showSwitch: Bt.available
                checked: Bt.enabled
                expandable: Bt.enabled
                onToggled: Bt.setEnabled(!Bt.enabled)
                onExpandedChanged: Bt.scan(expanded)
                Component.onCompleted: Bt.refresh()

                Column {
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: Bt.devices.slice(0, 8)
                        ListItem {
                            required property var modelData
                            icon: modelData.connected ? Icons.btOn : Icons.bluetooth
                            text: modelData.name || modelData.address
                            sub: modelData.connected ? (modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : "Connected")
                                : modelData.paired ? "Paired" : ""
                            selected: modelData.connected
                            busy: modelData.pairing
                            onClicked: Bt.toggleDevice(modelData)
                        }
                    }
                    Label { visible: Bt.devices.length === 0; text: "Searching…"; color: Theme.subtext; size: Theme.fontSmall; leftPadding: 10; height: 28 }
                }
            }

            // Output
            SectionRow {
                visible: !Audio.ready
                width: parent.width
                icon: Icons.volOff
                title: "Audio"
                sub: "No audio device"
            }
            SliderRow {
                width: parent.width
                visible: Audio.ready
                icon: Audio.icon
                title: "Output · " + Audio.sinkName
                value: Audio.volume
                muted: Audio.muted
                expandable: Audio.sinks.length > 1
                onMoved: v => Audio.setVolume(v)
                onIconClicked: Audio.toggleMute()
                Repeater {
                    model: Audio.sinks
                    ListItem {
                        required property var modelData
                        icon: Icons.speaker
                        text: Audio.label(modelData, "Output")
                        selected: modelData === Audio.sink
                        onClicked: Audio.setSink(modelData)
                    }
                }
            }

            // Microphone
            SliderRow {
                width: parent.width
                visible: Audio.micReady
                icon: Audio.micIcon
                title: "Microphone · " + Audio.sourceName
                value: Audio.micVolume
                muted: Audio.micMuted
                tint: Theme.purple
                expandable: Audio.sources.length > 1
                onMoved: v => Audio.setMicVolume(v)
                onIconClicked: Audio.toggleMicMute()
                Repeater {
                    model: Audio.sources
                    ListItem {
                        required property var modelData
                        icon: Icons.mic
                        text: Audio.label(modelData, "Input")
                        selected: modelData === Audio.source
                        onClicked: Audio.setSource(modelData)
                    }
                }
            }

            // Brightness (laptops / backlight only)
            SliderRow {
                width: parent.width
                visible: Brightness.available
                icon: Icons.brightness
                title: "Brightness"
                value: Brightness.value
                tint: Theme.yellow
                onMoved: v => Brightness.set(v)
            }

            // Battery + power mode (laptops only)
            Rectangle {
                visible: Power.hasBattery || Power.profilesAvailable
                width: parent.width
                height: 84
                radius: Theme.radiusCard
                color: Theme.card
                Row {
                    x: 12; y: 10
                    spacing: 8
                    visible: Power.hasBattery
                    Glyph { text: Power.icon; color: Power.charging ? Theme.green : Theme.text }
                    Label { text: Math.round(Power.percent * 100) + "%"; font.bold: true }
                    Label { text: Power.timeLeft; color: Theme.subtext; size: Theme.fontSmall }
                }
                Row {
                    x: 10; y: 42
                    spacing: 6
                    visible: Power.profilesAvailable
                    Repeater {
                        model: [
                            { p: PowerProfile.PowerSaver,  icon: Icons.leaf,   label: "Saver" },
                            { p: PowerProfile.Balanced,    icon: Icons.scale,  label: "Balanced" },
                            { p: PowerProfile.Performance, icon: Icons.rocket, label: "Performance" }
                        ].filter(x => x.p !== PowerProfile.Performance || Power.hasPerformance)
                        Rectangle {
                            required property var modelData
                            readonly property bool on: Power.profile === modelData.p
                            width: 110; height: 32; radius: 16
                            color: on ? Theme.a(Theme.green, 0.2) : (pm.containsMouse ? Theme.cardHi : "transparent")
                            border.width: on ? 1 : 0
                            border.color: Theme.green
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Glyph { text: modelData.icon; color: parent.parent.on ? Theme.green : Theme.text; size: Theme.fontSmall + 2 }
                                Label { text: modelData.label; size: Theme.fontSmall }
                            }
                            MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Power.setProfile(modelData.p) }
                        }
                    }
                }
            }

            // System
            Rectangle {
                width: parent.width
                height: sys.height + 20
                radius: Theme.radiusCard
                color: Theme.card
                Column {
                    id: sys
                    x: 12; y: 10
                    width: parent.width - 24
                    spacing: 8
                    Row {
                        width: parent.width; spacing: 8
                        Glyph { text: Icons.cpu; width: 18; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                        Bar { width: parent.width - 18 - 96 - 16; value: Stats.cpu; anchors.verticalCenter: parent.verticalCenter; fill: Stats.cpu > 0.85 ? Theme.red : Theme.accent }
                        Label { text: Math.round(Stats.cpu * 100) + "%"; size: Theme.fontSmall; color: Theme.subtext; width: 96; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row {
                        width: parent.width; spacing: 8
                        Glyph { text: Icons.memory; width: 18; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                        Bar { width: parent.width - 18 - 96 - 16; value: Stats.mem; anchors.verticalCenter: parent.verticalCenter; fill: Stats.mem > 0.85 ? Theme.red : Theme.purple }
                        Label { text: Stats.memUsedGiB.toFixed(1) + "G"; size: Theme.fontSmall; color: Theme.subtext; width: 96; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row {
                        visible: Stats.temp >= 0
                        width: parent.width; spacing: 8
                        Glyph { text: Icons.thermo; width: 18; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                        Bar { width: parent.width - 18 - 96 - 16; value: Math.min(1, Stats.temp / 100); anchors.verticalCenter: parent.verticalCenter; fill: Stats.temp > 85 ? Theme.red : Theme.yellow }
                        Label { text: Math.round(Stats.temp) + "°C"; size: Theme.fontSmall; color: Theme.subtext; width: 96; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Repeater {
                        model: Stats.disks.slice(0, 3)
                        Row {
                            required property var modelData
                            width: sys.width; spacing: 8
                            Glyph { text: Icons.disk; width: 18; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                            Bar { width: parent.width - 18 - 96 - 16; value: modelData.frac; anchors.verticalCenter: parent.verticalCenter; fill: modelData.frac > 0.9 ? Theme.red : Theme.accent2 }
                            Label { text: Stats.gib(modelData.size - modelData.used) + " free"; size: Theme.fontSmall; color: Theme.subtext; width: 96; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Row {
                        spacing: 16
                        Chip { icon: Net.icon; text: Net.label }
                        Chip { icon: Icons.download; text: Stats.human(Stats.rxRate) }
                        Chip { icon: Icons.upload; text: Stats.human(Stats.txRate) }
                    }
                }
            }

            // Session
            Row {
                spacing: 8
                anchors.horizontalCenter: parent.horizontalCenter
                IconButton { icon: Icons.lock; size: 38; onClicked: { IslandState.closePanel(); Session.lock() } }
                IconButton { icon: Icons.sleep; size: 38; onClicked: IslandState.openPanel("power") }
                IconButton { icon: Icons.logout; size: 38; onClicked: IslandState.openPanel("power") }
                IconButton { icon: Icons.restart; size: 38; onClicked: IslandState.openPanel("power") }
                IconButton { icon: Icons.power; size: 38; tint: Theme.red; onClicked: IslandState.openPanel("power") }
            }
        }
    }

    // ───────────────────────── right column ────────────────────────
    Column {
        id: right
        x: 386
        width: 374
        spacing: 10

        MediaCard { visible: Media.active; width: parent.width }
        WallpaperStrip { width: parent.width }

        Grid {
            columns: 3
            spacing: 8
            Tile { width: 119; icon: Notifs.dnd ? Icons.bellOff : Icons.bell; label: "Silence"; active: Notifs.dnd; tint: Theme.red; onClicked: Notifs.dnd = !Notifs.dnd }
            Tile { width: 119; visible: NightLight.available; icon: Icons.night; label: NightLight.active ? (NightLight.manual ? "Night · on" : "Night · auto") : (NightLight.manual ? "Night · off" : "Night light")
                   active: NightLight.active; tint: Theme.yellow; onClicked: NightLight.toggle() }
            // Appearance: pitch black ↔ eggshell (accents always follow the wallpaper)
            Tile { width: 119; icon: Icons.lightDark; label: Themes.dark ? "Dark mode" : "Light mode"; active: Themes.dark; tint: Theme.accent; onClicked: Themes.toggleMode() }
            Tile { width: 119; icon: Icons.coffee; label: "Stay awake"; active: Session.inhibitIdle; tint: Theme.yellow; onClicked: Session.inhibitIdle = !Session.inhibitIdle }
            Tile { width: 119; icon: Session.floatMode ? Icons.floating : Icons.tiling; label: Session.floatMode ? "Floating" : "Tiling"; active: Session.floatMode; tint: Theme.accent3; onClicked: Session.toggleFloatMode() }
            Tile { width: 119; icon: Icons.notes; label: "Notes"; onClicked: IslandState.openPanel("notes") }
            Tile { width: 119; icon: Icons.picker; label: "Color picker"; onClicked: Utils.colorPicker() }
            Tile { width: 119; icon: Icons.screenshot; label: "Screenshot"; onClicked: Utils.screenshotRegion() }
            Tile {
                width: 119
                icon: Recorder.recording ? Icons.stop : Icons.region
                label: Recorder.recording ? "Stop " + Time.hms(Recorder.elapsed) : "Rec region"
                active: Recorder.recording
                tint: Theme.red
                onClicked: Recorder.recording ? Recorder.stop() : Utils.recordRegion()
            }
            Tile { width: 119; icon: Icons.record; label: "Rec screen"; visible: !Recorder.recording; tint: Theme.red; onClicked: Utils.recordScreen() }
            Tile { width: 119; icon: Icons.sand; label: Timers.cdActive ? Time.hms(Timers.cdLeft) : "Timer"; active: Timers.cdActive || Timers.swRunning; tint: Theme.purple; onClicked: IslandState.openPanel("timer") }
        }

    }
}
