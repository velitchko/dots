// SPDX-License-Identifier: GPL-3.0-or-later
// Round button that floats beside the island (gear / bell), same material as the pill.
import QtQuick
import ".."

Rectangle {
    id: root
    property string icon: ""
    property bool active: false
    property int badge: 0
    property color tint: Theme.accent
    signal clicked()

    width: Theme.islandHeight
    height: Theme.islandHeight
    radius: height / 2
    // Opaque like the pill: tints are mixed into the island colour, never see-through.
    color: active ? Qt.tint(Theme.island, Theme.a(tint, 0.25)) : (ma.containsMouse ? Qt.tint(Theme.island, Theme.a(Theme.text, 0.08)) : Theme.island)
    border.width: Theme.borderWidth
    // Same stroke width as the rest of the shell (Theme.borderWidth) -- a
    // pending badge gets a tinted ring too, so it's visible at a glance
    // without reading the number, not just when active/hovered.
    border.color: active ? Theme.a(tint, 0.7)
        : badge > 0 ? Theme.a(tint, 0.5)
        : Theme.a(Theme.text, ma.containsMouse ? 0.14 : 0.06)
    Behavior on border.color { ColorAnimation { duration: Theme.fadeMs } }
    Behavior on color { ColorAnimation { duration: Theme.fadeMs } }

    Glyph {
        anchors.centerIn: parent
        text: root.icon
        size: Theme.fontUi + 3
        optical: true
        color: root.active ? root.tint : Theme.text
    }
    // count badge
    Rectangle {
        visible: root.badge > 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -3
        anchors.bottomMargin: -3
        width: Math.max(16, badgeText.implicitWidth + 8)
        height: 16
        radius: 8
        color: Theme.accent
        Label { id: badgeText; anchors.centerIn: parent; text: root.badge > 99 ? "99+" : root.badge; size: Theme.fontSmall - 2; font.bold: true; color: Theme.base }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
