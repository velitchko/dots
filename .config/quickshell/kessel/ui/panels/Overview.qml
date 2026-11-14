// SPDX-License-Identifier: GPL-3.0-or-later
// Overview (SUPER+Tab): every workspace with live window previews.
// Click a window to focus it, click a workspace to go there, drag a window
// onto another workspace to move it. ←/→/↑/↓ + Enter work too.
import QtQuick
import Quickshell.Widgets
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../.."
import "../../services"
import "../../components"

PanelBase {
    id: root
    title: "Overview"
    icon: Icons.overview

    readonly property var mon: Hyprland.focusedMonitor
    readonly property real monW: mon ? mon.width / mon.scale : 1920
    readonly property real monH: mon ? mon.height / mon.scale : 1080
    readonly property int cols: 5
    readonly property int count: Math.max(Hypr.maxId, 5)
    readonly property real cardW: 168
    readonly property real cardH: cardW * monH / monW
    readonly property real k: cardW / monW            // logical px → preview px (focused monitor)

    // Window coordinates are global (all monitors side by side), so each card must
    // be mapped through the monitor *its* workspace lives on, not the focused one --
    // otherwise windows on the other monitors land outside their card and get clipped.
    // Rotated outputs (transform 1/3/5/7) swap width and height.
    function geomOf(m) {
        if (!m) return { x: 0, y: 0, w: monW, h: monH }
        const s = m.scale > 0 ? m.scale : 1
        const rot = (m.lastIpcObject?.transform ?? 0) % 2 === 1
        const w = (rot ? m.height : m.width) / s, h = (rot ? m.width : m.height) / s
        return { x: m.x, y: m.y, w: w, h: h }
    }

    contentWidth: cols * cardW + (cols - 1) * 10
    contentHeight: Math.ceil(count / cols) * (cardH + 26) + (Math.ceil(count / cols) - 1) * 10

    property int sel: Hypr.focusedId - 1
    property var dragging: null

    Component.onCompleted: { Hyprland.refreshToplevels(); Hyprland.refreshMonitors() }

    focus: true
    Keys.onLeftPressed:  sel = (sel + count - 1) % count
    Keys.onRightPressed: sel = (sel + 1) % count
    Keys.onUpPressed:    sel = (sel - cols + count) % count
    Keys.onDownPressed:  sel = (sel + cols) % count
    Keys.onReturnPressed: { const id = sel + 1; Hypr.afterPanel(() => Hypr.focus(id)) }

    Grid {
        columns: root.cols
        spacing: 10
        Repeater {
            model: root.count
            Column {
                id: ws
                required property int index
                readonly property int wsId: index + 1
                readonly property var wins: Hypr.windowsOn(wsId)
                // This workspace's own monitor (falls back to the focused one for
                // workspaces that don't exist yet -- they have no windows anyway),
                // fitted into the card without distortion and centred.
                readonly property var g: root.geomOf(Hypr.workspaces.find(w => w.id === wsId)?.monitor ?? root.mon)
                readonly property real wk: Math.min(root.cardW / g.w, root.cardH / g.h)
                readonly property real ox: (root.cardW - g.w * wk) / 2
                readonly property real oy: (root.cardH - g.h * wk) / 2
                spacing: 4

                Rectangle {
                    id: card
                    width: root.cardW
                    height: root.cardH
                    radius: 10
                    color: drop.containsDrag ? Theme.a(Theme.accent, 0.18) : Theme.card
                    // border drawn by an overlay above the window previews (below)
                    readonly property real borderW: root.sel === ws.index || Hypr.focusedId === ws.wsId ? Theme.borderWidth * 2 : Theme.borderWidth
                    readonly property color borderC: root.sel === ws.index ? Theme.accent
                        : Hypr.focusedId === ws.wsId ? Theme.a(Theme.accent, 0.5) : Theme.a(Theme.text, 0.06)

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.sel = ws.index
                        onClicked: { const id = ws.wsId; Hypr.afterPanel(() => Hypr.focus(id)) }
                    }
                    DropArea {
                        id: drop
                        anchors.fill: parent
                        onDropped: if (root.dragging) { Hypr.moveWindowTo(root.dragging, ws.wsId); root.dragging = null }
                    }

                    // Windows are cropped to the card's rounded shape: clip: true only
                    // cuts square, so tiled windows (which fill the card) stuck out of
                    // its corners. The border is drawn on top, after them.
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: card.radius
                        color: "transparent"
                        Repeater {
                            model: ws.wins
                            Rectangle {
                                id: win
                                required property var modelData
                                readonly property var ipc: modelData.lastIpcObject
                                x: ws.ox + ((ipc?.at?.[0] ?? 0) - ws.g.x) * ws.wk
                                y: ws.oy + ((ipc?.at?.[1] ?? 0) - ws.g.y) * ws.wk
                                width: Math.max(12, (ipc?.size?.[0] ?? 100) * ws.wk)
                                height: Math.max(10, (ipc?.size?.[1] ?? 80) * ws.wk)
                                radius: 4
                                color: Theme.overlay
                                border.width: wma.containsMouse ? Theme.borderWidth : 0
                                border.color: Theme.accent
                                Drag.active: wma.drag.active
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2

                                // live preview with rounded corners (clip: true only cuts square)
                                ClippingRectangle {
                                    anchors.fill: parent
                                    anchors.margins: parent.border.width
                                    radius: Math.max(0, parent.radius - parent.border.width)
                                    color: "transparent"
                                    ScreencopyView {
                                        anchors.fill: parent
                                        captureSource: win.modelData.wayland
                                        live: true
                                        paintCursor: false
                                    }
                                }
                                Image {
                                    anchors.centerIn: parent
                                    width: Math.min(24, parent.width * 0.5)
                                    height: width
                                    sourceSize: Qt.size(48, 48)
                                    source: Quickshell.iconPath((win.ipc?.class ?? "").toLowerCase(), true)
                                    opacity: 0.85
                                }
                                MouseArea {
                                    id: wma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    drag.target: win
                                    onPressed: root.dragging = win.modelData
                                    onReleased: {
                                        const moved = win.Drag.target !== null
                                        win.Drag.drop()
                                        if (!moved) { const t = win.modelData; Hypr.afterPanel(() => Hypr.focusWindow(t)) }
                                        else IslandState.closePanel()
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: card.radius
                        color: "transparent"
                        border.width: card.borderW
                        border.color: card.borderC
                    }
                }
                Row {
                    spacing: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    Label { text: ws.wsId; font.bold: Hypr.focusedId === ws.wsId; color: Hypr.focusedId === ws.wsId ? Theme.accent : Theme.subtext; size: Theme.fontSmall }
                    Label { text: ws.wins.length > 0 ? "· " + ws.wins.length : ""; color: Theme.muted; size: Theme.fontSmall }
                }
            }
        }
    }
}
