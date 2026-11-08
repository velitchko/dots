// SPDX-License-Identifier: GPL-3.0-or-later
// Battery icon + percent for the resting island (every perspective). Green while
// charging, red below 15%. Hidden without a laptop battery. Click: quick settings
// (battery card + power modes).
import QtQuick
import ".."
import "../services"

Chip {
    visible: Power.hasBattery
    clickable: true
    onClicked: IslandState.openPanel("control")
    icon: Power.icon
    text: Stats.pct(Power.percent)
    reserve: "100%"
    tint: Power.charging ? Theme.green : Power.percent < 0.15 ? Theme.red : Theme.subtext
}
