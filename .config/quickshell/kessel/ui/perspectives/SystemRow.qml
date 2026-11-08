// SPDX-License-Identifier: GPL-3.0-or-later
// System perspective: CPU / RAM sparklines, live ↓/↑ graphs, uptime.
import QtQuick
import "../.."
import "../../services"
import "../../components"

Item {
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.islandHeight
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16
        Row { spacing: 6; anchors.verticalCenter: parent.verticalCenter
            Chip { icon: Icons.cpu; text: Stats.pct(Stats.cpu); reserve: "100%"; anchors.verticalCenter: parent.verticalCenter }
            Spark { values: Stats.cpuHist; max: 1; tint: Stats.cpu > 0.85 ? Theme.red : Theme.accent; anchors.verticalCenter: parent.verticalCenter } }
        Row { spacing: 6; anchors.verticalCenter: parent.verticalCenter
            Chip { icon: Icons.memory; text: Stats.pct(Stats.mem); reserve: "100%"; anchors.verticalCenter: parent.verticalCenter }
            Spark { values: Stats.memHist; max: 1; tint: Theme.purple; anchors.verticalCenter: parent.verticalCenter } }
        Row { spacing: 6; anchors.verticalCenter: parent.verticalCenter
            Chip { icon: Icons.download; text: Stats.compact(Stats.rxRate); reserve: "999K"; anchors.verticalCenter: parent.verticalCenter }
            Spark { values: Stats.rxHist; tint: Theme.green; anchors.verticalCenter: parent.verticalCenter } }
        Row { spacing: 6; anchors.verticalCenter: parent.verticalCenter
            Chip { icon: Icons.upload; text: Stats.compact(Stats.txRate); reserve: "999K"; anchors.verticalCenter: parent.verticalCenter }
            Spark { values: Stats.txHist; tint: Theme.yellow; anchors.verticalCenter: parent.verticalCenter } }
        Row { visible: Stats.temp >= 0; spacing: 6; anchors.verticalCenter: parent.verticalCenter
            Chip { icon: Icons.thermo; text: Math.round(Stats.temp) + "°"; tint: Stats.temp > 85 ? Theme.red : Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
            Spark { values: Stats.tempHist; max: 1; tint: Stats.temp > 85 ? Theme.red : Theme.yellow; anchors.verticalCenter: parent.verticalCenter } }
        Repeater {
            model: Stats.disks.slice(0, 2)
            Chip { required property var modelData; icon: Icons.disk; text: Stats.pct(modelData.frac) + " " + (modelData.mount === "/" ? "/" : modelData.mount.split("/").pop())
                   tint: modelData.frac > 0.9 ? Theme.red : Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
        }
        BatteryChip { anchors.verticalCenter: parent.verticalCenter }
        Chip { icon: Icons.timer; text: "up " + User.uptime; anchors.verticalCenter: parent.verticalCenter }
    }
}
