// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import ".."
import "../services"
import "../components"

View {
    implicitWidth: IslandState.osdValue >= 0 ? 300 : 200
    implicitHeight: Theme.islandHeight + 4
    Row {
        anchors.centerIn: parent
        spacing: 12
        // Fixed-size icon slot, not the glyph's own implicit width: different
        // OSDs (volume vs. brightness vs. mic...) show different icons with
        // different natural advance widths, which otherwise changes the
        // Row's total width and visibly shifts the bar/label left or right
        // depending which icon is showing. optical: true centres the ink
        // inside that fixed slot (see Theme.iconFont's comment on this).
        Item {
            width: 28
            height: Theme.fontUi + 4
            anchors.verticalCenter: parent.verticalCenter
            Glyph { text: IslandState.osdIcon; size: Theme.fontUi + 4; optical: true; anchors.centerIn: parent }
        }
        Bar { visible: IslandState.osdValue >= 0; width: 170; value: IslandState.osdValue; anchors.verticalCenter: parent.verticalCenter }
        // Fixed width for the same reason as the icon slot (labels range from
        // "73%" to "Floating" without resizing the row) -- centred within it,
        // not left-aligned, so short labels don't look stranded against a
        // slab of empty space before the next pill.
        Label { text: IslandState.osdLabel; width: 64; horizontalAlignment: Text.AlignHCenter; size: Theme.fontSmall; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
    }
}
