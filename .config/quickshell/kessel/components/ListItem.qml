// SPDX-License-Identifier: GPL-3.0-or-later
// Selectable row used in device / network lists.
import QtQuick
import ".."

Rectangle {
    id: root
    property string icon: ""
    property string text: ""
    property string sub: ""
    property bool selected: false
    property bool busy: false
    // optional trailing button (e.g. forget a network / device)
    property string action: ""
    signal clicked()
    signal actionClicked()
    width: parent ? parent.width : 300
    height: 34
    radius: 9
    color: ma.containsMouse ? Theme.cardHi : "transparent"
    // fixed slot: Propo icons have their real widths, labels must still line up
    Glyph { id: ic; x: 6; width: 22; text: root.icon; visible: text !== ""; color: root.selected ? Theme.accent : Theme.subtext; optical: true; anchors.verticalCenter: parent.verticalCenter; size: Theme.fontUi + 1 }
    Label {
        anchors.left: ic.visible ? ic.right : parent.left
        anchors.leftMargin: ic.visible ? 8 : 10
        anchors.right: right.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: root.selected ? Theme.accent : Theme.text
        size: Theme.fontSmall + 0.5
    }
    Row {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Label { text: root.busy ? "…" : root.sub; color: Theme.subtext; size: Theme.fontSmall - 0.5; anchors.verticalCenter: parent.verticalCenter }
        Glyph { visible: root.selected; text: Icons.check; color: Theme.accent; size: Theme.fontSmall + 1; optical: true; anchors.verticalCenter: parent.verticalCenter }
        Item { width: root.action !== "" ? 24 : 0; height: 24; anchors.verticalCenter: parent.verticalCenter }   // room for the action button
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
    // after the row's MouseArea, so it takes its own clicks
    IconButton {
        id: act
        visible: root.action !== "" && (ma.containsMouse || hovered)
        readonly property bool hovered: actHover.hovered
        HoverHandler { id: actHover }
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        size: 24
        iconSize: Theme.fontSmall + 1
        icon: root.action
        onClicked: root.actionClicked()
    }
}
