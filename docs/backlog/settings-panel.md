# Settings panel in the island

> Tracked as issue #1 in this repo's tracker.

**Type:** feature · **Priority:** later

A settings page inside the island, inspired by Panacea and Impasto, for ordinary preferences that should not require editing files:

- Theme: dark/light, accent source (wallpaper / fixed color), wallpaper folder
- Island: perspectives on/off and order, hover delay, side buttons, screen-corner radius, spring feel (stiffness/damping)
- Weather location + units, night-light temperature and schedule (auto / fixed times)
- Notifications: timeout, DND schedule
- Launcher: which sources (apps / calculator / URLs / translation), default translation languages
- Keybinds: read-only overview with conflict check (editing later)

**Approach:** a `Settings` service reads and writes `~/.config/kessel/settings.json`, watches it live, and layers it over the defaults in `Config.qml`. Generated theme files still come from `theme.sh`. The setup must remain usable without the panel: the file is the source of truth.
