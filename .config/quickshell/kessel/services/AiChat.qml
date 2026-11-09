// SPDX-License-Identifier: GPL-3.0-or-later
// AI chat panel state: messages, streaming, provider calls, history.
// Spawns scripts/desktop/ai_chat.py per request (one process per send, a
// second one in --render mode once streaming finishes); see
// docs/superpowers/specs/2026-11-09-ai-chat-panel-design.md.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root

    property bool shown: false
    property string provider: "ollama"
    property string model: ""
    property var messages: []     // [{role, content, html, provider, ts}]
    property bool streaming: false

    readonly property string scriptPath: Quickshell.env("HOME") + "/.config/hypr/scripts/ai_chat.py"
    readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/kessel/ai/history.json"

    function toggle() { root.shown = !root.shown }
    function open() { root.shown = true }
    function close() { root.shown = false }

    function send(text) {
        if (root.streaming || text.trim() === "") return
        const payload = root.messages.map(m => ({ role: m.role, content: m.content }))
        payload.push({ role: "user", content: text })
        root.messages = root.messages.concat([
            { role: "user", content: text, html: "", provider: root.provider, ts: Date.now() },
            { role: "assistant", content: "", html: "", provider: root.provider, ts: Date.now() }
        ])
        root.streaming = true
        sendProcess.payload = JSON.stringify(payload)
        sendProcess.command = ["python3", root.scriptPath, "--provider", root.provider, "--model", root.model]
        sendProcess.running = true
    }

    function _appendDelta(delta) {
        const msgs = root.messages.slice()
        const last = msgs[msgs.length - 1]
        msgs[msgs.length - 1] = Object.assign({}, last, { content: last.content + delta })
        root.messages = msgs
    }

    // errorText undefined = clean completion (kick off the render pass);
    // set = the stream ended in an error (shown as the message itself).
    function _finishStreaming(errorText) {
        root.streaming = false
        if (errorText !== undefined) {
            const msgs = root.messages.slice()
            msgs[msgs.length - 1] = Object.assign({}, msgs[msgs.length - 1], { content: errorText })
            root.messages = msgs
            root.saveHistory()
            return
        }
        const last = root.messages[root.messages.length - 1]
        renderProcess.payload = last.content
        renderProcess.running = true
    }

    function _applyRenderedHtml(htmlText) {
        const msgs = root.messages.slice()
        msgs[msgs.length - 1] = Object.assign({}, msgs[msgs.length - 1], { html: htmlText })
        root.messages = msgs
        root.saveHistory()
    }

    Process {
        id: sendProcess
        property string payload: ""
        stdinEnabled: true
        onStarted: sendProcess.write(sendProcess.payload + "\n")
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.trim() === "") return
                let chunk
                try { chunk = JSON.parse(data) } catch (e) { return }
                if (chunk.delta !== undefined) root._appendDelta(chunk.delta)
                else if (chunk.error !== undefined) root._finishStreaming(chunk.error)
                else if (chunk.done) root._finishStreaming(undefined)
            }
        }
    }

    Process {
        id: renderProcess
        property string payload: ""
        command: ["python3", root.scriptPath, "--render"]
        stdinEnabled: true
        onStarted: renderProcess.write(renderProcess.payload)
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._applyRenderedHtml(JSON.parse(text).html)
                } catch (e) {
                    root._applyRenderedHtml("")
                }
            }
        }
    }

    function loadHistory() {
        try { root.messages = JSON.parse(historyFile.text()) } catch (e) { root.messages = [] }
    }

    function saveHistory() {
        historyFile.setText(JSON.stringify(root.messages))
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/kessel/ai"])
    }

    FileView {
        id: historyFile
        path: root.historyPath
        watchChanges: false
        printErrors: false
        onLoaded: root.loadHistory()
        onLoadFailed: { /* no history yet (first run) -- messages stays [] */ }
    }
}
