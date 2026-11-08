// SPDX-License-Identifier: GPL-3.0-or-later
// Nerd Font glyph. With `optical: true` the visible ink (not the font's line
// box) is centred on the item — use it for icons inside circles.
import QtQuick
import ".."

Text {
    id: root
    property real size: Theme.fontUi + 3
    property bool optical: false
    font.family: Theme.iconFont
    font.pointSize: size
    color: Theme.text
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter

    TextMetrics { id: tm; font: root.font; text: root.text }
    FontMetrics { id: fm; font: root.font }
    // offset between the ink's centre and the item's centre (layout is unaffected)
    transform: Translate {
        x: root.optical ? (tm.advanceWidth / 2 - (tm.tightBoundingRect.x + tm.tightBoundingRect.width / 2)) : 0
        y: root.optical ? (root.implicitHeight / 2 - (fm.ascent + tm.tightBoundingRect.y + tm.tightBoundingRect.height / 2)) : 0
    }
}
