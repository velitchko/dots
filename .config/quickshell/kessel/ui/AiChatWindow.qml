// SPDX-License-Identifier: GPL-3.0-or-later
// Floating AI chat window. A plain QtQuick.Window (not PanelWindow/layer-shell)
// so Hyprland treats it like any other floating app window -- draggable,
// resizable, alt-tabbable (floated by workspaces.lua's title-matched rule,
// since it tiles by default otherwise). See
// docs/superpowers/specs/2026-11-09-ai-chat-panel-design.md.
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../services"
import "../components"

Window {
    id: win
    title: "Kessel AI Chat"
    width: 480
    height: 640
    minimumWidth: 360
    minimumHeight: 420
    visible: AiChat.shown
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    // true once the settings view (Task 10) wires a real toggle here
    property bool showSettings: false

    Rectangle {
        anchors.fill: parent
        color: Theme.island
        radius: Theme.radiusPanel
        border.width: Theme.borderWidth
        border.color: Theme.a(Theme.text, 0.1)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: 10

            // header
            RowLayout {
                Layout.fillWidth: true
                Label { text: "AI Chat"; font.bold: true; size: Theme.fontUi + 1; Layout.fillWidth: true }
                IconButton {
                    icon: Icons.settings
                    size: 30
                    onClicked: win.showSettings = !win.showSettings
                }
            }

            // messages
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !win.showSettings
                spacing: 8
                clip: true
                model: AiChat.messages
                delegate: Rectangle {
                    required property var modelData
                    width: list.width
                    height: body.implicitHeight + 44
                    radius: Theme.radiusCard
                    color: modelData.role === "user" ? Theme.cardHi : Theme.card

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.role === "user" ? "You" : AiChat.provider; color: Theme.subtext; size: Theme.fontSmall; Layout.fillWidth: true }
                            IconButton {
                                icon: Icons.clipboard
                                size: 22
                                onClicked: {} // wired in Task 9
                            }
                            Label {
                                text: "Quote"
                                color: Theme.subtext
                                size: Theme.fontSmall
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: {} /* wired in Task 9 */ }
                            }
                        }
                        TextArea {
                            id: body
                            Layout.fillWidth: true
                            readOnly: true
                            wrapMode: Text.Wrap
                            textFormat: Text.RichText
                            text: modelData.html || modelData.content
                            color: Theme.text
                            background: null
                            font.family: Theme.font
                            font.pointSize: Theme.fontUi
                        }
                    }
                }
            }

            // input row
            RowLayout {
                Layout.fillWidth: true
                visible: !win.showSettings
                spacing: 8
                TextField {
                    id: input
                    Layout.fillWidth: true
                    enabled: !AiChat.streaming
                    placeholderText: AiChat.streaming ? "Waiting for a response…" : "Ask something…"
                    color: Theme.text
                    font.family: Theme.font
                    onAccepted: { AiChat.send(text); text = "" }
                }
                IconButton {
                    icon: Icons.send
                    size: 36
                    tint: Theme.accent
                    onClicked: { input.accepted() }
                }
            }
        }
    }
}
