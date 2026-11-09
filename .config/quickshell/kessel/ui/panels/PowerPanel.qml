// SPDX-License-Identifier: GPL-3.0-or-later
// Session menu (SUPER+Escape). ←/→ to choose, Enter twice for destructive actions.
import QtQuick
import "../.."
import "../../services"
import "../../components"

PanelBase {
    id: root
    title: "Session"
    icon: Icons.power
    contentWidth: 5 * 104 + 4 * 10
    contentHeight: 120

    property int sel: 0
    property int armed: -1
    readonly property var actions: [
        { icon: Icons.lock,    label: "Lock",     confirm: false, run: () => Session.lock() },
        { icon: Icons.sleep,   label: "Standby",  confirm: false, run: () => Session.suspend() },
        { icon: Icons.logout,  label: "Log out",  confirm: true,  run: () => Session.logout() },
        { icon: Icons.restart, label: "Restart",  confirm: true,  run: () => Session.reboot() },
        { icon: Icons.power,   label: "Shut down", confirm: true, run: () => Session.poweroff() }
    ]

    function trigger(i) {
        sel = i
        const a = actions[i]
        if (a.confirm && armed !== i) { armed = i; disarm.restart(); return }
        IslandState.closePanel()
        a.run()
    }
    Timer { id: disarm; interval: 3000; onTriggered: root.armed = -1 }

    focus: true
    Keys.onLeftPressed: { sel = (sel + actions.length - 1) % actions.length; armed = -1 }
    Keys.onRightPressed: { sel = (sel + 1) % actions.length; armed = -1 }
    Keys.onReturnPressed: trigger(sel)
    Keys.onEnterPressed: trigger(sel)

    Row {
        spacing: 10
        Repeater {
            model: root.actions
            Rectangle {
                required property var modelData
                required property int index
                readonly property bool isArmed: root.armed === index
                width: 104; height: 110
                radius: 22
                color: isArmed ? Theme.a(Theme.red, 0.25) : (root.sel === index || ma.containsMouse ? Theme.cardHi : Theme.card)
                border.width: root.sel === index ? Theme.borderWidth : 0
                border.color: isArmed ? Theme.red : Theme.a(Theme.accent, 0.6)
                Behavior on color { ColorAnimation { duration: Theme.fadeMs } }
                // Labels are held to the card's width (centred, wrapping): the old
                // armed text "Again to confirm" was wider than the 104 px card.
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 12
                    spacing: 6
                    Glyph { text: modelData.icon; size: 22; color: isArmed ? Theme.red : Theme.text; anchors.horizontalCenter: parent.horizontalCenter }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        text: modelData.label
                        size: Theme.fontSmall
                        font.bold: isArmed
                        color: isArmed ? Theme.red : Theme.text
                    }
                    // armed: a short second line instead of replacing the label
                    Label {
                        width: parent.width
                        visible: isArmed
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        text: "Press again"
                        size: Theme.fontSmall - 1
                        color: Theme.a(Theme.red, 0.85)
                    }
                }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: root.sel = index; onClicked: root.trigger(index) }
            }
        }
    }
}
