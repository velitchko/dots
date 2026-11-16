// SPDX-License-Identifier: GPL-3.0-or-later
// Small "54°" suffix that rides next to a CPU/GPU chip instead of taking a
// chip + sparkline of its own (temperatures move slowly; a graph per sensor
// cost ~130px of island width). Reserves "99°" so the island doesn't jitter;
// hidden when the sensor is missing (temp < 0).
import QtQuick
import ".."

Label {
    property real temp: -1
    property real hot: 85
    visible: temp >= 0
    text: Math.round(temp) + "°"
    width: Math.max(implicitWidth, tm.advanceWidth)
    color: temp >= hot ? Theme.red : Theme.subtext
    size: Theme.fontSmall
    TextMetrics { id: tm; font.family: Theme.font; font.pointSize: Theme.fontSmall; text: "99°" }
}
