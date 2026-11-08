// SPDX-License-Identifier: GPL-3.0-or-later
// Time perspective: clock · full date · current weather · next days · running timer.
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
        spacing: 14

        Label { text: Time.time; font.bold: true; size: Theme.fontUi + 3; anchors.verticalCenter: parent.verticalCenter }
        Label { text: Time.dateLong; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }

        Rectangle { visible: Weather.ok; width: 1; height: 16; color: Theme.a(Theme.text, 0.15); anchors.verticalCenter: parent.verticalCenter }

        // now
        Row {
            visible: Weather.ok
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            Glyph { text: Weather.icon; color: Theme.yellow; size: Theme.fontUi + 3; anchors.verticalCenter: parent.verticalCenter }
            Label { text: Weather.temp; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Label { text: Weather.desc; color: Theme.subtext; size: Theme.fontSmall + 0.5; anchors.verticalCenter: parent.verticalCenter }
        }
        // where the weather is for (detected from your IP unless Config.weatherLocation is set)
        Chip { visible: Weather.ok && Weather.area !== ""; icon: Icons.place; text: Weather.area; anchors.verticalCenter: parent.verticalCenter }
        // next three days (skip today, it's the "now" above)
        Row {
            visible: Weather.ok && Weather.forecast.length > 1
            spacing: 10
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: Weather.forecast.slice(1, 4)
                Row {
                    required property var modelData
                    spacing: 4
                    Label { text: modelData.day; color: Theme.subtext; size: Theme.fontSmall; anchors.verticalCenter: parent.verticalCenter }
                    Glyph { text: modelData.icon; color: Theme.yellow; size: Theme.fontSmall + 1; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: modelData.max; size: Theme.fontSmall; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
        // running countdown / stopwatch
        Chip { visible: Timers.cdActive; icon: Icons.sand; text: Time.hms(Timers.cdLeft); tint: Theme.purple; anchors.verticalCenter: parent.verticalCenter }
        Chip { visible: Timers.swRunning; icon: Icons.timer; text: Time.hms(Timers.swMs / 1000); tint: Theme.purple; anchors.verticalCenter: parent.verticalCenter }
        BatteryChip { anchors.verticalCenter: parent.verticalCenter }
    }
}
