// SPDX-License-Identifier: GPL-3.0-or-later
// Shortcuts (SUPER+/): every keybind from keybinds.lua, grouped, searchable.
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
    contentHeight: search.height + 10 + list.height

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
        placeholder: "Search shortcuts"
        onUp: list.flick(0, 900)
        onDown: list.flick(0, -900)
    }

    ListView {
        id: list
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
    Label {
        visible: root.results.length === 0
        anchors.top: search.bottom
        anchors.topMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        text: Shortcuts.entries.length === 0 ? "No shortcuts yet: reload Hyprland (CTRL+SUPER+R)" : "Nothing matches"
        color: Theme.subtext
    }
}
