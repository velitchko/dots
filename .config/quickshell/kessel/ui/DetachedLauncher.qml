// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone launcher window, used only while the island itself is in focus
// mode (SUPER+Space hid it): opening the launcher then should show just the
// launcher, not un-hide the whole island and its side buttons. A plain
// QtQuick.Window (not PanelWindow/layer-shell), same approach as
// AiChatWindow.qml -- Hyprland floats + centers it (workspaces.lua), so it
// lands on whichever monitor is focused without any per-screen wiring.
import QtQuick
import QtQuick.Window
import ".."
import "../services"
import "panels"

Window {
    id: win
    title: "Kessel Launcher"
    width: launcher.implicitWidth
    height: launcher.implicitHeight
    visible: IslandState.detachedLauncher
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    onClosing: IslandState.closePanel()
    onActiveChanged: if (!active) IslandState.closePanel()
    Component.onCompleted: launcher.forceActiveFocus()

    Rectangle {
        anchors.fill: parent
        // Matches general.lua's decoration.rounding (10), same convention as
        // AiChatWindow: Hyprland draws the real border, this just shouldn't
        // visibly disagree with it.
        color: Theme.island
        radius: 10

        Launcher { id: launcher }
    }
}
