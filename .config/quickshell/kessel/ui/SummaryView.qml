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
    }
}
