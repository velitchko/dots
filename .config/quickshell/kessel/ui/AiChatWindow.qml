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
import Quickshell.Widgets
import ".."
import "../services"
import "../components"

Window {
    id: win
    title: "Kessel AI Chat"
    width: 680
    height: 820
    minimumWidth: 360
    minimumHeight: 420
    visible: AiChat.shown
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    // Closing via the compositor's own close/kill bind only hides the Qt
    // Window -- it doesn't touch AiChat.shown, which drives the LazyLoader
    // that owns this window's existence. Without this, AiChat.shown stays
    // true, so the next SUPER+I toggles it to false (no visible change,
    // the window's already gone) and only the press after that reopens it.
    onClosing: AiChat.close()

    property bool showSettings: false
    property bool showSessions: false

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
                spacing: 8
                // A small drawn mark instead of an emoji: three connected
                // nodes read as "network/intelligence" without leaning on
                // a brain/robot cliché or an emoji's inconsistent look
                // across fonts. Plain Canvas, same as WavyBar.qml.
                Canvas {
                    id: mark
                    width: 16; height: 16
                    visible: !win.showSettings && !win.showSessions
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const top = [8, 3], left = [3, 13], right = [13, 13]
                        ctx.strokeStyle = Theme.a(Theme.accent, 0.5)
                        ctx.lineWidth = 1.2
                        ctx.beginPath()
                        ctx.moveTo(top[0], top[1]); ctx.lineTo(left[0], left[1])
                        ctx.moveTo(top[0], top[1]); ctx.lineTo(right[0], right[1])
                        ctx.moveTo(left[0], left[1]); ctx.lineTo(right[0], right[1])
                        ctx.stroke()
                        ctx.fillStyle = Theme.accent
                        for (const [x, y, r] of [[top[0], top[1], 2], [left[0], left[1], 1.5], [right[0], right[1], 1.5]]) {
                            ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill()
                        }
                    }
                }
                Label {
                    // the session's real name once it has one (auto-titled from
                    // the first message, or renamed by hand) -- "New chat" is
                    // just the placeholder before that happens, not worth
                    // stating out loud when it's the obvious default state
                    text: win.showSettings ? "Settings" : win.showSessions ? "Sessions"
                        : (AiChat.activeSession && AiChat.activeSession.name !== AiChat.defaultSessionName) ? AiChat.activeSession.name : "Intelligence"
                    font.bold: true
                    size: Theme.fontUi + 1
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Label {
                    // no verified "list/menu" glyph to reuse safely, so this is
                    // text, same as how Quote started before a safe icon turned up
                    text: "Sessions"
                    visible: !win.showSettings && !win.showSessions
                    color: Theme.subtext
                    size: Theme.fontSmall
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.showSessions = true }
                }
                IconButton {
                    icon: Icons.trash
                    size: 30
                    visible: !win.showSettings && !win.showSessions && AiChat.messages.length > 0
                    onClicked: AiChat.clearConversation()
                }
                IconButton {
                    icon: Icons.back
                    size: 30
                    visible: win.showSettings || win.showSessions
                    onClicked: { win.showSettings = false; win.showSessions = false }
                }
                IconButton {
                    icon: Icons.settings
                    size: 30
                    visible: !win.showSessions
                    onClicked: win.showSettings = !win.showSettings
                }
            }

            // messages
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !win.showSettings && !win.showSessions
                spacing: 8
                clip: true
                model: AiChat.messages
                // AiChat.messages only gets a new array identity twice per
                // reply now (send(), _finishStreaming()) -- streamed tokens
                // land in AiChat.streamingText instead, a plain string the
                // in-flight delegate binds to directly, so the model (and
                // this view's scroll position) stays untouched while a
                // reply is actively streaming in.
                //
                // "Stick to bottom" while content grows: positionViewAtEnd
                // on every contentHeight change (each streamed token resizes
                // the last delegate) would also fight a user who scrolled up
                // to reread something, so it only fires while the view was
                // already at the end; scrolling away turns it off until the
                // view either returns to the end on its own or a new
                // message starts (which always re-pins, same as before).
                property bool stickToBottom: true
                onCountChanged: { list.stickToBottom = true; positionViewAtEnd() }
                onContentHeightChanged: if (list.stickToBottom) Qt.callLater(list.positionViewAtEnd)
                onMovementEnded: list.stickToBottom = list.atYEnd
                delegate: Rectangle {
                    id: delegateRoot
                    required property var modelData
                    required property int index
                    readonly property bool isStreamingTarget: AiChat.streaming && index === list.count - 1 && modelData.role === "assistant"
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
                            spacing: 6
                            // user: their own ~/.face if set (same source the lock
                            // screen and SDDM theme already use), else a plain
                            // initial. assistant: a robot glyph -- a real emoji
                            // doesn't carry the "verify against glyphnames.json"
                            // risk a Nerd Font codepoint would, it's a standard
                            // widely-supported Unicode character.
                            Item {
                                width: 18; height: 18
                                visible: modelData.role === "user"
                                ClippingRectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Theme.overlay
                                    visible: User.hasFace
                                    Image {
                                        anchors.fill: parent
                                        source: User.hasFace ? "file://" + User.face : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }
                                Label {
                                    anchors.centerIn: parent
                                    visible: !User.hasFace
                                    text: User.name.charAt(0).toUpperCase()
                                    size: Theme.fontSmall
                                    color: Theme.subtext
                                }
                            }
                            Label { text: "🤖"; visible: modelData.role !== "user"; size: Theme.fontSmall }
                            Label {
                                text: modelData.role === "user" ? User.name : "ai (" + (modelData.model || modelData.provider) + ")"
                                color: Theme.subtext
                                size: Theme.fontSmall
                                Layout.fillWidth: true
                            }
                            IconButton {
                                icon: Icons.clipboard
                                size: 22
                                // Quickshell.clipboardText, not wl-copy via execDetached: a
                                // message starting with "-" (any markdown bullet list) gets
                                // parsed by wl-copy as an option and fails, and a long enough
                                // message can exceed a single argv element's size limit.
                                onClicked: Quickshell.clipboardText = delegateRoot.isStreamingTarget ? AiChat.streamingText : modelData.content
                            }
                            IconButton {
                                // reply-style visual (left-pointing arrow); reuses the
                                // already-verified Icons.back glyph rather than guessing
                                // a new codepoint for "quote"/"reply"
                                icon: Icons.back
                                size: 22
                                onClicked: {
                                    const src = delegateRoot.isStreamingTarget ? AiChat.streamingText : modelData.content
                                    const quoted = src.split("\n").map(l => "> " + l).join("\n")
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
                            // RichText only once the sanitized render lands (modelData.html) --
                            // modelData.content is the model's raw, un-sanitized text (streaming
                            // deltas, user messages, which never get an html pass, and error
                            // text), and Text.RichText would interpret raw angle brackets as
                            // markup with none of ai_chat.py's sanitization in between.
                            // PlainText never interprets anything, so it's safe regardless, and
                            // (unlike RichText without <br>) correctly preserves newlines.
                            // The in-flight reply reads from AiChat.streamingText directly
                            // (always plain -- it never gets an html pass until it's done).
                            textFormat: (!delegateRoot.isStreamingTarget && modelData.html) ? Text.RichText : Text.PlainText
                            text: delegateRoot.isStreamingTarget ? AiChat.streamingText : (modelData.html || modelData.content)
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
                visible: !win.showSettings && !win.showSessions
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

            ScrollView {
                id: sessionsScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.showSessions
                AiChatSessions { width: sessionsScroll.availableWidth }
            }
        }
    }
}
