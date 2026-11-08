// SPDX-License-Identifier: GPL-3.0-or-later
// Quick settings (SUPER+A): network, Bluetooth, output/mic + devices, brightness,
// battery / power mode, music, toggles, utilities, system, session.
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Bluetooth
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
                sub: !Net.available ? "NetworkManager unavailable"
                    : Net.hasWifi && Net.wifiBlocked ? "Blocked by the airplane switch / rfkill"
                    : Net.label
                showSwitch: Net.hasWifi
                checked: Net.hasWifi ? Net.wifiEnabled : Net.online
                expandable: Net.hasWifi && Net.wifiEnabled
                onToggled: Net.setWifi(!Net.wifiEnabled)
                onExpandedChanged: { Net.scan(expanded); if (!expanded) root.pskTarget = null }
                Connections {
                    target: Net
                    function onPasswordRejected(n) { root.pskTarget = n; wifiRow.expanded = true }
                }

                Column {
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: Net.networks.slice(0, 10)
                        ListItem {
                            required property var modelData
                            icon: Net.wifiIcon(modelData.signalStrength)
                            text: modelData.name
                            sub: modelData.connected ? "Connected" : modelData.known ? "Saved"
                                : Net.isOpen(modelData) ? "Open" : Net.isEnterprise(modelData) ? "Enterprise…" : ""
                            selected: modelData.connected
                            busy: modelData.stateChanging
                            action: modelData.known ? Icons.trash : ""
                            onActionClicked: Net.forget(modelData)
                            onClicked: {
                                if (modelData.connected) Net.disconnect(modelData)
                                else if (Net.isEnterprise(modelData) && !modelData.known) Net.openEditor()
                                else if (Net.needsPassword(modelData)) root.pskTarget = modelData
                                else Net.connect(modelData)
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
                    Label { visible: Net.error !== ""; text: Net.error; color: Theme.red; size: Theme.fontSmall; leftPadding: 10; height: 24 }
                    Label { visible: Net.networks.length === 0; text: "Scanning…"; color: Theme.subtext; size: Theme.fontSmall; leftPadding: 10; height: 28 }
                    ListItem { icon: Icons.settings; text: "Hidden network, VPN, more…"; onClicked: { IslandState.closePanel(); Net.openEditor() } }
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
                id: btRow
                width: parent.width
                icon: Bt.enabled ? Icons.bluetooth : Icons.btOff
                title: "Bluetooth"
                sub: !Bt.available ? Bt.missingReason : !Bt.enabled ? "Off"
                    : Bt.connected.length > 0 ? Bt.connected.map(d => d.name).join(", ") : "On"
                showSwitch: Bt.available
                checked: Bt.enabled
                expandable: Bt.enabled
                clickable: !Bt.available && Bt.hwPresent
                onClicked: Bt.restartIsland()
                onToggled: Bt.setEnabled(!Bt.enabled)
                onExpandedChanged: Bt.scan(expanded)
                Component.onCompleted: Bt.refresh()

                Column {
                    width: parent.width
                    spacing: 2
                    Label { visible: Bt.paired.length > 0; text: "My devices"; color: Theme.subtext; size: Theme.fontSmall - 1; leftPadding: 10; height: 20 }
                    Repeater {
                        model: Bt.paired.slice(0, 8)
                        ListItem {
                            required property var modelData
                            icon: modelData.connected ? Icons.btOn : Icons.bluetooth
                            text: modelData.name || modelData.address
                            sub: modelData.connected ? (modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : "Connected") : "Connect"
                            selected: modelData.connected
                            busy: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                            action: Icons.trash
                            onActionClicked: Bt.forget(modelData)
                            onClicked: Bt.toggleDevice(modelData)
                        }
                    }
                    Label { text: Bt.discovering ? "Nearby · searching…" : "Nearby"; color: Theme.subtext; size: Theme.fontSmall - 1; leftPadding: 10; height: 20 }
                    Repeater {
                        model: Bt.nearby.slice(0, 8)
                        ListItem {
                            required property var modelData
                            icon: Icons.bluetooth
                            text: modelData.name || modelData.address
                            sub: Bt.pairingAddress === modelData.address ? "Pairing…" : "Pair"
                            busy: modelData.pairing
                            onClicked: Bt.toggleDevice(modelData)
                        }
                    }
                    Label { visible: Bt.pairError !== ""; text: Bt.pairError; color: Theme.red; size: Theme.fontSmall; leftPadding: 10; width: parent.width; wrapMode: Text.Wrap }
                    Label { visible: Bt.nearby.length === 0; text: "Put the device in pairing mode"; color: Theme.muted; size: Theme.fontSmall; leftPadding: 10; height: 26 }
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
                expandable: Audio.sinks.length > 0
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
                expandable: Audio.sources.length > 0
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
                    Glyph { text: Power.icon; color: Power.charging ? Theme.green : Theme.text; optical: true }
                    Label { text: Math.round(Power.percent * 100) + "%"; font.bold: true }
                    Label { text: Power.timeLeft; color: Theme.subtext; size: Theme.fontSmall }
                }
                Label {
                    x: 14; y: 50
                    width: parent.width - 28
                    visible: !Power.profilesAvailable && Power.profilesReason !== ""
                    text: Power.profilesReason
                    color: Theme.subtext
                    size: Theme.fontSmall - 0.5
                    elide: Text.ElideRight
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
                            // Content-sized, not a hardcoded 110 (didn't fit "Performance" at
                            // today's font sizes) or a uniform width matched to the widest
                            // label (made the whole row wider than the 360px card: Saver and
                            // Balanced don't need "Performance"'s room, and this card has none
                            // to spare for three pills that size).
                            width: Math.max(72, content.implicitWidth + 24); height: 32; radius: 16
                            color: on ? Theme.a(Theme.green, 0.2) : (pm.containsMouse ? Theme.cardHi : "transparent")
                            border.width: on ? 1 : 0
                            border.color: Theme.green
                            Row {
                                id: content
                                anchors.centerIn: parent
                                spacing: 6
                                // Row doesn't vertically center children by default -- the
                                // icon (fontSmall+2) and label (fontSmall) sat at different
                                // baselines without this, the "text and icon not aligned" complaint.
                                Glyph { text: modelData.icon; color: parent.parent.on ? Theme.green : Theme.text; size: Theme.fontSmall + 2; optical: true; anchors.verticalCenter: parent.verticalCenter }
                                Label { text: modelData.label; size: Theme.fontSmall; anchors.verticalCenter: parent.verticalCenter }
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
                        Glyph { text: Icons.cpu; width: 18; color: Theme.subtext; optical: true; anchors.verticalCenter: parent.verticalCenter }
                        Bar { width: parent.width - 18 - 96 - 16; value: Stats.cpu; anchors.verticalCenter: parent.verticalCenter; fill: Stats.cpu > 0.85 ? Theme.red : Theme.accent }
                        Label { text: Math.round(Stats.cpu * 100) + "%"; size: Theme.fontSmall; color: Theme.subtext; width: 96; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row {
                        width: parent.width; spacing: 8
                        Glyph { text: Icons.memory; width: 18; color: Theme.subtext; optical: true; anchors.verticalCenter: parent.verticalCenter }
                        Bar { width: parent.width - 18 - 96 - 16; value: Stats.mem; anchors.verticalCenter: parent.verticalCenter; fill: Stats.mem > 0.85 ? Theme.red : Theme.purple }
                        Label { text: Stats.memUsedGiB.toFixed(1) + "G"; size: Theme.fontSmall; color: Theme.subtext; width: 96; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row {
                        visible: Stats.temp >= 0
                        width: parent.width; spacing: 8
                        Glyph { text: Icons.thermo; width: 18; color: Theme.subtext; optical: true; anchors.verticalCenter: parent.verticalCenter }
                        Bar { width: parent.width - 18 - 96 - 16; value: Math.min(1, Stats.temp / 100); anchors.verticalCenter: parent.verticalCenter; fill: Stats.temp > 85 ? Theme.red : Theme.yellow }
                        Label { text: Math.round(Stats.temp) + "°C"; size: Theme.fontSmall; color: Theme.subtext; width: 96; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Repeater {
                        model: Stats.disks.slice(0, 3)
                        Row {
                            required property var modelData
                            width: sys.width; spacing: 8
                            Glyph { text: Icons.disk; width: 18; color: Theme.subtext; optical: true; anchors.verticalCenter: parent.verticalCenter }
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
