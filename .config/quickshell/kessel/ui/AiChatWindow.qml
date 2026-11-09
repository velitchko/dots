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

    property bool showSettings: false

    // A fresh playful prompt each time the window opens, not the generic
    // "Ask something..." -- picked once per open, not re-rolled on every
    // binding re-evaluation.
    readonly property var playfulPrompts: [
        "What's up?", "What do you wanna know?", "What's on your mind?",
        "Need a hand with something?", "Ask away…", "What are we figuring out today?"
    ]
    property string placeholderPhrase: playfulPrompts[Math.floor(Math.random() * playfulPrompts.length)]

    // Chat content (not the UI chrome, which stays on Theme.font like every
    // other kessel surface) matches the terminal exactly: same family, same
    // point size -- kitty.conf: font_family JetBrainsMono Nerd Font Mono,
    // font_size 11.
    readonly property string contentFontFamily: "JetBrainsMono Nerd Font Mono"
    readonly property real contentFontSize: 11

    Rectangle {
        anchors.fill: parent
        color: Theme.island
        // Matches general.lua's decoration.rounding (10) exactly -- Hyprland
        // draws this window's actual border/corner decoration now (reverted
        // the earlier rounding/border_size=0 override, see workspaces.lua),
        // so this just needs to not visibly disagree with it. No border of
        // its own: Hyprland's accent border is the border.
        radius: 10

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
                                onClicked: Quickshell.execDetached(["wl-copy", modelData.content])
                            }
                            IconButton {
                                // reply-style visual (left-pointing arrow); reuses the
                                // already-verified Icons.back glyph rather than guessing
                                // a new codepoint for "quote"/"reply"
                                icon: Icons.back
                                size: 22
                                onClicked: {
                                    const quoted = modelData.content.split("\n").map(l => "> " + l).join("\n")
                                    input.text = quoted + "\n\n" + input.text
                                    input.focusInput()
                                }
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
                            font.family: win.contentFontFamily
                            font.pointSize: win.contentFontSize
                        }
                    }
                }
            }

            // input row
            RowLayout {
                Layout.fillWidth: true
                visible: !win.showSettings
                spacing: 8
                SearchField {
                    id: input
                    Layout.fillWidth: true
                    icon: ""
                    placeholder: AiChat.streaming ? "Waiting for a response…" : win.placeholderPhrase
                    enabled: !AiChat.streaming
                    onAccepted: { AiChat.send(text); text = "" }
                }
                IconButton {
                    icon: Icons.send
                    size: 36
                    tint: Theme.accent
                    onClicked: input.accepted()
                }
            }

            ScrollView {
                id: settingsScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.showSettings
                AiChatSettings { width: settingsScroll.availableWidth }
            }
        }
    }
}
