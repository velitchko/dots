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

    // music progress: a real rounded Rectangle shaped exactly like the pill
    // itself (same radius formula), a few px larger all round, revealed
    // left-to-right by plain clipping instead of traced/hand-computed arc
    // geometry -- the earlier Shape/ShapePath version kept hitting
    // QtQuick.Shapes renderer edge cases (a stray line, then invisible
    // rendering). The reveal naturally follows the real curve because the
    // revealed shape genuinely has that curve; no trigonometry needed.
    Item {
        id: progressReveal
        readonly property int glow: 3   // halo thickness, and how far it sits outside the pill
        visible: root.cur === music && Media.length > 0
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: -glow
        anchors.topMargin: -glow
        property real animatedProgress: Media.progress
        Behavior on animatedProgress { NumberAnimation { duration: 900 } }
        width: (root.width + 2 * glow) * animatedProgress
        height: root.height + 2 * glow
        clip: true
        Rectangle {
            width: root.width + 2 * progressReveal.glow
            height: root.height + 2 * progressReveal.glow
            radius: height / 2
            color: "transparent"
            border.width: progressReveal.glow
            border.color: Theme.accent
        }
    }
}
