// SPDX-License-Identifier: GPL-3.0-or-later
// Resting island. Shows one "perspective" (Overview · Time · Music · Metrics · Minimal);
// scroll over the island to rotate between them. Music appears while a player
// exists and is entered automatically when playback starts.
import QtQuick
import QtQuick.Shapes
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

    // music progress, traced along the pill's own rounded-cap curve (not a
    // straight bar starting at a tangent point) so it visually wraps the cap
    // the way the pill itself is shaped, instead of cutting across it.
    // Path: a quarter-circle lead-in through the left cap, a flat run along
    // the bottom edge, a mirrored quarter-circle through the right cap —
    // all offset `inset` px inward (same technique as the straight version's
    // margin, generalized to the whole curve instead of one point on it).
    // Media.progress selects how far along that combined path to draw.
    QtObject {
        id: progressGeo
        readonly property int inset: 2
        readonly property int arcSteps: 6   // points per quarter-circle
        // A run of many identical trailing points (tried so the polyline's
        // length would never change frame to frame) turned out to break
        // GeometryRenderer's stroke entirely -- likely a degenerate join at
        // a zero-length segment -- rather than just render differently.
        // Back to a naturally-truncated point list that stops exactly at
        // the current progress; only the renderer-type fix is kept.
        function build(w, h, progress) {
            const r = h / 2, reff = r - inset
            const cy = h / 2
            const arcLen = reff * Math.PI / 2, flatLen = Math.max(0, w - 2 * r)
            const total = 2 * arcLen + flatLen
            const target = Math.max(0, Math.min(1, progress)) * total
            const pts = []
            // left cap: sweep 270° (bottom of arc) → 180° (leftmost point)
            for (let i = 0; i <= arcSteps; i++) {
                const len = i / arcSteps * arcLen
                if (len > target) break
                const t = (270 - 90 * i / arcSteps) * Math.PI / 180
                pts.push(Qt.point(r + reff * Math.cos(t), cy + reff * Math.sin(t)))
            }
            if (target <= arcLen) {
                const t = (270 - 90 * target / arcLen) * Math.PI / 180
                pts.push(Qt.point(r + reff * Math.cos(t), cy + reff * Math.sin(t)))
                return pts
            }
            // flat run along the bottom edge
            const flatTarget = Math.min(flatLen, target - arcLen)
            pts.push(Qt.point(r, h - inset), Qt.point(r + flatTarget, h - inset))
            if (target <= arcLen + flatLen) return pts
            // right cap: sweep 270° → 360°(0°), mirroring the left cap
            const rightTarget = target - arcLen - flatLen
            for (let i = 0; i <= arcSteps; i++) {
                const len = i / arcSteps * arcLen
                if (len > rightTarget) break
                const t = (270 + 90 * i / arcSteps) * Math.PI / 180
                pts.push(Qt.point(w - r + reff * Math.cos(t), cy + reff * Math.sin(t)))
            }
            const t = (270 + 90 * rightTarget / arcLen) * Math.PI / 180
            pts.push(Qt.point(w - r + reff * Math.cos(t), cy + reff * Math.sin(t)))
            return pts
        }
    }
    Shape {
        anchors.fill: parent
        visible: root.cur === music && Media.length > 0
        // A polyline of straight segments, not true bezier curves: the
        // GeometryRenderer default is the right (and more stable) fit, not
        // CurveRenderer (meant for smooth curve primitives like PathArc/Cubic).
        property real animatedProgress: Media.progress
        Behavior on animatedProgress { NumberAnimation { duration: 900 } }
        ShapePath {
            strokeWidth: 2
            strokeColor: Theme.accent
            fillColor: "transparent"
            capStyle: Qt.RoundCap
            PathPolyline { path: progressGeo.build(parent.parent.width, parent.parent.height, parent.parent.animatedProgress) }
        }
    }
}
