// SPDX-License-Identifier: GPL-3.0-or-later
// Workspace (SUPER+G): Markdown notes in ~/Notes + a kanban board (~/Notes/Board.md).
//   Notes: CTRL+N new · CTRL+S save · CTRL+P preview · CTRL+Tab switch tab · Esc close
//   Board: type + Enter to add · drag cards between columns · click a card to edit
import QtQuick
import Quickshell
import "../.."
import "../../services"
import "../../components"

PanelBase {
    id: root
    title: "Workspace"
    icon: Icons.notes
    contentWidth: 860
    contentHeight: 470

    property string tab: IslandState.panel === "board" ? "board" : "notes"
    property bool preview: false
    property string armedDelete: ""

    headerExtra: [
        Repeater {
            model: [{ id: "notes", label: "Notes", icon: Icons.notes }, { id: "board", label: "Board", icon: Icons.overview }]
            Rectangle {
                required property var modelData
                readonly property bool on: root.tab === modelData.id
                width: tabRow.implicitWidth + 20; height: 26; radius: 13
                color: on ? Theme.a(Theme.accent, 0.2) : (tma.containsMouse ? Theme.cardHi : "transparent")
                Row {
                    id: tabRow
                    anchors.centerIn: parent
                    spacing: 6
                    Glyph { text: modelData.icon; size: Theme.fontSmall + 1; color: parent.parent.on ? Theme.accent : Theme.subtext }
                    Label { text: modelData.label; size: Theme.fontSmall; color: parent.parent.on ? Theme.accent : Theme.text }
                }
                MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = modelData.id }
            }
        }
    ]

    onActiveFocusChanged: if (activeFocus) focusCurrent()
    onTabChanged: focusCurrent()
    function focusCurrent() { if (tab === "notes") editor.forceActiveFocus(); else if (addFieldRef) addFieldRef.focusInput() }

    Keys.onPressed: e => {
        if (e.modifiers & Qt.ControlModifier) {
            if (e.key === Qt.Key_Tab) { tab = tab === "notes" ? "board" : "notes"; e.accepted = true }
            else if (e.key === Qt.Key_N && tab === "notes") { newName.visible = true; newName.focusInput(); e.accepted = true }
            else if (e.key === Qt.Key_S) { Notes.save(); e.accepted = true }
            else if (e.key === Qt.Key_P && tab === "notes") { preview = !preview; e.accepted = true }
        }
    }
    Component.onCompleted: Notes.refresh()
    Component.onDestruction: Notes.save()

    // ═════════════════════════════ NOTES ═════════════════════════════════
    Item {
        anchors.fill: parent
        visible: root.tab === "notes"

        // file list
        Rectangle {
            id: sidebar
            width: 210
            height: parent.height
            radius: Theme.radiusCard
            color: Theme.card

            Column {
                id: sideTop
                x: 8; y: 8
                width: parent.width - 16
                spacing: 6
                Rectangle {
                    width: parent.width; height: 32; radius: 10
                    color: nma.containsMouse ? Theme.a(Theme.accent, 0.25) : Theme.a(Theme.accent, 0.15)
                    Row { anchors.centerIn: parent; spacing: 6
                        Glyph { text: Icons.plus; color: Theme.accent; size: Theme.fontSmall + 1 }
                        Label { text: "New note"; color: Theme.accent; size: Theme.fontSmall } }
                    MouseArea { id: nma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { newName.visible = true; newName.focusInput() } }
                }
                SearchField {
                    id: newName
                    visible: false
                    width: parent.width
                    implicitHeight: 32
                    placeholder: "Name, then Enter"
                    onAccepted: { Notes.create(text); text = ""; visible = false; editor.forceActiveFocus() }
                    input.Keys.onEscapePressed: { text = ""; visible = false; editor.forceActiveFocus() }
                }
            }
            ListView {
                anchors.top: sideTop.bottom
                anchors.topMargin: 6
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                x: 8
                width: parent.width - 16
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: Notes.files
                delegate: Rectangle {
                    id: fd
                    required property var modelData
                    readonly property bool sel: modelData.path === Notes.current
                    width: ListView.view.width
                    height: 40
                    radius: 10
                    color: sel ? Theme.a(Theme.accent, 0.18) : (fma.containsMouse ? Theme.cardHi : "transparent")
                    Column {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 44
                        Label { text: fd.modelData.name; width: parent.width; size: Theme.fontSmall + 0.5; color: fd.sel ? Theme.accent : Theme.text }
                        Label { text: Qt.formatDateTime(new Date(fd.modelData.mtime), "d MMM · HH:mm"); size: Theme.fontSmall - 1.5; color: Theme.muted }
                    }
                    MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { root.armedDelete = ""; Notes.open(fd.modelData.path); editor.forceActiveFocus() } }
                    // delete: first click arms, second deletes (moves to ~/Notes/.trash)
                    IconButton {
                        visible: fma.containsMouse || root.armedDelete === fd.modelData.path
                        anchors.right: parent.right; anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        size: 24; iconSize: Theme.fontSmall
                        icon: Icons.trash
                        active: root.armedDelete === fd.modelData.path
                        tint: Theme.red
                        onClicked: {
                            if (root.armedDelete === fd.modelData.path) { Notes.remove(fd.modelData.path); root.armedDelete = "" }
                            else root.armedDelete = fd.modelData.path
                        }
                    }
                }
                Label { visible: Notes.files.length === 0; anchors.centerIn: parent; text: "No notes yet"; color: Theme.subtext; size: Theme.fontSmall }
            }
        }

        // editor
        Rectangle {
            id: editorCard
            anchors.left: sidebar.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            height: parent.height
            radius: Theme.radiusCard
            color: Theme.card

            Row {
                id: edHeader
                x: 16; y: 10
                spacing: 8
                Label { text: Notes.currentName || "—"; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Label { text: Notes.dirty ? "editing…" : (Notes.current ? "saved" : ""); color: Theme.muted; size: Theme.fontSmall - 1; anchors.verticalCenter: parent.verticalCenter }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 10; y: 6
                spacing: 4
                Rectangle {
                    width: pvRow.implicitWidth + 16; height: 26; radius: 13
                    color: root.preview ? Theme.a(Theme.accent, 0.2) : (pva.containsMouse ? Theme.cardHi : "transparent")
                    Row { id: pvRow; anchors.centerIn: parent; spacing: 5
                        Glyph { text: Icons.search; size: Theme.fontSmall; color: root.preview ? Theme.accent : Theme.subtext }
                        Label { text: root.preview ? "Edit" : "Preview"; size: Theme.fontSmall } }
                    MouseArea { id: pva; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.preview = !root.preview }
                }
            }

            Flickable {
                id: flick
                anchors.top: edHeader.bottom
                anchors.topMargin: 10
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                contentHeight: root.preview ? previewText.implicitHeight : editor.contentHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                function ensureVisible(r) {
                    if (contentY >= r.y) contentY = r.y
                    else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
                }
                TextEdit {
                    id: editor
                    visible: !root.preview
                    width: flick.width
                    text: Notes.text
                    enabled: Notes.current !== ""
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    color: Theme.text
                    selectionColor: Theme.a(Theme.accent, 0.4)
                    font.family: Theme.font
                    font.pointSize: Theme.fontMono - 1
                    onTextChanged: if (text !== Notes.text) Notes.edit(text)
                    onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
                    Keys.onEscapePressed: { Notes.save(); IslandState.closePanel() }
                    Text {
                        visible: editor.text === ""
                        text: Notes.current ? "Write Markdown…" : "Create a note with “New note” (CTRL+N)"
                        color: Theme.muted
                        font: editor.font
                    }
                }
                Text {
                    id: previewText
                    visible: root.preview
                    width: flick.width
                    text: Notes.text
                    textFormat: Text.MarkdownText
                    wrapMode: Text.Wrap
                    color: Theme.text
                    linkColor: Theme.accent
                    font.family: Theme.font
                    font.pointSize: Theme.fontUi
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
        }
    }

    // ═════════════════════════════ BOARD ═════════════════════════════════
    Item {
        id: board
        anchors.fill: parent
        visible: root.tab === "board"
        property string dragFrom: ""
        property int dragIndex: -1

        Row {
            spacing: 10
            Repeater {
                model: Board.columns
                Rectangle {
                    id: colRect
                    required property var modelData
                    readonly property string colId: modelData.id
                    readonly property var items: Board.cards[colId] ?? []
                    width: (board.width - 20) / 3
                    height: board.height
                    radius: Theme.radiusCard
                    color: drop.containsDrag ? Theme.a(Theme.accent, 0.12) : Theme.card
                    border.width: drop.containsDrag ? Theme.borderWidth : 0
                    border.color: Theme.a(Theme.accent, 0.6)

                    Row {
                        id: colHead
                        x: 14; y: 12
                        spacing: 8
                        Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                                    color: colRect.colId === "todo" ? Theme.subtext : colRect.colId === "doing" ? Theme.yellow : Theme.green }
                        Label { text: colRect.modelData.title; font.bold: true; size: Theme.fontSmall + 1 }
                        Label { text: colRect.items.length; color: Theme.muted; size: Theme.fontSmall }
                    }

                    DropArea {
                        id: drop
                        anchors.fill: parent
                        onDropped: {
                            if (board.dragFrom !== "") Board.move(board.dragFrom, board.dragIndex, colRect.colId)
                            board.dragFrom = ""; board.dragIndex = -1
                        }
                    }

                    ListView {
                        id: cardList
                        anchors.top: colHead.bottom
                        anchors.topMargin: 10
                        anchors.bottom: colRect.colId === "todo" ? addField.top : parent.bottom
                        anchors.bottomMargin: 10
                        x: 10
                        width: parent.width - 20
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        model: colRect.items
                        delegate: Rectangle {
                            id: card
                            required property string modelData
                            required property int index
                            property bool editing: false
                            width: cardList.width
                            height: Math.max(40, (editing ? editInput.implicitHeight : cardText.implicitHeight) + 20)
                            radius: 10
                            color: cma.containsMouse || editing ? Theme.cardHi : Theme.a(Theme.text, 0.05)
                            border.width: Theme.borderWidth
                            border.color: Theme.a(Theme.text, 0.06)
                            opacity: colRect.colId === "done" ? 0.7 : 1
                            Drag.active: cma.drag.active
                            Drag.hotSpot.x: width / 2
                            Drag.hotSpot.y: height / 2
                            // while dragging, float above every column (the lists clip their children)
                            states: State {
                                when: cma.drag.active
                                ParentChange { target: card; parent: dragLayer }
                                PropertyChanges { target: card; z: 100; scale: 1.03; opacity: 0.95 }
                            }

                            // priority stripe
                            readonly property int prio: Board.prio(card.modelData)
                            Rectangle {
                                visible: card.prio > 0
                                width: 4; radius: 2
                                x: 4; y: 8; height: parent.height - 16
                                color: card.prio === 3 ? Theme.red : card.prio === 2 ? Theme.yellow : Theme.accent
                            }
                            Text {
                                id: cardText
                                visible: !card.editing
                                x: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 26 - (cma.containsMouse ? 92 : 0)
                                text: Board.label(card.modelData)
                                wrapMode: Text.Wrap
                                color: Theme.text
                                font.family: Theme.font
                                font.pointSize: Theme.fontSmall + 0.5
                                font.strikeout: colRect.colId === "done"
                            }
                            TextInput {
                                id: editInput
                                visible: card.editing
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24
                                text: Board.label(card.modelData)
                                wrapMode: TextInput.Wrap
                                color: Theme.text
                                font.family: Theme.font
                                font.pointSize: Theme.fontSmall + 0.5
                                selectionColor: Theme.a(Theme.accent, 0.4)
                                // keep the priority prefix when the text is edited
                                function withPrio(t) { const p = Board.prio(card.modelData); return (p ? "!".repeat(p) + " " : "") + t }
                                onAccepted: { Board.rename(colRect.colId, card.index, withPrio(text)); card.editing = false }
                                Keys.onEscapePressed: card.editing = false
                                onActiveFocusChanged: if (!activeFocus && card.editing) { Board.rename(colRect.colId, card.index, withPrio(text)); card.editing = false }
                            }
                            MouseArea {
                                id: cma
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !card.editing
                                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                drag.target: card
                                drag.axis: Drag.XAndYAxis
                                onPressed: { board.dragFrom = colRect.colId; board.dragIndex = card.index }
                                onReleased: { if (drag.active) card.Drag.drop() }
                                onClicked: { card.editing = true; editInput.forceActiveFocus(); editInput.selectAll() }
                            }
                            // hover actions: ◀ ▶ ×
                            Row {
                                visible: cma.containsMouse && !card.editing
                                anchors.right: parent.right; anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0
                                IconButton { size: 22; iconSize: Theme.fontSmall - 1; icon: Icons.flag
                                             tint: card.prio === 3 ? Theme.red : card.prio === 2 ? Theme.yellow : Theme.accent; active: card.prio > 0
                                             onClicked: Board.cyclePrio(colRect.colId, card.index) }
                                IconButton { size: 22; iconSize: Theme.fontSmall - 1; icon: Icons.chevronL; visible: colRect.colId !== "todo"; onClicked: Board.shift(colRect.colId, card.index, -1) }
                                IconButton { size: 22; iconSize: Theme.fontSmall - 1; icon: Icons.chevronR; visible: colRect.colId !== "done"; onClicked: Board.shift(colRect.colId, card.index, 1) }
                                IconButton { size: 22; iconSize: Theme.fontSmall - 1; icon: Icons.close; tint: Theme.red; onClicked: Board.remove(colRect.colId, card.index) }
                            }
                        }
                        Label {
                            visible: colRect.items.length === 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 20
                            text: colRect.colId === "done" ? "Nothing finished yet" : "Drop cards here"
                            color: Theme.muted
                            size: Theme.fontSmall
                        }
                    }

                    SearchField {
                        id: addField
                        visible: colRect.colId === "todo"
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10
                        x: 10
                        width: parent.width - 20
                        implicitHeight: 34
                        placeholder: "Add a card, Enter"
                        onAccepted: { Board.add("todo", text); text = "" }
                        Component.onCompleted: if (colRect.colId === "todo") root.addFieldRef = addField
                    }
                }
            }
        }
        // dragged cards are reparented here so they render above all columns
        Item { id: dragLayer; anchors.fill: parent; z: 100 }
    }

    property var addFieldRef: null
}
