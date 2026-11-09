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
    // per-provider, not one shared value -- switching providers used to carry
    // the previous provider's model name along and both show and send it.
    property var providerModels: ({})   // { "ollama": "qwen2.5:0.5b", ... }
    readonly property string model: root.providerModels[root.provider] || ""
    property string baseUrl: ""   // only used when provider === "openai-compatible"
    property var messages: []     // [{role, content, html, provider, ts}]
    property bool streaming: false

    readonly property string scriptPath: Quickshell.env("HOME") + "/.config/hypr/scripts/ai_chat.py"
    readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/kessel/ai/history.json"
    readonly property string settingsPath: Quickshell.env("HOME") + "/.local/state/kessel/ai/settings.json"

    function toggle() { root.shown = !root.shown }
    function open() { root.shown = true }
    function close() { root.shown = false }

    function setProviderModel(provider, model) {
        const m = Object.assign({}, root.providerModels)
        m[provider] = model
        root.providerModels = m
        root.saveSettings()
    }
    function setBaseUrl(url) { root.baseUrl = url; root.saveSettings() }
    function setProvider(p) { root.provider = p; root.saveSettings() }

    function clearConversation() {
        root.messages = []
        root.saveHistory()
    }

    function send(text) {
        if (root.streaming || text.trim() === "") return
        // Error turns were never a real assistant reply, and an empty turn
        // (a reply that produced no deltas before erroring, or a stream
        // still being rebuilt) makes some providers reject every later
        // request outright -- neither belongs in the context sent back.
        const payload = root.messages
            .filter(m => !m.isError && m.content.trim() !== "")
            .map(m => ({ role: m.role, content: m.content }))
        payload.push({ role: "user", content: text })
        root.messages = root.messages.concat([
            { role: "user", content: text, html: "", provider: root.provider, ts: Date.now() },
            { role: "assistant", content: "", html: "", provider: root.provider, ts: Date.now() }
        ])
        root.streaming = true
        sendProcess.gotFinalChunk = false
        sendProcess.payload = JSON.stringify(payload)
        sendProcess.command = ["python3", root.scriptPath, "--provider", root.provider, "--model", root.model]
            .concat(root.provider === "openai-compatible" ? ["--base-url", root.baseUrl] : [])
        sendProcess.running = true
    }

    function _appendDelta(delta) {
        const msgs = root.messages.slice()
        const last = msgs[msgs.length - 1]
        msgs[msgs.length - 1] = Object.assign({}, last, { content: last.content + delta })
        root.messages = msgs
    }

    // errorText undefined = clean completion (kick off the render pass, and
    // only then clear `streaming` -- keeping it set through the render pass,
    // not just the stream, is what stops a second send() from landing its
    // render on top of this one's: send() is streaming-gated, so nothing
    // can start a new exchange while this one's render is still in flight).
    // errorText set = append it to whatever streamed before the failure
    // (Review Focus: a reasonable person expects the partial reply to stay
    // visible with a clear error appended, not replaced by just the error).
    function _finishStreaming(errorText) {
        if (errorText !== undefined) {
            root.streaming = false
            const msgs = root.messages.slice()
            const last = msgs[msgs.length - 1]
            const sep = last.content ? "\n\n" : ""
            msgs[msgs.length - 1] = Object.assign({}, last, { content: last.content + sep + "⚠ " + errorText, isError: true })
            root.messages = msgs
            root.saveHistory()
            return
        }
        const last = root.messages[root.messages.length - 1]
        renderProcess.payload = last.content
        renderProcess.running = true
    }

    function _applyRenderedHtml(htmlText) {
        root.streaming = false
        const msgs = root.messages.slice()
        msgs[msgs.length - 1] = Object.assign({}, msgs[msgs.length - 1], { html: htmlText })
        root.messages = msgs
        root.saveHistory()
    }

    Process {
        id: sendProcess
        property string payload: ""
        // Distinguishes "exited after its own done/error chunk" (expected,
        // including the happy path -- streaming stays true through the
        // render pass that done triggers, so this process has already
        // exited normally well before streaming clears) from "exited with
        // nothing at all" (belt-and-suspenders against ai_chat.py's own
        // _safe_stream: that guarantees a final chunk for an in-process
        // exception, but the process itself could still be killed -- OOM, a
        // signal -- before it gets the chance; without this, nothing would
        // ever clear `streaming` and the input would stay disabled until
        // the shell restarts).
        property bool gotFinalChunk: false
        stdinEnabled: true
        onStarted: {
            sendProcess.write(sendProcess.payload + "\n")
            sendProcess.stdinEnabled = false // close the write end: ai_chat.py's stdin.read() blocks until EOF
        }
        onExited: (code, status) => {
            if (!sendProcess.gotFinalChunk) root._finishStreaming("the response process exited unexpectedly")
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.trim() === "") return
                let chunk
                try { chunk = JSON.parse(data) } catch (e) { return }
                if (chunk.delta !== undefined) { root._appendDelta(chunk.delta) }
                else if (chunk.error !== undefined) { sendProcess.gotFinalChunk = true; root._finishStreaming(chunk.error) }
                else if (chunk.done) { sendProcess.gotFinalChunk = true; root._finishStreaming(undefined) }
            }
        }
    }

    Process {
        id: renderProcess
        property string payload: ""
        command: ["python3", root.scriptPath, "--render"]
        stdinEnabled: true
        onStarted: {
            renderProcess.write(renderProcess.payload)
            renderProcess.stdinEnabled = false
        }
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

    // provider/model/baseUrl -- previously in-memory only, so every shell
    // restart lost them and the model field went back to empty (every send
    // failed until re-entered). No secrets in here, just names/URLs.
    function loadSettings() {
        try {
            const s = JSON.parse(settingsFile.text())
            root.provider = s.provider || "ollama"
            root.providerModels = s.providerModels || {}
            root.baseUrl = s.baseUrl || ""
        } catch (e) { /* defaults already set */ }
    }

    function saveSettings() {
        settingsFile.setText(JSON.stringify({ provider: root.provider, providerModels: root.providerModels, baseUrl: root.baseUrl }))
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

    FileView {
        id: settingsFile
        path: root.settingsPath
        watchChanges: false
        printErrors: false
        onLoaded: root.loadSettings()
        onLoadFailed: { /* no settings yet (first run) -- defaults already set */ }
    }
}
