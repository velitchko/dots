// SPDX-License-Identifier: GPL-3.0-or-later
// Shortcuts (SUPER+/): every keybind from keybinds.lua, grouped, searchable, and a
// Scripts tab (~/Scripts: location, purpose, usage, read from each script's header).
// Keys are drawn as keycaps (Arch logo for SUPER); rows alternate a very faint
// fill so the eye can follow a line across. fuzzel is the fallback without the island.
import QtQuick
import "../.."
import "../../services"
import "../../components"

PanelBase {
    id: root
    title: "Shortcuts"
    icon: Icons.keyboard
    contentWidth: 760
    contentHeight: search.height + 10 + (tab === "keys" ? list.height : scriptList.height)

    // "keys": keybinds · "scripts": ~/Scripts with location, purpose and usage. Tab switches.
    property string tab: "keys"
    onTabChanged: { if (tab === "scripts") Shortcuts.refreshScripts(); search.focusInput() }
    headerExtra: Row {
        spacing: 4
        Repeater {
            model: [{ id: "keys", label: "Keys" }, { id: "scripts", label: "Scripts" }]
            Rectangle {
                required property var modelData
                readonly property bool on: root.tab === modelData.id
                height: 26; width: tabLabel.implicitWidth + 22; radius: 13
                color: on ? Theme.a(Theme.accent, 0.22) : (tabMa.containsMouse ? Theme.cardHi : "transparent")
                border.width: on ? 1 : 0
                border.color: Theme.a(Theme.accent, 0.6)
                Label { id: tabLabel; anchors.centerIn: parent; text: modelData.label; size: Theme.fontSmall; font.bold: parent.on; color: parent.on ? Theme.accent : Theme.text }
                MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = parent.modelData.id }
            }
        }
    }
    readonly property var scriptResults: Shortcuts.scripts.filter(sc => Shortcuts.matchesScript(sc, search.text))
    readonly property var scriptRows: {
        const out = []
        let last = "", n = 0
        for (const sc of scriptResults) {
            if (sc.group !== last) { out.push({ header: sc.group + (sc.group === "Desktop" ? "  ·  ~/Scripts/desktop (also ~/.config/hypr/scripts): run by keybinds and the island" : "  ·  ~/Scripts") }); last = sc.group; n = 0 }
            out.push({ script: sc, stripe: n++ % 2 === 0 })
        }
        return out
    }

    readonly property var results: Shortcuts.entries.filter(e => Shortcuts.matches(e, search.text))
    // rows with a header before each group (ListView sections need model roles,
    // which a plain JS array doesn't have); `stripe` restarts in every group
    readonly property var rows: {
        const out = []
        let last = "", n = 0
        for (const e of results) {
            if (e.group !== last) { out.push({ header: e.group }); last = e.group; n = 0 }
            out.push({ entry: e, stripe: n++ % 2 === 0 })
        }
        return out
    }
    onActiveFocusChanged: if (activeFocus) search.focusInput()

    SearchField {
        id: search
        width: parent.width
        placeholder: root.tab === "keys" ? "Search shortcuts   (Tab: scripts)" : "Search scripts   (Tab: keys)"
        onUp: (root.tab === "keys" ? list : scriptList).flick(0, 900)
        onDown: (root.tab === "keys" ? list : scriptList).flick(0, -900)
        input.Keys.onTabPressed: root.tab = root.tab === "keys" ? "scripts" : "keys"
    }

    ListView {
        id: list
        visible: root.tab === "keys"
        anchors.top: search.bottom
        anchors.topMargin: 10
        width: parent.width
        height: Math.min(560, Math.max(48, contentHeight))
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows

        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool isHeader: modelData.header !== undefined
            width: list.width
            height: isHeader ? 34 : 36
            radius: 8
            // very faint zebra striping (theme text colour, so it suits light and dark)
            color: !isHeader && modelData.stripe ? Theme.a(Theme.text, Theme.dark ? 0.045 : 0.035) : "transparent"

            Label {
                visible: row.isHeader
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: row.modelData.header ?? ""
                color: Theme.accent
                size: Theme.fontSmall
                font.bold: true
            }

            Row {
                id: caps
                visible: !row.isHeader
                x: 10
                width: 190
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                Repeater {
                    model: row.isHeader ? [] : Shortcuts.keycaps(row.modelData.entry.keys)
                    Rectangle {
                        required property var modelData
                        height: 26
                        width: Math.max(height, inner.implicitWidth + 14)
                        radius: 7
                        color: Theme.a(Theme.text, Theme.dark ? 0.08 : 0.07)
                        border.width: 1
                        border.color: Theme.a(Theme.text, 0.10)
                        opacity: modelData.optional ? 0.55 : 1
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: inner
                            anchors.centerIn: parent
                            spacing: 3
                            Glyph {
                                visible: !!parent.parent.modelData.g
                                text: parent.parent.modelData.g ?? ""
                                size: Theme.fontUi + 2
                                optical: true
                                color: Theme.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Label {
                                visible: !!parent.parent.modelData.t
                                text: parent.parent.modelData.t ?? ""
                                size: Theme.fontSmall + 1
                                font.bold: true
                                color: Theme.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
            Label {
                visible: !row.isHeader
                anchors.left: parent.left
                anchors.leftMargin: 205
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.entry?.desc ?? ""
                size: Theme.fontUi
            }
        }
        WheelHandler { onWheel: e => list.flick(0, e.angleDelta.y * 6) }
    }
    // ── Scripts tab ──────────────────────────────────────────────────────────
    ListView {
        id: scriptList
        visible: root.tab === "scripts"
        anchors.top: search.bottom
        anchors.topMargin: 10
        width: parent.width
        height: Math.min(560, Math.max(48, contentHeight))
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.tab === "scripts" ? root.scriptRows : []
        spacing: 2

        delegate: Rectangle {
            id: srow
            required property var modelData
            readonly property bool isHeader: modelData.header !== undefined
            property bool copied: false
            width: scriptList.width
            height: isHeader ? 34 : body.implicitHeight + 16
            radius: 8
            color: isHeader ? "transparent"
                : sma.containsMouse ? Theme.a(Theme.text, Theme.dark ? 0.07 : 0.06)
                : modelData.stripe ? Theme.a(Theme.text, Theme.dark ? 0.045 : 0.035) : "transparent"

            Label {
                visible: srow.isHeader
                anchors.left: parent.left; anchors.leftMargin: 10
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                text: srow.modelData.header ?? ""
                color: Theme.accent
                size: Theme.fontSmall
                font.bold: true
            }
            Column {
                id: body
                visible: !srow.isHeader
                x: 12; y: 8
                width: parent.width - 24
                spacing: 3
                Row {
                    spacing: 10
                    Label { text: srow.modelData.script?.name ?? ""; font.bold: true; size: Theme.fontUi }
                    Label { text: srow.copied ? "copied" : (srow.modelData.script?.path ?? ""); size: Theme.fontSmall; color: srow.copied ? Theme.accent : Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                }
                Label {
                    width: parent.width
                    text: srow.modelData.script?.purpose ?? ""
                    size: Theme.fontSmall + 0.5
                    color: Theme.subtext
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
                Repeater {
                    model: srow.isHeader ? [] : srow.modelData.script.usage
                    Item {
                        required property var modelData
                        width: body.width
                        height: Math.max(ucmd.implicitHeight, uwhat.implicitHeight)
                        Label { id: ucmd; width: 300; text: modelData.cmd; size: Theme.fontSmall; color: Theme.accent; elide: Text.ElideRight }
                        Label { id: uwhat; x: 310; width: parent.width - 310; text: modelData.what; size: Theme.fontSmall; color: Theme.text; wrapMode: Text.Wrap; elide: Text.ElideNone }
                    }
                }
            }
            MouseArea {
                id: sma
                anchors.fill: parent
                enabled: !srow.isHeader
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { Shortcuts.copyPath(srow.modelData.script); srow.copied = true; copiedTimer.restart() }
            }
            Timer { id: copiedTimer; interval: 1200; onTriggered: srow.copied = false }
        }
        WheelHandler { onWheel: e => scriptList.flick(0, e.angleDelta.y * 6) }
    }

    Label {
        visible: root.tab === "scripts" && root.scriptResults.length === 0
        anchors.top: search.bottom
        anchors.topMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        text: Shortcuts.scripts.length === 0 ? "Loading…" : "Nothing matches"
        color: Theme.subtext
    }
    Label {
        visible: root.tab === "keys" && root.results.length === 0
        anchors.top: search.bottom
        anchors.topMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        text: Shortcuts.entries.length === 0 ? "No shortcuts yet: reload Hyprland (CTRL+SUPER+R)" : "Nothing matches"
        color: Theme.subtext
    }
}
