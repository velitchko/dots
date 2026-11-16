# Island services

Singletons without UI: state, D-Bus, PipeWire, processes. Views in `../ui/` only read them.

| Service | Role |
| --- | --- |
| `IslandState` | Layer arbitration (alarm > panel > notification > osd > summary > rest) + **all IPC** (`qs -c kessel ipc show`) |
| `Perspectives` | Resting perspectives (overview · time · music · metrics · minimal), auto music mode |
| `Time`, `Weather`, `User` | Clock; wttr.in + Open-Meteo (7 days, sunrise/sunset); user/host/avatar/uptime |
| `Media`, `Cava` | MPRIS player (wraps looping positions); cava visualizer (runs only when shown) |
| `Audio`, `Privacy` | PipeWire sinks/sources/per-app streams (classified by `PwNodeType`); mic/camera/screen-share in use |
| `Notifs` | Notification server (dunst takes over via D-Bus when the island is down) |
| `Net`, `Bt`, `Power`, `Brightness`, `NightLight` | NetworkManager, BlueZ, UPower + power profiles, backlight, hyprsunset; hidden when absent |
| `Gpu` | GPU load/VRAM/temp (nvidia-smi, amdgpu sysfs, Intel temp only); suspended laptop dGPUs are never woken |
| `Apps`, `Calc`, `Translator`, `Clipboard` | Launcher sources: desktop entries, qalc/built-in maths, offline translation, cliphist |
| `Notes`, `Board` | `~/Notes/*.md` editor, kanban board in `~/Notes/Board.md` |
| `Timers`, `Alarm`, `Recorder`, `Session`, `Utils`, `Themes`, `Hypr`, `Stats` | Timer/stopwatch, alarm, wf-recorder, power actions + idle inhibit, one-shot tools, wallpaper/theme, Hyprland workspaces/windows, CPU/RAM/net |

Adding one: create `Name.qml` with `pragma Singleton` and `Singleton { … }`, then **restart** the island (new files aren't hot-reloaded). Avoid names of QtQuick types (e.g. `Translate`).
