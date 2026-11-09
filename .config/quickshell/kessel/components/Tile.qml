// SPDX-License-Identifier: GPL-3.0-or-later
// Quick-settings tile: icon + label, toggles or triggers.
import QtQuick
import ".."

Rectangle {
    id: root
    property string icon: ""
    property string label: ""
    property string sub: ""
    property bool active: false
    property color tint: Theme.accent
    signal clicked()

    implicitWidth: 108
    implicitHeight: 58
    radius: Theme.radiusCard
    color: active ? Theme.a(tint, 0.2) : (ma.containsMouse ? Theme.cardHi : Theme.card)
    border.width: active ? Theme.borderWidth : 0
    border.color: Theme.a(tint, 0.6)
    Behavior on color { ColorAnimation { duration: Theme.fadeMs } }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Glyph { text: root.icon; color: root.active ? root.tint : Theme.text; size: Theme.fontUi + 4; optical: true }
        Label { text: root.label; size: Theme.fontSmall; color: Theme.text; width: root.width - 20 }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
