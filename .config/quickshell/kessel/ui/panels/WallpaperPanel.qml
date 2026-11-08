// SPDX-License-Identifier: GPL-3.0-or-later
// Wallpaper + theme (CTRL+SUPER+T). Accents follow the wallpaper; the base is
// pitch black (dark) or eggshell (light). Drop images into ~/Pictures/Wallpapers.
import QtQuick
import "../.."
import "../../services"
import "../../components"

PanelBase {
    id: root
    title: "Wallpaper & theme"
    icon: Icons.image
    readonly property int cols: 4
    readonly property real thumbW: 170
    readonly property real thumbH: 96
    contentWidth: cols * thumbW + (cols - 1) * 10
    contentHeight: modeRow.height + 12 + Math.min(3, Math.max(1, Math.ceil(grid.count / cols))) * (thumbH + 10)

    property int sel: 0
    Component.onCompleted: Themes.refresh()

    focus: true
    Keys.onLeftPressed:  sel = Math.max(0, sel - 1)
    Keys.onRightPressed: sel = Math.min(grid.count - 1, sel + 1)
    Keys.onUpPressed:    sel = Math.max(0, sel - cols)
    Keys.onDownPressed:  sel = Math.min(grid.count - 1, sel + cols)
    Keys.onReturnPressed: if (Themes.wallpapers[sel]) Themes.setWallpaper(Themes.wallpapers[sel])

    Row {
        id: modeRow
        spacing: 8
        Repeater {
            model: [{ m: "dark", label: "Dark · pitch black", icon: Icons.night }, { m: "light", label: "Light · eggshell", icon: Icons.sunny }]
            Rectangle {
                required property var modelData
                readonly property bool on: (modelData.m === "dark") === Themes.dark
                width: 190; height: 36; radius: 18
                color: on ? Theme.a(Theme.accent, 0.22) : (mm.containsMouse ? Theme.cardHi : Theme.card)
                border.width: on ? 1 : 0
                border.color: Theme.accent
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Glyph { text: modelData.icon; color: parent.parent.on ? Theme.accent : Theme.text; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: modelData.label; size: Theme.fontSmall + 0.5; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: mm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Themes.setMode(modelData.m) }
            }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 10
            text: Themes.busy ? "applying…" : "~/Pictures/Wallpapers"
            color: Theme.muted
            size: Theme.fontSmall
        }
    }

    GridView {
        id: grid
        anchors.top: modeRow.bottom
        anchors.topMargin: 12
        width: parent.width + 10
        height: root.contentHeight - modeRow.height - 12
        cellWidth: root.thumbW + 10
        cellHeight: root.thumbH + 10
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Themes.wallpapers
        currentIndex: root.sel
        delegate: Rectangle {
            required property string modelData
            required property int index
            readonly property bool active: modelData === Themes.current
            width: root.thumbW; height: root.thumbH
            radius: 12
            color: Theme.card
            clip: true
            border.width: active || root.sel === index ? 2 : 0
            border.color: active ? Theme.accent : Theme.a(Theme.text, 0.4)
            Image {
                anchors.fill: parent
                anchors.margins: parent.border.width
                source: Themes.thumb(modelData)
                sourceSize: Qt.size(340, 192)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Rectangle {
                visible: active
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6
                width: 22; height: 22; radius: 11
                color: Theme.accent
                Glyph { anchors.centerIn: parent; text: Icons.check; color: Theme.base; size: Theme.fontSmall }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.sel = index
                onClicked: Themes.setWallpaper(modelData)
            }
        }
    }
}
