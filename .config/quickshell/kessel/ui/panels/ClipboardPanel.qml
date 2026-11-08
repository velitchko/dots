// SPDX-License-Identifier: GPL-3.0-or-later
// Clipboard history (SUPER+V): Enter copies, Delete removes, images get thumbnails.
import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "../../services"
import "../../components"

PanelBase {
    id: root
    title: "Clipboard"
    icon: Icons.clipboard
    contentWidth: 520
    contentHeight: search.height + 10 + list.height

    headerExtra: IconButton { icon: Icons.trash; size: 26; iconSize: Theme.fontSmall + 2; onClicked: Clipboard.wipe() }

    readonly property var results: {
        const q = search.text.toLowerCase()
        return q === "" ? Clipboard.entries : Clipboard.entries.filter(e => !e.image && e.text.toLowerCase().indexOf(q) >= 0)
    }

    Component.onCompleted: Clipboard.refresh()
    onActiveFocusChanged: if (activeFocus) search.focusInput()

    function copyCurrent() {
        const e = results[list.currentIndex]
        if (!e) return
        Clipboard.copy(e)
        IslandState.closePanel()
    }

    SearchField {
        id: search
        width: parent.width
        placeholder: "Search clipboard"
        onTextChanged: list.currentIndex = 0
        onAccepted: root.copyCurrent()
        onUp: { list.keyNav = true; keyNavTimer.restart(); list.decrementCurrentIndex() }
        onDown: { list.keyNav = true; keyNavTimer.restart(); list.incrementCurrentIndex() }
        input.Keys.onDeletePressed: { const e = root.results[list.currentIndex]; if (e) Clipboard.remove(e) }
    }

    ListView {
        id: list
        anchors.top: search.bottom
        anchors.topMargin: 10
        width: parent.width
        height: Math.min(420, Math.max(48, contentHeight))
        clip: true
        spacing: 4
        model: root.results
        highlightMoveDuration: 120
        boundsBehavior: Flickable.StopAtBounds
        highlight: Rectangle { radius: 12; color: Theme.cardHi }

        // Arrow-key nav auto-scrolls the list to follow currentIndex; without this,
        // whatever row scrolls under the (unmoved) mouse cursor fires onEntered and
        // immediately steals currentIndex back, fighting the keyboard. 200ms covers
        // highlightMoveDuration (120) plus the scroll settling.
        property bool keyNav: false
        Timer { id: keyNavTimer; interval: 200; onTriggered: list.keyNav = false }

        delegate: Item {
            id: d
            required property var modelData
            required property int index
            width: list.width
            height: modelData.image ? 92 : 40

            readonly property string url: !modelData.image && /^https?:\/\/\S+$/i.test(modelData.text.trim()) ? modelData.text.trim() : ""
            Label {
                visible: !d.modelData.image
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: d.url !== "" ? 44 : 12
                anchors.verticalCenter: parent.verticalCenter
                text: d.modelData.text
                textFormat: Text.PlainText
            }
            Row {
                visible: d.modelData.image
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Rectangle {
                    width: 120; height: 76; radius: 8
                    color: Theme.overlay
                    clip: true
                    Image {
                        id: thumb
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        sourceSize: Qt.size(240, 152)
                    }
                    Glyph { anchors.centerIn: parent; text: Icons.image; color: Theme.subtext; visible: thumb.status !== Image.Ready }
                }
                Label { text: d.modelData.text.replace(/^\[\[ binary data /, "").replace(/ \]\]$/, ""); color: Theme.subtext; size: Theme.fontSmall; anchors.verticalCenter: parent.verticalCenter }
            }
            Process {
                running: d.modelData.image
                command: Clipboard.thumbCommand(d.modelData)
                onExited: thumb.source = "file://" + Clipboard.thumbPath(d.modelData)
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: if (!list.keyNav) list.currentIndex = d.index
                onClicked: { list.currentIndex = d.index; root.copyCurrent() }
            }
            IconButton {
                visible: d.url !== ""
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                size: 28
                iconSize: Theme.fontSmall + 1
                icon: Icons.openExt
                onClicked: { Quickshell.execDetached(["xdg-open", d.url]); IslandState.closePanel() }
            }
        }
        Label { visible: list.count === 0; anchors.centerIn: parent; text: "Clipboard history is empty"; color: Theme.subtext }
    }
}
