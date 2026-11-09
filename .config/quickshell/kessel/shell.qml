// SPDX-License-Identifier: GPL-3.0-or-later
// Kessel — dynamic island. Run: qs -c kessel
// Optional by design: Hyprland, kitty and fuzzel never depend on this.
import QtQuick
import Quickshell
import "ui"
import "services"

ShellRoot {
    // rounded screen corners (Theme.screenCornerRadius; 0 = off)
    Variants {
        model: Theme.screenCornerRadius > 0 ? Quickshell.screens : []
        ScreenCorners { required property var modelData; screen: modelData }
    }

    Variants {
        model: Quickshell.screens
        Island {
            required property var modelData
            screen: modelData
        }
    }

    // Whole-screen crossfade while the theme switches (see ui/ThemeFade.qml).
    Variants {
        model: IslandState.frozen ? Quickshell.screens : []
        ThemeFade { required property var modelData; screen: modelData }
    }

    // Graceful quit (island.sh stop): give the windows a moment to drop focus
    // and unload panels, then exit normally.
    Timer {
        running: IslandState.quitting
        interval: 250
        onTriggered: Qt.quit()
    }

    // Instantiate services that must run even before any UI reads them.
    Component.onCompleted: {
        IslandState.shown = true
        void Notifs.count
        void Audio.ready
        void Brightness.available
    }
}
