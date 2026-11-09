// SPDX-License-Identifier: GPL-3.0-or-later
// Session list for the AI chat window: separate named threads, switchable,
// renameable, deletable. Mirrors AiChatSettings.qml's card layout for
// visual consistency (header row with a switch/active indicator, an
// editable SearchField below).
import QtQuick
import QtQuick.Layouts
import ".."
import "../services"
import "../components"

ColumnLayout {
    id: root
    spacing: 10

    Repeater {
        model: AiChat.sessions
        delegate: Rectangle {
            required property var modelData
            readonly property bool active: AiChat.activeSessionId === modelData.id
            Layout.fillWidth: true
            implicitHeight: body.implicitHeight + 20
            radius: Theme.radiusCard
            color: active ? Theme.cardHi : Theme.card
            border.width: active ? Theme.borderWidth : 0
            border.color: Theme.accent

            ColumnLayout {
                id: body
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: active ? "Active" : "Switch"
                        color: active ? Theme.accent : Theme.subtext
                        size: Theme.fontSmall
                        Layout.fillWidth: true
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: AiChat.switchSession(modelData.id) }
                    }
                    IconButton {
                        icon: Icons.trash
                        size: 20
                        // always leave at least one session -- deleteSession()
                        // itself guarantees this (ensureSession()), but disabling
                        // the last one's button makes that visible instead of
                        // letting a click silently replace it with a fresh one
                        enabled: AiChat.sessions.length > 1
                        onClicked: AiChat.deleteSession(modelData.id)
                    }
                }

                SearchField {
                    Layout.fillWidth: true
                    icon: ""
                    text: modelData.name
                    onAccepted: AiChat.renameSession(modelData.id, text)
                }

                Label {
                    text: modelData.messages.length + (modelData.messages.length === 1 ? " message" : " messages")
                    color: Theme.subtext
                    size: Theme.fontSmall
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 40
        radius: Theme.radiusCard
        color: newMa.containsMouse ? Theme.cardHi : Theme.card
        Label { anchors.centerIn: parent; text: "+ New chat"; color: Theme.accent }
        MouseArea { id: newMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AiChat.newSession("") }
    }

    Item { Layout.fillHeight: true }
}
