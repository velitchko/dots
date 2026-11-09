// SPDX-License-Identifier: GPL-3.0-or-later
// AI chat panel state: sessions (each its own named thread of messages),
// streaming, provider calls, settings. Spawns scripts/desktop/ai_chat.py per
// request (one process per send, a second one in --render mode once
// streaming finishes); see docs/superpowers/specs/2026-11-09-ai-chat-panel-design.md.
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
    // Defaults to a shell/Arch assistant persona (this machine's default
    // shell is fish, per AGENTS.md's own validation commands) -- tuned for
    // a small local model, which needs more steering to stay terse and
    // correct than a frontier one does. Editable in Settings either way.
    property string systemPrompt: "You are a terminal assistant for Arch Linux, specializing in Bash and Fish shell scripting. Give direct, correct, copy-pasteable commands with minimal preamble. Prefer pacman/official repos over AUR unless the user needs an AUR package, and say so when it's AUR. Match the user's shell when they specify one; otherwise assume fish, this system's default. Briefly explain any non-obvious flag. Clearly flag destructive commands (rm -rf, dd, mkfs, etc.) before giving them."
    property bool streaming: false
    // Accumulates the in-flight reply without touching `sessions` (so
    // `messages` keeps one stable array identity for the whole reply --
    // reassigning it per token used to reset the ListView's model and snap
    // scroll position back to 0 on every single delta, which Qt.callLater
    // then corrected a frame later: a visible top/bottom flicker on every
    // token, confirmed on screen recording). The in-flight message's real
    // `content` field stays "" until _finishStreaming commits it once.
    property string streamingText: ""

    // Sessions: separate named threads, switchable/creatable/deletable. There
    // is always at least one (ensureSession() guarantees it) -- the window
    // always has somewhere to send into, never a null-session state to guard
    // against everywhere else.
    property var sessions: []              // [{id, name, messages: [...]}]
    property string activeSessionId: ""
    readonly property var activeSession: root.sessions.find(s => s.id === root.activeSessionId) || null
    readonly property var messages: root.activeSession ? root.activeSession.messages : []

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
    function setSystemPrompt(text) { root.systemPrompt = text; root.saveSettings() }
    function setProvider(p) { root.provider = p; root.saveSettings() }

    function _newId() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 8) }

    // Guarantees at least one session exists and activeSessionId points at a
    // real one. Called after loading (or failing to load) history, and
    // whenever deleting a session could otherwise leave zero.
    function ensureSession() {
        if (root.sessions.length === 0) {
            const id = root._newId()
            root.sessions = [{ id: id, name: root.defaultSessionName, messages: [] }]
            root.activeSessionId = id
        } else if (!root.sessions.some(s => s.id === root.activeSessionId)) {
            root.activeSessionId = root.sessions[0].id
        }
    }

    function newSession(name) {
        const id = root._newId()
        root.sessions = root.sessions.concat([{ id: id, name: (name || "").trim() || root.defaultSessionName, messages: [] }])
        root.activeSessionId = id
        root.saveHistory()
    }

    function deleteSession(id) {
        root.sessions = root.sessions.filter(s => s.id !== id)
        root.ensureSession()
        root.saveHistory()
    }

    function renameSession(id, name) {
        if ((name || "").trim() === "") return
        const idx = root.sessions.findIndex(s => s.id === id)
        if (idx === -1) return
        const sess = root.sessions.slice()
        sess[idx] = Object.assign({}, sess[idx], { name: name.trim() })
        root.sessions = sess
        root.saveHistory()
    }

    function switchSession(id) {
        if (root.streaming) return // don't switch away from a reply in flight
        if (root.sessions.some(s => s.id === id)) root.activeSessionId = id
    }

    // Clears the *active* session's messages in place (same session, same
    // name, empty thread) -- distinct from newSession(), which creates a new
    // named one. Both are exposed; this is the quick "start over" action.
    function clearConversation() {
        root._setMessages([])
        root.saveHistory()
    }

    function _setMessages(newMessages) {
        const idx = root.sessions.findIndex(s => s.id === root.activeSessionId)
        if (idx === -1) return
        const sess = root.sessions.slice()
        sess[idx] = Object.assign({}, sess[idx], { messages: newMessages })
        root.sessions = sess
    }

    // "New chat" is the only name a session ever gets automatically, so it's
    // also the only one safe to silently overwrite -- anything else means
    // the person (or an earlier call to this) already named it on purpose.
    readonly property string defaultSessionName: "New chat"

    function _autoTitle(firstMessage) {
        const oneLine = firstMessage.trim().split("\n")[0]
        return oneLine.length > 40 ? oneLine.slice(0, 40).trim() + "…" : oneLine
    }

    function send(text) {
        if (root.streaming || text.trim() === "") return
        if (root.messages.length === 0 && root.activeSession && root.activeSession.name === root.defaultSessionName) {
            root.renameSession(root.activeSessionId, root._autoTitle(text))
        }
        // Error turns were never a real assistant reply, and an empty turn
        // (a reply that produced no deltas before erroring, or a stream
        // still being rebuilt) makes some providers reject every later
        // request outright -- neither belongs in the context sent back.
        const payload = root.messages
            .filter(m => !m.isError && m.content.trim() !== "")
            .map(m => ({ role: m.role, content: m.content }))
        payload.push({ role: "user", content: text })
        root._setMessages(root.messages.concat([
            { role: "user", content: text, html: "", provider: root.provider, model: root.model, ts: Date.now() },
            { role: "assistant", content: "", html: "", provider: root.provider, model: root.model, ts: Date.now() }
        ]))
        root.streaming = true
        root.streamingText = ""
        sendProcess.gotFinalChunk = false
        sendProcess.payload = JSON.stringify(payload)
        sendProcess.command = ["python3", root.scriptPath, "--provider", root.provider, "--model", root.model]
            .concat(root.provider === "openai-compatible" ? ["--base-url", root.baseUrl] : [])
            .concat(root.systemPrompt.trim() !== "" ? ["--system-prompt", root.systemPrompt] : [])
        sendProcess.running = true
    }

    function _appendDelta(delta) {
        root.streamingText += delta
    }

    // errorText undefined = clean completion (kick off the render pass, and
    // only then clear `streaming` -- keeping it set through the render pass,
    // not just the stream, is what stops a second send() from landing its
    // render on top of this one's: send() is streaming-gated, so nothing
    // can start a new exchange while this one's render is still in flight).
    // errorText set = append it to whatever streamed before the failure
    // (Review Focus: a reasonable person expects the partial reply to stay
    // visible with a clear error appended, not replaced by just the error).
    // Either way this is the single point that commits streamingText into
    // the real message array -- the only `messages` reassignment that
    // happens during a whole reply, besides the one at send() that adds
    // the two new rows.
    function _finishStreaming(errorText) {
        const msgs = root.messages.slice()
        const last = msgs[msgs.length - 1]
        let content = root.streamingText
        let isError = false
        if (errorText !== undefined) {
            const sep = content ? "\n\n" : ""
            content = content + sep + "⚠ " + errorText
            isError = true
        }
        msgs[msgs.length - 1] = Object.assign({}, last, { content: content, isError: isError })
        root._setMessages(msgs)
        root.streamingText = ""
        if (errorText !== undefined) {
            root.streaming = false
            root.saveHistory()
            return
        }
        renderProcess.payload = content
        renderProcess.running = true
    }

    function _applyRenderedHtml(htmlText) {
        root.streaming = false
        const msgs = root.messages.slice()
        msgs[msgs.length - 1] = Object.assign({}, msgs[msgs.length - 1], { html: htmlText })
        root._setMessages(msgs)
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
        try {
            const data = JSON.parse(historyFile.text())
            root.sessions = data.sessions || []
            root.activeSessionId = data.activeSessionId || ""
        } catch (e) {
            root.sessions = []
            root.activeSessionId = ""
        }
        root.ensureSession()
    }

    function saveHistory() {
        historyFile.setText(JSON.stringify({ sessions: root.sessions, activeSessionId: root.activeSessionId }))
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
            if (s.systemPrompt !== undefined) root.systemPrompt = s.systemPrompt
        } catch (e) { /* defaults already set */ }
    }

    function saveSettings() {
        settingsFile.setText(JSON.stringify({ provider: root.provider, providerModels: root.providerModels, baseUrl: root.baseUrl, systemPrompt: root.systemPrompt }))
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
        onLoadFailed: root.ensureSession() // no history yet (first run) -- still need a session to send into
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
