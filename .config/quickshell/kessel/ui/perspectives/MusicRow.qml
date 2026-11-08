// SPDX-License-Identifier: GPL-3.0-or-later
// Music perspective: spinning record (art as its label) · scrolling title/artist · cava visualizer ·
// time left · play/pause; a progress line runs along the pill's bottom edge
// (drawn by RestView). Bars rest as a dot row when paused (dot-matrix idle).
import QtQuick
import Quickshell
import Quickshell.Widgets
import "../.."
import "../../services"
import "../../components"

Item {
    id: root
    property bool active: false
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.islandHeight

    // the visualizer only runs while this perspective is on screen and playing
    Binding { target: Cava; property: "wanted"; value: root.active && Media.playing }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        // A small vinyl record: dark disc with faint grooves, the album art as a
        // round centre label, a spindle hole. Only the record spins (the square
        // art used to rotate, because clip cuts to the rectangle, not the circle).
        Item {
            id: art
            width: 26; height: 26
            anchors.verticalCenter: parent.verticalCenter
            Item {
                id: disc
                anchors.fill: parent
                // vinyl stays dark in both modes; a touch lighter than the pitch-black pill
                Rectangle { anchors.fill: parent; radius: width / 2; color: "#1c1c1c"; border.width: 1; border.color: Theme.a(Theme.text, 0.16) }
                // grooves
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        anchors.centerIn: parent
                        width: disc.width - 5 - index * 4; height: width; radius: width / 2
                        color: "transparent"
                        border.width: 0.6
                        border.color: Qt.rgba(1, 1, 1, 0.09)
                    }
                }
                // a sheen across the grooves makes the rotation visible on a plain disc
                Rectangle {
                    anchors.centerIn: parent
                    width: disc.width - 4; height: 1.2; radius: 0.6
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0;  color: "transparent" }
                        GradientStop { position: 0.3;  color: Qt.rgba(1, 1, 1, 0.12) }
                        GradientStop { position: 0.42; color: "transparent" }
                        GradientStop { position: 0.58; color: "transparent" }
                        GradientStop { position: 0.7;  color: Qt.rgba(1, 1, 1, 0.12) }
                        GradientStop { position: 1.0;  color: "transparent" }
                    }
                }
                // label: accent paper, album art on top clipped to a circle
                Rectangle { anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: Theme.accent }
                ClippingRectangle {
                    anchors.centerIn: parent
                    width: 12; height: 12; radius: 6
                    color: "transparent"
                    Image { anchors.fill: parent; source: Media.art; sourceSize: Qt.size(48, 48); fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: status === Image.Ready }
                }
                // spindle hole
                Rectangle { anchors.centerIn: parent; width: 2.5; height: 2.5; radius: 1.25; color: "#1c1c1c" }
                // 33⅓ rpm would be a blur at this size: one calm turn every 6 s; holds its angle on pause
                RotationAnimation on rotation { running: Media.playing; from: 0; to: 360; duration: 6000; loops: Animation.Infinite }
            }
        }

        // marquee: scrolls when "title — artist" is wider than its box
        Item {
            id: marquee
            width: 180
            height: Theme.islandHeight
            clip: true
            anchors.verticalCenter: parent.verticalCenter
            readonly property string full: Media.title + (Media.artist ? "  ·  " + Media.artist : "")
            Label {
                id: mtext
                y: (parent.height - height) / 2
                text: marquee.full + (overflow ? "        " + marquee.full : "")
                readonly property bool overflow: tm.advanceWidth > marquee.width
                size: Theme.fontSmall + 0.5
                elide: Text.ElideNone
                TextMetrics { id: tm; font: mtext.font; text: marquee.full }
                NumberAnimation on x {
                    running: mtext.overflow && root.active
                    from: 0; to: -(tm.advanceWidth + tm.font.pointSize * 6)
                    duration: Math.max(6000, tm.advanceWidth * 28)
                    loops: Animation.Infinite
                }
                onOverflowChanged: if (!overflow) x = 0
            }
        }

        // visualizer
        Row {
            id: viz
            spacing: 2
            height: 22
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: Cava.bars
                Rectangle {
                    required property int index
                    readonly property real v: Media.playing ? (Cava.values[index] ?? 0) : 0
                    width: 3
                    height: Math.max(3, v * viz.height)
                    radius: 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.rgba(Theme.accent.r + (Theme.accent3.r - Theme.accent.r) * index / Cava.bars,
                                   Theme.accent.g + (Theme.accent3.g - Theme.accent.g) * index / Cava.bars,
                                   Theme.accent.b + (Theme.accent3.b - Theme.accent.b) * index / Cava.bars, 1)
                    opacity: Media.playing ? 0.55 + 0.45 * v : 0.35
                    Behavior on height { NumberAnimation { duration: 60 } }
                }
            }
        }

        Label {
            width: 46
            horizontalAlignment: Text.AlignRight
            text: Media.length > 0 ? "-" + Time.hms(Media.length - Media.position) : ""
            color: Theme.subtext
            size: Theme.fontSmall
            anchors.verticalCenter: parent.verticalCenter
        }
        IconButton {
            icon: Media.playing ? Icons.pause : Icons.play
            size: 26
            iconSize: Theme.fontUi
            onClicked: Media.toggle()
            anchors.verticalCenter: parent.verticalCenter
        }
        BatteryChip { anchors.verticalCenter: parent.verticalCenter }
    }
}
