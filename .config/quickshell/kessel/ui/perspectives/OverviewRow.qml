// SPDX-License-Identifier: GPL-3.0-or-later
// Overview perspective: workspaces + music chip · clock · weather · system · live chips.
import QtQuick
import Quickshell
import "../.."
import "../../services"
import "../../components"

Item {
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.islandHeight
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        // ── left wing ───────────────────────────────────────────────
        Row {
            id: workspaces
            spacing: 5
            // Keep the dots on screen while the pointer is on them (no glance).
            HoverHandler { margin: 8; onHoveredChanged: IslandState.holdRest = hovered }
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: Hypr.maxId
                Rectangle {
                    required property int index
                    readonly property int wsId: index + 1
                    readonly property bool focused: Hypr.focusedId === wsId
                    readonly property bool used: Hypr.occupied(wsId)
                    anchors.verticalCenter: parent.verticalCenter
                    width: focused ? 18 : 7
                    height: 7
                    radius: 3.5
                    color: focused ? Theme.accent : used ? Theme.subtext : Theme.overlay
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: Hypr.focus(parent.wsId) }
                }
            }
        }

        Item {
          visible: Media.active
          implicitWidth: mediaRow.implicitWidth
          implicitHeight: mediaRow.implicitHeight
          anchors.verticalCenter: parent.verticalCenter
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Media.toggle() }
          Row {
            id: mediaRow
            spacing: 7
            Rectangle {
                width: 20; height: 20; radius: 10
                color: Theme.overlay
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                Image { anchors.fill: parent; source: Media.art; fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: status === Image.Ready }
                Glyph { anchors.centerIn: parent; optical: true; text: Icons.music; size: Theme.fontSmall; visible: Media.art === ""; color: Theme.subtext }
            }
            Label {
                text: Media.title
                width: Math.min(implicitWidth, 150)
                size: Theme.fontSmall + 0.5
                anchors.verticalCenter: parent.verticalCenter
            }
            EqBars { playing: Media.playing; anchors.verticalCenter: parent.verticalCenter }
          }
        }

        // ── centre ──────────────────────────────────────────────────
        Item {
            implicitWidth: clockRow.implicitWidth
            implicitHeight: clockRow.implicitHeight
            anchors.verticalCenter: parent.verticalCenter
            Row {
                id: clockRow
                spacing: 8
                Label { text: Time.time; font.bold: true; size: Theme.fontUi + 1; anchors.verticalCenter: parent.verticalCenter }
                Label { text: Time.dateShort; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: IslandState.openPanel("notifications") }
        }

        // ── right wing ──────────────────────────────────────────────
        Chip { clickable: true; onClicked: IslandState.openPanel("notifications"); visible: Weather.ok; icon: Weather.icon; text: Weather.temp; tint: Theme.yellow; anchors.verticalCenter: parent.verticalCenter }
        Chip { clickable: true; onClicked: IslandState.openPanel("control"); icon: Icons.cpu; text: Stats.pct(Stats.cpu); reserve: "100%"; tint: Stats.cpu > 0.85 ? Theme.red : Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
        Chip { clickable: true; onClicked: IslandState.openPanel("control"); icon: Icons.memory; text: Stats.pct(Stats.mem); reserve: "100%"; tint: Stats.mem > 0.85 ? Theme.red : Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
        // network: link icon, then fixed-width ↓ / ↑ so the island never changes size
        Chip { clickable: true; onClicked: IslandState.openPanel("control"); icon: Net.icon; tint: Net.online ? Theme.subtext : Theme.red; anchors.verticalCenter: parent.verticalCenter }
        Chip { visible: Net.online; clickable: true; onClicked: IslandState.openPanel("control"); icon: Icons.download; text: Stats.compact(Stats.rxRate); reserve: "999K"; anchors.verticalCenter: parent.verticalCenter }
        Chip { visible: Net.online; clickable: true; onClicked: IslandState.openPanel("control"); icon: Icons.upload; text: Stats.compact(Stats.txRate); reserve: "999K"; anchors.verticalCenter: parent.verticalCenter }
        BatteryChip { anchors.verticalCenter: parent.verticalCenter }

        // live activities
        Chip { clickable: true; onClicked: Recorder.stop(); visible: Recorder.recording; icon: Icons.record; text: Time.hms(Recorder.elapsed); tint: Theme.red; anchors.verticalCenter: parent.verticalCenter }
        Chip { clickable: true; onClicked: IslandState.openPanel("timer"); visible: Timers.cdActive; icon: Icons.sand; text: Time.hms(Timers.cdLeft); tint: Theme.purple; anchors.verticalCenter: parent.verticalCenter }
        Chip { visible: Timers.swRunning; icon: Icons.timer; text: Time.hms(Timers.swMs / 1000); tint: Theme.purple; anchors.verticalCenter: parent.verticalCenter }
        Chip { clickable: true; onClicked: Session.toggleFloatMode(); visible: Session.floatMode; icon: Icons.floating; tint: Theme.accent3; anchors.verticalCenter: parent.verticalCenter }
        Chip { visible: Session.inhibitIdle; icon: Icons.coffee; tint: Theme.yellow; anchors.verticalCenter: parent.verticalCenter }
    }
}
