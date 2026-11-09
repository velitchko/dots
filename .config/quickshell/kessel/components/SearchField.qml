// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import ".."

Rectangle {
    id: root
    property alias text: input.text
    property string placeholder: "Search"
    property string icon: Icons.search
    property alias input: input
    signal accepted()
    signal up()
    signal down()

    implicitHeight: 40
    radius: 12
    color: Theme.card
    border.width: Theme.borderWidth
    border.color: input.activeFocus ? Theme.a(Theme.accent, 0.6) : "transparent"

    Glyph { id: ic; text: root.icon; color: Theme.subtext; anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter }
    TextInput {
        id: input
        anchors.left: ic.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.text
        selectionColor: Theme.a(Theme.accent, 0.4)
        font.family: Theme.font
        font.pointSize: Theme.fontUi + 1
        clip: true
        focus: true
        Keys.onReturnPressed: root.accepted()
        Keys.onEnterPressed: root.accepted()
        Keys.onUpPressed: root.up()
        Keys.onDownPressed: root.down()
        Text {
            visible: input.text === ""
            text: root.placeholder
            color: Theme.muted
            font: input.font
        }
    }
    function focusInput() { input.forceActiveFocus() }
}
