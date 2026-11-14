// SPDX-License-Identifier: GPL-3.0-or-later
// A device/network list capped to a max visible height and scrollable within
// itself, instead of growing indefinitely and pushing the rest of the panel
// down (reported: long Wi-Fi/Bluetooth/audio-device lists were hard to
// scroll or see, since expanding one pushed everything else far below the
// fold of the panel's own scroll area).
import QtQuick
import ".."

ListView {
    id: root
    property int maxVisible: 5
    width: parent.width
    height: Math.min(contentHeight, maxVisible * 34)   // ListItem.qml's fixed row height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: count > 0
}
