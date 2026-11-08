// SPDX-License-Identifier: GPL-3.0-or-later
// One notification: icon/image, app, summary, body, actions.
// Click = focus the app (runs its default action, else focuses its window).
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import ".."
import "../services"

Rectangle {
    id: root
    required property var notif
    property bool inList: false
    readonly property bool critical: notif?.urgency === NotificationUrgency.Critical

    implicitWidth: 400
    implicitHeight: Math.max(64, body.implicitHeight + 24)
    radius: Theme.radiusCard
    color: ma.containsMouse ? Theme.cardHi : (inList ? Theme.card : "transparent")
    border.width: critical ? 1 : 0
    border.color: Theme.red

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
    }

    function activate() {
        const n = root.notif
        // notify-send exits immediately, so it can never receive a real D-Bus
        // action click-back -- screenshot.sh/Recorder.qml instead pass the path
        // in a custom hint. Checked before the generic app-focus fallback, which
        // has no window to find for a one-shot CLI notification anyway.
        const openPath = n.hints ? n.hints["x-kessel-open-path"] : undefined
        if (openPath) {
            Quickshell.execDetached(["dolphin", "--select", openPath])
            Notifs.dismiss(n)
            IslandState.closePanel()
            return
        }
        const hasDefault = n.actions.some(a => a.identifier === "default")
        if (!hasDefault) Hypr.focusApp([n.desktopEntry, n.appName])
        Notifs.activate(n)
        IslandState.closePanel()
    }

    Rectangle {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.top: parent.top
        anchors.topMargin: 12
        width: 40; height: 40; radius: 12
        color: Theme.overlay
        clip: true
        Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.notif?.image || (root.notif?.appIcon ? Quickshell.iconPath(root.notif.appIcon, true) : "")
            visible: status === Image.Ready
        }
        Glyph { anchors.centerIn: parent; text: Icons.bellRing; color: root.critical ? Theme.red : Theme.accent; visible: parent.children[0].status !== Image.Ready }
    }

    Column {
        id: body
        anchors.left: icon.right
        anchors.leftMargin: 12
        anchors.right: closeBtn.left
        anchors.rightMargin: 6
        anchors.top: parent.top
        anchors.topMargin: 12
        spacing: 3

        Label { text: root.notif?.appName || "Notification"; size: Theme.fontSmall - 0.5; color: Theme.subtext; width: parent.width }
        Label { text: root.notif?.summary ?? ""; font.bold: true; width: parent.width }
        Text {
            text: root.notif?.body ?? ""
            visible: text !== ""
            width: parent.width
            wrapMode: Text.Wrap
            maximumLineCount: root.inList ? 3 : 4
            elide: Text.ElideRight
            textFormat: Text.StyledText
            color: Theme.subtext
            font.family: Theme.font
            font.pointSize: Theme.fontSmall
        }
        Row {
            spacing: 6
            topPadding: 4
            visible: actRep.count > 0
            Repeater {
                id: actRep
                model: (root.notif?.actions ?? []).filter(a => a.identifier !== "default")
                Rectangle {
                    required property var modelData
                    height: 26
                    width: actLabel.implicitWidth + 20
                    radius: 13
                    color: actMa.containsMouse ? Theme.a(Theme.accent, 0.3) : Theme.a(Theme.accent, 0.15)
                    Label { id: actLabel; anchors.centerIn: parent; text: parent.modelData.text; size: Theme.fontSmall; color: Theme.accent }
                    MouseArea { id: actMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.invoke(root.notif, parent.modelData) }
                }
            }
        }
    }

    IconButton {
        id: closeBtn
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.top: parent.top
        anchors.topMargin: 8
        icon: Icons.close
        size: 24
        iconSize: Theme.fontSmall + 1
        onClicked: Notifs.dismiss(root.notif)
    }
}
