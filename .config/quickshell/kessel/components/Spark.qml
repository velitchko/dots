// SPDX-License-Identifier: GPL-3.0-or-later
// Tiny bar sparkline (values normalised to the max, or 0..1 if `max` is set).
// Backed by an incrementally-synced ListModel so existing bars translate
// into place as new samples arrive. A plain Repeater re-evaluates every
// bar's value by index each tick (the whole window shifts under fixed
// slots), which reads as the chart popping/redrawing all at once; here each
// sample keeps a stable delegate that only moves, so just the newest bar
// animates in while the rest slide.
import QtQuick
import ".."

Item {
    id: root
    property var values: []
    property real max: 0               // 0 = auto
    property color tint: Theme.accent
    property real barWidth: 2
    property real spacing: 1
    property int count: 24
    implicitWidth: count * (barWidth + spacing) - spacing
    height: 16

    readonly property var shown: values.slice(-count)
    readonly property real peak: max > 0 ? max : Math.max(1e-6, ...shown, 1e-6)

    ListModel { id: histModel }

    function sync() {
        const arr = root.shown
        if (histModel.count === 0) {
            for (const x of arr) histModel.append({ v: x })
        } else if (arr.length === histModel.count) {
            histModel.append({ v: arr[arr.length - 1] })
            histModel.remove(0)
        } else if (arr.length > histModel.count) {
            histModel.append({ v: arr[arr.length - 1] })
        } else {
            histModel.clear()
            for (const x of arr) histModel.append({ v: x })
        }
    }
    onShownChanged: sync()
    Component.onCompleted: sync()

    ListView {
        anchors.fill: parent
        orientation: ListView.Horizontal
        interactive: false
        spacing: root.spacing
        model: histModel
        add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic } }
        displaced: Transition { NumberAnimation { property: "x"; duration: 300; easing.type: Easing.OutCubic } }
        delegate: Item {
            required property real v
            width: root.barWidth
            height: root.height
            readonly property real norm: Math.min(1, v / root.peak)
            Rectangle {
                width: root.barWidth
                height: Math.max(1.5, norm * root.height)
                radius: 1
                anchors.bottom: parent.bottom
                color: root.tint
                Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }
    }
}
