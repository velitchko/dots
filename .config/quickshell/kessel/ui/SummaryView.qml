// SPDX-License-Identifier: GPL-3.0-or-later
// Hover glance: shared baseline (time, user, date, weather, now-playing,
// brief metrics) on every perspective, plus a perspective-specific extra
// section -- richer now-playing on Music, timezones + full forecast on
// Time, bigger charts + top processes on Metrics.
import QtQuick
import ".."
import "../services"
import "../components"

View {
    id: root
    // 520 matches NotificationView (700 for Metrics: its four charts read
    // better side by side than stacked) -- but never narrower than the
    // resting view already on screen. Shrinking on hover can pull the pill's
    // edge out from under the cursor, which un-hovers it, which collapses
    // it back to the (wider) resting view, which re-hovers it: an endless
    // expand/collapse loop on any perspective whose resting row is wider
    // than the glance's own base width (confirmed: Overview's chip row and
    // others can exceed 520 easily).
    property real minWidth: 0
    implicitWidth: Math.max(root.isSystem ? 700 : 520, minWidth)
    implicitHeight: col.implicitHeight + 24
    readonly property bool isMusic: Perspectives.current === "music"
    readonly property bool isTime: Perspectives.current === "time"
    readonly property bool isSystem: Perspectives.current === "system"

    // timezone polling only while this section is actually visible
    Binding { target: Timezones; property: "wanted"; value: root.shown && root.isTime }
    // top-processes polling only while this section is actually visible
    Binding { target: Processes; property: "wanted"; value: root.shown && root.isSystem }

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

        // Metrics perspective only: enlarged sparklines + top-5 process lists
        Column {
            visible: root.isSystem
            width: parent.width
            spacing: 10

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16
                Column { spacing: 4
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: "CPU"; color: Theme.subtext; size: Theme.fontSmall }
                    Spark { values: Stats.cpuHist; max: 1; tint: Stats.cpu > 0.85 ? Theme.red : Theme.accent; height: 40; barWidth: 3; count: 36 }
                }
                Column { spacing: 4
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: "RAM"; color: Theme.subtext; size: Theme.fontSmall }
                    Spark { values: Stats.memHist; max: 1; tint: Theme.purple; height: 40; barWidth: 3; count: 36 }
                }
                Column { spacing: 4
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: "RX"; color: Theme.subtext; size: Theme.fontSmall }
                    Spark { values: Stats.rxHist; tint: Theme.green; height: 40; barWidth: 3; count: 36 }
                }
                Column { spacing: 4
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: "TX"; color: Theme.subtext; size: Theme.fontSmall }
                    Spark { values: Stats.txHist; tint: Theme.yellow; height: 40; barWidth: 3; count: 36 }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 24
                Column {
                    width: 280
                    spacing: 2
                    Label { text: "Top CPU"; color: Theme.subtext; size: Theme.fontSmall; font.bold: true }
                    Repeater {
                        model: Processes.topCpu
                        Row {
                            required property var modelData
                            width: 280
                            Label { text: modelData.name; width: 200; elide: Text.ElideRight; size: Theme.fontSmall }
                            Label { text: modelData.pct.toFixed(1) + "%"; width: 70; horizontalAlignment: Text.AlignRight; color: Theme.subtext; size: Theme.fontSmall }
                        }
                    }
                }
                Column {
                    width: 280
                    spacing: 2
                    Label { text: "Top Memory"; color: Theme.subtext; size: Theme.fontSmall; font.bold: true }
                    Repeater {
                        model: Processes.topMem
                        Row {
                            required property var modelData
                            width: 280
                            Label { text: modelData.name; width: 200; elide: Text.ElideRight; size: Theme.fontSmall }
                            Label { text: modelData.pct.toFixed(1) + "%"; width: 70; horizontalAlignment: Text.AlignRight; color: Theme.subtext; size: Theme.fontSmall }
                        }
                    }
                }
            }
        }
    }
}
