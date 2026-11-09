// SPDX-License-Identifier: GPL-3.0-or-later
// Resting island. Shows one "perspective" (Overview · Time · Music · Metrics · Minimal);
// scroll over the island to rotate between them. Music appears while a player
// exists and is entered automatically when playback starts.
import QtQuick
import Quickshell
import ".."
import "../services"
import "../components"
import "perspectives"

View {
    id: root
    readonly property Item cur: Perspectives.current === "music" ? music
        : Perspectives.current === "system" ? system
        : Perspectives.current === "minimal" ? minimal
        : Perspectives.current === "time" ? timeRow
        : overview
    implicitWidth: cur.implicitWidth + 32
    implicitHeight: Theme.islandHeight
    onImplicitWidthChanged: IslandState.restWidth = implicitWidth
    Component.onCompleted: IslandState.restWidth = implicitWidth

    // Click anywhere that isn't a control → quick settings.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: IslandState.openPanel("control")
    }
    // Scrolling (wheel or touchpad) is handled by Island.qml for the whole pill.

    component Slot: Item {
        property bool on: false
        anchors.centerIn: parent
        opacity: on ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Theme.fadeMs } }
    }
    Slot { on: root.cur === overview; implicitWidth: overview.implicitWidth; implicitHeight: overview.implicitHeight; width: implicitWidth; height: implicitHeight
           OverviewRow { id: overview } }
    Slot { on: root.cur === music; width: music.implicitWidth; height: music.implicitHeight
           MusicRow { id: music; active: root.cur === music && root.shown } }
    Slot { on: root.cur === system; width: system.implicitWidth; height: system.implicitHeight
           SystemRow { id: system } }
    Slot { on: root.cur === timeRow; width: timeRow.implicitWidth; height: timeRow.implicitHeight
           TimeRow { id: timeRow } }
    Slot { on: root.cur === minimal; width: minimal.implicitWidth; height: minimal.implicitHeight
           MinimalRow { id: minimal } }

    // music progress along the bottom edge of the pill. leftMargin starts the
    // bar partway through the pill's rounded cap (half its inset at this
    // height: cap radius 22.5, bar center 19.5px from mid-height → curve ends
    // at inset ≈11.3px, halved ≈6) instead of past it, so it reads as flowing
    // out of the curve rather than appearing cut off at the flat edge.
    Rectangle {
        visible: root.cur === music && Media.length > 0
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 6
        anchors.bottomMargin: 2
        height: 2
        radius: 1
        width: (parent.width - 12) * Media.progress
        color: Theme.accent
        Behavior on width { NumberAnimation { duration: 900 } }
    }
}
