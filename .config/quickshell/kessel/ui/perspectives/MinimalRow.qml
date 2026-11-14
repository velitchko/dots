// SPDX-License-Identifier: GPL-3.0-or-later
// Minimal perspective: just the time and date (+ battery on laptops).
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
        spacing: 10
        WorkspaceDots { anchors.verticalCenter: parent.verticalCenter }
        Label { text: Time.time; font.bold: true; size: Theme.fontUi + 2; anchors.verticalCenter: parent.verticalCenter }
        Label { text: Time.dateShort; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
        BatteryChip { anchors.verticalCenter: parent.verticalCenter }
    }
}
