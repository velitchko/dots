// SPDX-License-Identifier: GPL-3.0-or-later
// Base for island views: cross-fades in/out and is anchored at the top centre.
import QtQuick
import ".."

Item {
    property bool shown: false
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.94
    transformOrigin: Item.Top
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.OutCubic } }
    // Same spring as the pill's own width/height (Island.qml): content used to grow
    // into shape faster and with less bounce than the capsule resizing around it, so
    // it looked like the new view popped in and the capsule caught up afterward,
    // rather than one morph. Matching the constants makes the two arrive together.
    Behavior on scale { SpringAnimation { spring: Theme.springStiffness; damping: Theme.springDamping; mass: Theme.springMass; epsilon: 0.002 } }
}
