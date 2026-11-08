// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string icon: ""
    property bool toggled: false
    property color tint: Style.accent
    property color iconColor: toggled ? Style.onAccent : Style.subtext
    signal clicked()
    Layout.preferredWidth: 38
    Layout.preferredHeight: 38
    Layout.alignment: Qt.AlignVCenter
    radius: 19
    color: toggled ? tint : (ma.containsMouse ? Style.toolbarHi : "transparent")
    opacity: enabled ? 1 : 0.5
    Behavior on color { ColorAnimation { duration: 150 } }
    Text {
        anchors.centerIn: parent
        text: root.icon
        font.family: Style.iconFont
        font.pixelSize: 20
        color: root.iconColor
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
