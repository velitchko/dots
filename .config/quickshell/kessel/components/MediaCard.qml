// SPDX-License-Identifier: GPL-3.0-or-later
// Music controller card (hover glance, quick settings):
//   cover · title / artist / wavy progress with times · prev · play · next
import QtQuick
import ".."
import "../services"

Rectangle {
    id: root
    property bool compact: false
    implicitWidth: 420
    implicitHeight: compact ? 92 : 104
    radius: Theme.radiusCard
    color: Theme.card

    Rectangle {
        id: art
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: root.implicitHeight - 24
        height: width
        radius: 12
        color: Theme.overlay
        clip: true
        Image { anchors.fill: parent; source: Media.art; fillMode: Image.PreserveAspectCrop; asynchronous: true }
        Glyph { anchors.centerIn: parent; optical: true; text: Icons.music; size: 20; color: Theme.subtext; visible: Media.art === "" }
    }

    Row {
        id: controls
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        IconButton { icon: Icons.prev; size: 30; anchors.verticalCenter: parent.verticalCenter; onClicked: Media.prev() }
        IconButton { icon: Media.playing ? Icons.pause : Icons.play; size: 38; iconSize: Theme.fontUi + 5; active: true; tint: Theme.accent
                     anchors.verticalCenter: parent.verticalCenter; onClicked: Media.toggle() }
        IconButton { icon: Icons.next; size: 30; anchors.verticalCenter: parent.verticalCenter; onClicked: Media.next() }
    }

    Column {
        anchors.left: art.right
        anchors.leftMargin: 14
        anchors.right: controls.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Label { text: Media.title; font.bold: true; width: parent.width }
        Label { text: (Media.artist || Media.identity) + (Media.album ? " · " + Media.album : ""); color: Theme.subtext; size: Theme.fontSmall; width: parent.width }
        WavyBar {
            width: parent.width
            value: Media.progress
            playing: Media.playing
            interactive: Media.player?.canSeek ?? false
            thickness: 3.5
            amplitude: 2.5
            wavelength: 18
            fill: Theme.accent
            onMoved: v => Media.seekTo(v)
        }
        Item {
            width: parent.width
            height: 12
            Label { text: Time.hms(Media.position); size: Theme.fontSmall - 1.5; color: Theme.muted }
            Label { anchors.right: parent.right; text: Media.length > 0 ? Time.hms(Media.length) : ""; size: Theme.fontSmall - 1.5; color: Theme.muted }
        }
    }
}
