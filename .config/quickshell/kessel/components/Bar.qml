// SPDX-License-Identifier: GPL-3.0-or-later
// Slider / progress bar. Interactive when `interactive` is true.
import QtQuick
import ".."

Item {
    id: root
    property real value: 0                 // 0..1
    property bool interactive: false
    property color fill: Theme.accent
    property real thickness: 6
    signal moved(real v)

    implicitHeight: Math.max(thickness, interactive ? 16 : thickness)
    implicitWidth: 160

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.thickness
        radius: height / 2
        color: Theme.overlay
        Rectangle {
            width: Math.max(height, track.width * Math.max(0, Math.min(1, root.value)))
            height: parent.height
            radius: parent.radius
            color: root.fill
            Behavior on width { enabled: !ma.pressed; NumberAnimation { duration: 120 } }
        }
    }
    Rectangle {
        visible: root.interactive && (ma.containsMouse || ma.pressed)
        width: 14; height: 14; radius: 7
        color: Theme.text
        anchors.verticalCenter: parent.verticalCenter
        x: track.width * Math.max(0, Math.min(1, root.value)) - width / 2
    }
    MouseArea {
        id: ma
        enabled: root.interactive
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        function emitAt(x) { root.moved(Math.max(0, Math.min(1, (x - 6) / track.width))) }
        onPressed: e => emitAt(e.x)
        onPositionChanged: e => { if (pressed) emitAt(e.x) }
        // Drag-only: scrolling over the bar used to nudge the value, which
        // fought scrolling a device list sitting right below it. No onWheel
        // handler here means the event isn't accepted and propagates to
        // whatever's underneath (e.g. the panel's own Flickable).
    }
}
