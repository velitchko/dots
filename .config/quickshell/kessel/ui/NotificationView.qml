// SPDX-License-Identifier: GPL-3.0-or-later
// A notification pops the island open with its card; hover holds it.
import QtQuick
import ".."
import "../services"
import "../components"

View {
    // Fixed, not tied to the resting perspective's width: that made the
    // popup stretch to whatever perspective happened to be active (band-wide
    // under Time, cramped under Minimal) instead of a size of its own.
    implicitWidth: 520
    implicitHeight: Notifs.popup ? card.implicitHeight + 16 : Theme.islandHeight
    NotificationCard {
        id: card
        visible: Notifs.popup !== null
        notif: Notifs.popup
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(560, parent.implicitWidth - 16)
    }
}
