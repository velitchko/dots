// SPDX-License-Identifier: GPL-3.0-or-later
// Small tooltip shown under its parent.
import QtQuick
import ".."

Rectangle {
    property alias text: label.text
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height + 6
    width: label.implicitWidth + 16
    height: label.implicitHeight + 8
    radius: 8
    color: Theme.island
    border.width: Theme.borderWidth
    border.color: Theme.a(Theme.text, 0.12)
    z: 50
    Label { id: label; anchors.centerIn: parent; size: Theme.fontSmall - 0.5 }
}
