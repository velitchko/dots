// SPDX-License-Identifier: GPL-3.0-or-later
// Inline settings view for the AI chat window (not an island panel -- the
// whole point of this window is that it's reached by SUPER+I, not by
// digging through Control Center). Provider/model picker + API key
// store/clear, scripts/desktop/ai_chat.py --store-key/--delete-key via
// Quickshell.Io.Process, the key piped through stdin, never an argv element.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../services"
import "../components"

ColumnLayout {
    id: root
    spacing: 14

    readonly property var providers: [
        { id: "ollama", label: "Ollama (local)", needsKey: false, needsUrl: false, optionalKey: false },
        { id: "anthropic", label: "Anthropic", needsKey: true, needsUrl: false, optionalKey: false },
        { id: "openai", label: "OpenAI", needsKey: true, needsUrl: false, optionalKey: false },
        { id: "openai-compatible", label: "Local / self-hosted (OpenAI-compatible)", needsKey: false, needsUrl: true, optionalKey: true }
    ]

    Process {
        id: keyProcess
        property string payload: ""
        stdinEnabled: true
        onStarted: {
            keyProcess.write(keyProcess.payload)
            keyProcess.stdinEnabled = false
            keyProcess.payload = "" // don't keep the key in memory after it's been written
        }
    }

    function storeKey(provider, key) {
        keyProcess.payload = key
        keyProcess.command = ["python3", AiChat.scriptPath, "--store-key", provider]
        keyProcess.running = true
    }
    function deleteKey(provider) {
        keyProcess.command = ["python3", AiChat.scriptPath, "--delete-key", provider]
        keyProcess.running = true
    }

    Repeater {
        model: root.providers
        delegate: Rectangle {
            required property var modelData
            readonly property bool active: AiChat.provider === modelData.id
            Layout.fillWidth: true
            implicitHeight: body.implicitHeight + 24
            radius: Theme.radiusCard
            color: active ? Theme.cardHi : Theme.card
            border.width: active ? Theme.borderWidth : 0
            border.color: Theme.accent

            ColumnLayout {
                id: body
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: modelData.label; font.bold: true; Layout.fillWidth: true }
                    Label {
                        text: active ? "Active" : "Use this"
                        color: active ? Theme.accent : Theme.subtext
                        size: Theme.fontSmall
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            // save whatever's currently typed, not just whatever was
                            // last confirmed with Enter -- "Use this" used to switch
                            // provider without saving the model field at all.
                            onClicked: {
                                AiChat.setProviderModel(modelData.id, modelField.text)
                                if (modelData.needsUrl) AiChat.setBaseUrl(urlField.text)
                                AiChat.setProvider(modelData.id)
                            }
                        }
                    }
                }

                SearchField {
                    id: modelField
                    Layout.fillWidth: true
                    icon: ""
                    placeholder: "Model name (e.g. " + (modelData.id === "ollama" ? "qwen2.5:0.5b" : modelData.id === "anthropic" ? "claude-sonnet-5-5" : modelData.id === "openai" ? "gpt-5" : "whatever your server calls it") + ")"
                    // this card's own remembered model, regardless of which
                    // provider is active -- was bound to the single shared
                    // AiChat.model, so switching cards showed (and would send)
                    // the previous provider's model name.
                    text: AiChat.providerModels[modelData.id] || ""
                    onAccepted: { AiChat.setProviderModel(modelData.id, text); AiChat.setProvider(modelData.id) }
                }

                SearchField {
                    id: urlField
                    visible: modelData.needsUrl
                    Layout.fillWidth: true
                    icon: ""
                    placeholder: "Base URL (e.g. http://localhost:8080/v1/chat/completions)"
                    text: AiChat.baseUrl
                    onAccepted: { AiChat.setBaseUrl(text); AiChat.setProvider(modelData.id) }
                }

                RowLayout {
                    visible: modelData.needsKey || modelData.optionalKey
                    Layout.fillWidth: true
                    spacing: 8
                    SearchField {
                        id: keyField
                        Layout.fillWidth: true
                        icon: ""
                        placeholder: modelData.optionalKey ? "API key (optional -- most local servers don't need one)" : "API key"
                        input.echoMode: TextInput.Password
                    }
                    Label {
                        text: "Save"
                        color: Theme.accent
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (keyField.text === "") return
                                root.storeKey(modelData.id, keyField.text)
                                keyField.text = ""
                            }
                        }
                    }
                    Label {
                        text: "Clear"
                        color: Theme.subtext
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.deleteKey(modelData.id) }
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
