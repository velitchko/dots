// SPDX-License-Identifier: GPL-3.0-or-later
// Spotlight-style launcher (SUPER+Space). Fuzzel stays on SUPER+R as the
// Quickshell-independent launcher.
import QtQuick
import Quickshell
import "../.."
import "../../services"
import "../../components"

PanelBase {
    id: root
    title: "Launch"
    icon: Icons.apps
    contentWidth: 520
    contentHeight: search.height + 10 + list.height

    // URL-ish: "https://…", "www.…", or "name.tld/…"
    function asUrl(q) {
        q = (q || "").trim()
        if (/\s/.test(q) || q.length < 4) return ""
        if (/^https?:\/\//i.test(q)) return q
        if (/^(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(:\d+)?(\/\S*)?$/i.test(q)) return "https://" + q
        return ""
    }
    // special rows (calculator result, open URL) come first, then apps
    readonly property var special: {
        const out = []
        if (Translator.looksLikeTranslate(search.text)) {
            const p = Translator.parse(search.text)
            out.push({ kind: "tr", value: Translator.state !== "ready" ? "" : (Translator.busy ? "…" : (Translator.result || Translator.error)),
                       label: p ? p.from + " → " + p.to : "" })
            return out
        }
        if (Calc.result !== "" && Calc.query === search.text) out.push({ kind: "calc", value: Calc.result })
        const u = asUrl(search.text)
        if (u !== "") out.push({ kind: "url", value: u })
        return out
    }
    property var results: Translator.looksLikeTranslate(search.text) ? special
        : special.concat(Apps.query(search.text).map(a => ({ kind: "app", app: a })))

    function launchCurrent() {
        if (list.currentIndex < 0 || list.currentIndex >= results.length) return
        const r = results[list.currentIndex]
        if (r.kind === "tr") { if (Translator.busy || Translator.result === "") return; Translator.copy() }
        else if (r.kind === "calc") Calc.copy(r.value)
        else if (r.kind === "url") Quickshell.execDetached([Utils.scripts + "browser-open.sh", r.value])
        else Apps.launch(r.app)
        IslandState.closePanel()
    }

    onActiveFocusChanged: if (activeFocus) search.focusInput()
    Component.onCompleted: if (IslandState.launcherText !== "") { search.text = IslandState.launcherText; IslandState.launcherText = "" }

    SearchField {
        id: search
        width: parent.width
        placeholder: "Apps · 2+2 · URL · >de translate"
        onTextChanged: { list.currentIndex = 0; Calc.evaluate(text); Translator.request(text) }
        onAccepted: root.launchCurrent()
        onUp: list.decrementCurrentIndex()
        onDown: list.incrementCurrentIndex()
    }

    ListView {
        id: list
        anchors.top: search.bottom
        anchors.topMargin: 10
        width: parent.width
        height: Math.min(8 * 48, Math.max(48, contentHeight))
        clip: true
        model: root.results
        currentIndex: 0
        highlightMoveDuration: 120
        boundsBehavior: Flickable.StopAtBounds
        highlight: Rectangle { radius: 12; color: Theme.cardHi }

        delegate: Item {
            id: d
            required property var modelData
            required property int index
            width: list.width
            height: d.modelData.kind === "tr" ? Math.max(48, textCol.implicitHeight + 18) : 48
            readonly property bool isApp: modelData.kind === "app"
            Image {
                id: appIcon
                visible: d.isApp
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30
                sourceSize: Qt.size(60, 60)
                source: d.isApp ? Quickshell.iconPath(d.modelData.app.icon, "application-x-executable") : ""
                asynchronous: true
            }
            Rectangle {
                visible: !d.isApp
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: 15
                color: Theme.a(Theme.accent, 0.18)
                Glyph { anchors.centerIn: parent; optical: true; size: Theme.fontUi + 1; color: Theme.accent
                        text: d.modelData.kind === "calc" ? Icons.calculator : d.modelData.kind === "tr" ? Icons.translate : Icons.web }
            }
            Column {
                id: textCol
                anchors.left: appIcon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    width: parent.width
                    wrapMode: d.modelData.kind === "tr" ? Text.Wrap : Text.NoWrap
                    maximumLineCount: d.modelData.kind === "tr" ? 3 : 1
                    elide: Text.ElideRight
                    text: d.modelData.kind === "tr" ? (Translator.state === "ready" ? (d.modelData.value || "Type a sentence…")
                                                      : Translator.state === "no-avx2" ? "This CPU can't run the translator (no AVX2)"
                                                      : "Offline translation isn't set up yet")
                        : d.modelData.kind === "calc" ? "= " + d.modelData.value
                        : d.modelData.kind === "url" ? d.modelData.value
                        : d.modelData.app.name
                    font.bold: !d.isApp
                    color: d.modelData.kind === "calc" ? Theme.accent : Theme.text
                }
                Label {
                    width: parent.width
                    text: d.modelData.kind === "tr" ? (Translator.state === "ready" ? d.modelData.label + " · offline · Enter to copy"
                                                      : Translator.state === "no-avx2" ? "On a VM: set its CPU type to 'host'"
                                                      : "Run: ~/.config/hypr/scripts/translate.sh setup")
                        : d.modelData.kind === "calc" ? "Enter to copy" + (Calc.qalcAvailable ? " · qalc" : "")
                        : d.modelData.kind === "url" ? "Enter to open in your browser"
                        : (d.modelData.app.comment || d.modelData.app.genericName || "")
                    visible: text !== ""
                    color: Theme.subtext
                    size: Theme.fontSmall
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: list.currentIndex = d.index
                onClicked: { list.currentIndex = d.index; root.launchCurrent() }
            }
        }
        Label {
            visible: list.count === 0
            anchors.centerIn: parent
            text: "No matches"
            color: Theme.subtext
        }
    }
}
