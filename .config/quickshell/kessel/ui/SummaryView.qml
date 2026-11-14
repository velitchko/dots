// SPDX-License-Identifier: GPL-3.0-or-later
// Hover glance: the music controller if something plays, else today at a glance.
import QtQuick
import ".."
import "../services"
import "../components"

View {
    id: root
    implicitWidth: 520                 // matches NotificationView; fixed regardless of perspective
    implicitHeight: col.implicitHeight + 24
    readonly property bool isMusic: Perspectives.current === "music"
    readonly property bool isTime: Perspectives.current === "time"

    // timezone polling only while this section is actually visible
    Binding { target: Timezones; property: "wanted"; value: root.shown && root.isTime }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: IslandState.openPanel("control")   // quick settings; the clock opens notifications
    }

    Column {
        id: col
        anchors.top: parent.top
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.implicitWidth - 24
        spacing: 10

        // avatar · time · date/weather — centred as one group
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Avatar { size: 40; anchors.verticalCenter: parent.verticalCenter }
            Label { text: Time.time; size: Theme.fontBig; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Label { text: `${User.name} · ${Time.dateLong}`; color: Theme.subtext; size: Theme.fontSmall }
                Label {
                    visible: Weather.ok
                    text: `${Weather.icon} ${Weather.temp} ${Weather.desc}${Weather.area ? " · " + Weather.area : ""}`
                    color: Theme.yellow
                    size: Theme.fontSmall
                }
            }
        }
        MediaCard {
            visible: Media.active
            compact: !root.isMusic
            width: Math.min(460, parent.width)
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18
            Chip { icon: Icons.cpu; text: "CPU " + Math.round(Stats.cpu * 100) + "%" }
            Chip { icon: Icons.memory; text: `RAM ${Stats.memUsedGiB.toFixed(1)}/${Stats.memTotalGiB.toFixed(1)} GiB` }
            Chip { icon: Icons.download; text: Stats.human(Stats.rxRate) }
            Chip { icon: Icons.upload; text: Stats.human(Stats.txRate) }
        }

        // Time perspective only: home/Vienna/Sofia clocks + full 7-day forecast
        Column {
            visible: root.isTime
            width: parent.width
            spacing: 8

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16
                Chip { icon: Icons.place; text: "Home " + Time.time }
                Chip { icon: Icons.place; text: "Vienna " + (Timezones.vienna !== "" ? Timezones.vienna : "--:--") }
                Chip { icon: Icons.place; text: "Sofia " + (Timezones.sofia !== "" ? Timezones.sofia : "--:--") }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                Repeater {
                    model: Weather.forecast.slice(0, 7)
                    Column {
                        required property var modelData
                        width: 62
                        spacing: 1
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.day; color: Theme.subtext; size: Theme.fontSmall - 1 }
                        Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; color: Theme.yellow; size: Theme.fontSmall + 1; optical: true }
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.max; size: Theme.fontSmall - 1 }
                    }
                }
            }
        }
    }
}
