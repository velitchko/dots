// SPDX-License-Identifier: GPL-3.0-or-later
// A quick-settings row: icon, title/subtitle, optional switch, optional expander.
import QtQuick
import ".."

Rectangle {
    id: root
    property string icon: ""
    property string title: ""
    property string sub: ""
    property bool showSwitch: false
    property bool checked: false
    property bool expandable: false
    property bool expanded: false
    // header click without an expander (e.g. "restart to fix")
    property bool clickable: false
    property color tint: Theme.accent
    default property alias content: inner.data
    signal toggled()
    signal clicked()

    implicitWidth: 360
    implicitHeight: head.height + (expanded ? inner.childrenRect.height + 10 : 0)
    radius: Theme.radiusCard
    color: Theme.card
    clip: true
    Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    Item {
        id: head
        width: parent.width
        height: Math.max(48, texts.implicitHeight + 16)
        Rectangle {
            id: ic
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 15
            color: root.checked ? Theme.a(root.tint, 0.2) : Theme.overlay
            Glyph { anchors.centerIn: parent; optical: true; text: root.icon; color: root.checked ? root.tint : Theme.text; size: Theme.fontUi + 2 }
        }
        Column {
            id: texts
            anchors.left: ic.right
            anchors.leftMargin: 10
            anchors.right: tail.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            Label { text: root.title; width: parent.width; font.bold: true; size: Theme.fontSmall + 1 }
            // up to two lines: setup hints ("sudo systemctl enable …") must stay readable
            Label { text: root.sub; visible: text !== ""; width: parent.width; color: Theme.subtext; size: Theme.fontSmall - 0.5
                    wrapMode: Text.Wrap; maximumLineCount: 2 }
        }
        Row {
            id: tail
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Switch { visible: root.showSwitch; checked: root.checked; anchors.verticalCenter: parent.verticalCenter; onToggled: root.toggled() }
            Glyph {
                visible: root.expandable
                text: Icons.chevronR
                rotation: root.expanded ? 90 : 0
                color: Theme.subtext
                anchors.verticalCenter: parent.verticalCenter
                Behavior on rotation { NumberAnimation { duration: 160 } }
                MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: root.expanded = !root.expanded }
            }
        }
        MouseArea {
            anchors.left: parent.left
            anchors.right: tail.left
            height: parent.height
            enabled: root.expandable || root.clickable
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expandable ? root.expanded = !root.expanded : root.clicked()
        }
    }
    Item {
        id: inner
        anchors.top: head.bottom
        x: 10
        width: parent.width - 20
        height: childrenRect.height
        visible: root.expanded
    }
}
