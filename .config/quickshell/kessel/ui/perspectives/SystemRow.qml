// SPDX-License-Identifier: GPL-3.0-or-later
// System perspective: CPU / GPU / RAM sparklines, live ↓/↑ graphs, uptime.
// Temperatures ride as a small suffix on the CPU and GPU groups rather than
// as their own chip + graph, so adding the GPU barely widens the island.
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
        WorkspaceDots { anchors.verticalCenter: parent.verticalCenter }
        Row { spacing: 6; anchors.verticalCenter: parent.verticalCenter
            Chip { icon: Icons.cpu; text: Stats.pct(Stats.cpu); reserve: "100%"; anchors.verticalCenter: parent.verticalCenter }
            Spark { values: Stats.cpuHist; max: 1; tint: Stats.cpu > 0.85 ? Theme.red : Theme.accent; anchors.verticalCenter: parent.verticalCenter }
            TempTag { temp: Stats.temp; anchors.verticalCenter: parent.verticalCenter } }
        // GPU: load graph when readable (NVIDIA/AMD), "off" for a sleeping
        // laptop dGPU, temperature only for Intel iGPUs
        Row { visible: Gpu.present; spacing: 6; anchors.verticalCenter: parent.verticalCenter
            Chip { icon: Icons.gpu; text: !Gpu.on ? "off" : Gpu.busy >= 0 ? Stats.pct(Gpu.busy) : ""; reserve: Gpu.busy >= 0 ? "100%" : ""
                   textColor: Gpu.on ? Theme.text : Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
            Spark { visible: Gpu.on && Gpu.busy >= 0; values: Gpu.busyHist; max: 1; tint: Gpu.busy > 0.85 ? Theme.red : Theme.accent2; anchors.verticalCenter: parent.verticalCenter }
            TempTag { temp: Gpu.on ? Gpu.temp : -1; anchors.verticalCenter: parent.verticalCenter } }
        Row { spacing: 6; anchors.verticalCenter: parent.verticalCenter
            Chip { icon: Icons.memory; text: Stats.pct(Stats.mem); reserve: "100%"; anchors.verticalCenter: parent.verticalCenter }
            Spark { values: Stats.memHist; max: 1; tint: Theme.purple; anchors.verticalCenter: parent.verticalCenter } }
        Row { spacing: 6; anchors.verticalCenter: parent.verticalCenter
            Chip { icon: Icons.download; text: Stats.compact(Stats.rxRate); reserve: "999K"; anchors.verticalCenter: parent.verticalCenter }
            Spark { values: Stats.rxHist; tint: Theme.green; anchors.verticalCenter: parent.verticalCenter } }
        Row { spacing: 6; anchors.verticalCenter: parent.verticalCenter
            Chip { icon: Icons.upload; text: Stats.compact(Stats.txRate); reserve: "999K"; anchors.verticalCenter: parent.verticalCenter }
            Spark { values: Stats.txHist; tint: Theme.yellow; anchors.verticalCenter: parent.verticalCenter } }
        Repeater {
            model: Stats.disks.slice(0, 2)
            Chip { required property var modelData; icon: Icons.disk; text: Stats.pct(modelData.frac) + " " + (modelData.mount === "/" ? "/" : modelData.mount.split("/").pop())
                   tint: modelData.frac > 0.9 ? Theme.red : Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
        }
        BatteryChip { anchors.verticalCenter: parent.verticalCenter }
        Chip { icon: Icons.timer; text: "up " + User.uptime; anchors.verticalCenter: parent.verticalCenter }
    }
}
