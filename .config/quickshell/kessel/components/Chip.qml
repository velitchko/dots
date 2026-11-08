// SPDX-License-Identifier: GPL-3.0-or-later
// Glyph + small label used in the resting island; optionally clickable.
import QtQuick
import ".."

Item {
    id: chip
    signal clicked()
    property bool clickable: false
    property string icon: ""
    property string text: ""
    property color tint: Theme.subtext
    property color textColor: Theme.text
    // Widest expected text (e.g. "100%"): the label keeps at least that width,
    // left-aligned, so changing numbers don't shift the island.
    property string reserve: ""

    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(row.implicitHeight, 20)

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5
        Glyph { text: chip.icon; color: chip.tint; size: Theme.fontUi + 1; optical: true; anchors.verticalCenter: parent.verticalCenter }
        Label { text: chip.text; width: Math.max(implicitWidth, chip.reserve !== "" ? reserveTm.advanceWidth : 0); horizontalAlignment: Text.AlignLeft; color: chip.textColor; size: Theme.fontSmall + 0.5; visible: text !== ""; anchors.verticalCenter: parent.verticalCenter }
    }
    TextMetrics { id: reserveTm; font.family: Theme.font; font.pointSize: Theme.fontSmall + 0.5; text: chip.reserve }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        enabled: chip.clickable
        visible: chip.clickable
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
