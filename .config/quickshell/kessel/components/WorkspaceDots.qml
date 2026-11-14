// SPDX-License-Identifier: GPL-3.0-or-later
// Workspace dots (1..Hypr.maxId), shown at the start of every resting perspective
// so they never disappear when the island auto-switches (e.g. to Music on playback).
// Focused = wide accent pill, occupied = subtext, empty = overlay. Click to focus.
import QtQuick
import ".."
import "../services"

Row {
    id: root
    spacing: 5
    // Keep the dots on screen while the pointer is on them (no glance).
    HoverHandler { margin: 8; onHoveredChanged: IslandState.holdRest = hovered }
    Repeater {
        model: Hypr.maxId
        Rectangle {
            required property int index
            readonly property int wsId: index + 1
            readonly property bool focused: Hypr.focusedId === wsId
            readonly property bool used: Hypr.occupied(wsId)
            anchors.verticalCenter: parent.verticalCenter
            width: focused ? 18 : 7
            height: 7
            radius: 3.5
            color: focused ? Theme.accent : used ? Theme.subtext : Theme.overlay
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 200 } }
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: Hypr.focus(parent.wsId) }
        }
    }
}
