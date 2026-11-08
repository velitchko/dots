// SPDX-License-Identifier: GPL-3.0-or-later
// Tiny wallpaper previews (~/Pictures/Wallpapers first); click to apply.
// Scroll horizontally; the last button opens the full picker.
import QtQuick
import Quickshell.Widgets
import ".."
import "../services"

Rectangle {
    id: root
    implicitWidth: 374
    implicitHeight: 64
    radius: Theme.radiusCard
    color: Theme.card
    Component.onCompleted: Themes.refresh()

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: 8
        anchors.rightMargin: 44
        orientation: ListView.Horizontal
        spacing: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Themes.wallpapers
        delegate: Rectangle {
            required property string modelData
            readonly property bool active: modelData === Themes.current
            width: 84; height: 48
            radius: 8
            color: Theme.overlay
            border.width: active ? 2 : (ma.containsMouse ? 1 : 0)
            border.color: active ? Theme.accent : Theme.a(Theme.text, 0.4)
            // clip: true only cuts square, so the picture sat on the rounded frame
            // with sharp corners. ClippingRectangle rounds it, just inside the border.
            ClippingRectangle {
                id: thumb
                anchors.fill: parent
                anchors.margins: parent.border.width
                radius: Math.max(0, parent.radius - parent.border.width)
                color: "transparent"
                Image {
                    anchors.fill: parent
                    source: Themes.thumb(thumb.parent.modelData)
                    sourceSize: Qt.size(168, 96)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Themes.setWallpaper(parent.modelData) }
        }
        WheelHandler { onWheel: e => list.flick(e.angleDelta.y * 8, 0) }
    }
    IconButton {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        icon: Icons.chevronR
        size: 30
        onClicked: IslandState.openPanel("wallpaper")
    }
}
