# VPN Status Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a button between the gear icon and the island's pill that shows whether a full-tunnel VPN (Tailscale exit node, a raw WireGuard tunnel such as the user's ProtonVPN `wg-quick` setup, or OpenConnect) is currently active, with a hover tooltip showing Tailscale mesh state, the active tunnel, and a cached public IP + city/country.

**Architecture:** One new `services/Vpn.qml` singleton polls three detection commands on a timer and derives `fullTunnel`/`anyBackendAvailable`, then fetches and caches a geolocation lookup only on connection transitions. `components/SideButton.qml` gets one additive `hovered` alias. `ui/Island.qml` gets a new `SideButton` instance slotted between `gearBtn` and `pill`, with a `Hint` tooltip as its child.

**Tech Stack:** QML (Quickshell), `sh`/coreutils (`tailscale`, `ip`, `pgrep`, `curl`), Arch pacman packages.

**Spec:** `docs/superpowers/specs/2026-11-16-vpn-status-indicator-design.md`

## Global Constraints

- No `sudo` anywhere in the probe or geolocation commands.
- Reuse the existing `Icons.shieldLock` glyph (`g(0xF099D)`) — no new codepoint.
- Active-state tint is the fixed color `win.catGreen` (`#a6e3a1`), not `Theme.accent` — matches the existing fixed-meaning-indicator convention (`updatesPill`).
- Plain Tailscale mesh (no exit node) must never set `fullTunnel`/drive the button's `active` state — only an exit node, a non-Tailscale WireGuard interface, or OpenConnect does.
- Geolocation is fetched at most once per full-tunnel connection/backend transition, never on every hover.
- `pkglist.txt` gets `tailscale`, `iproute2`, `wireguard-tools`, `openconnect` — every command the probe or the user's existing setup calls must be declared there (official `extra` repo only, no AUR).
- New `.qml` files are not picked up by Quickshell's hot reload — run `~/.config/hypr/scripts/island.sh restart` after creating `Vpn.qml`.
- Hot reload resets island UI state (open panel, perspective) — wait ~3s after saving before testing, and never hard-kill a running instance with a focused text field (use `island.sh stop`, not `kill -9`).
- Validation command for every QML task: `qs log -c kessel | grep -E 'WARN|ERROR|caused'` after `island.sh restart` — any new output is a bug to fix before moving on.

## Review Focus

- No VPN tooling installed at all (`tailscale`/`ip`/`openconnect` all absent): the button must hide (`visible: false`), not show a broken/empty state — tested in Task 2 by running the probe script with a stripped `PATH`.
- Tailscale installed but logged out / daemon down (`tailscale status --json` fails or returns unexpected JSON): must not crash the parse or leave stale `true` flags — tested in Task 2 with a non-JSON/garbage stdin fixture.
- Geolocation request fails (timeout, VPN briefly drops route mid-lookup): `geoLabel` must stay empty rather than show garbage, and nothing appears in `qs log` as an ERROR — tested in Task 3 with an unreachable host.
- Rapid connect/disconnect (fast transitions) must not spawn overlapping probe or geolocation processes — tested in Task 2 and Task 3 by asserting both `Process` blocks guard on `!proc.running` before setting `running = true`.
- A backend switch while `fullTunnel` stays continuously `true` (e.g. WireGuard tunnel drops, OpenConnect picks up without an intervening `false`) must still trigger a fresh geolocation lookup, not reuse the stale cached one — tested in Task 3 by changing `backendKey` without transitioning through `""`.

---

## Task 1: Declare VPN packages

**Files:**
- Modify: `pkglist.txt:44` (insert after the existing `nm-connection-editor` line)

**Interfaces:**
- Produces: nothing code-facing; later tasks assume `tailscale`, `ip`, `wg`/`wg-quick`, `openconnect`, `pgrep`, `curl` are available on this machine.

- [ ] **Step 1: Add the new package block**

Insert immediately after the `nm-connection-editor` line:

```
# VPN status indicator (services/Vpn.qml): Tailscale mesh/exit-node,
# raw WireGuard tunnels (e.g. the user's ProtonVPN wg-quick setup), OpenConnect
tailscale
iproute2                # `ip -o link show type wireguard` detects a non-Tailscale tunnel
wireguard-tools         # wg-quick config (ProtonVPN) — not called by the probe, but what it detects
openconnect
```

- [ ] **Step 2: Verify no duplicates and correct syntax**

Run: `grep -c '^tailscale$\|^iproute2$\|^wireguard-tools$\|^openconnect$' pkglist.txt`
Expected: `4` (each appears exactly once)

Run: `./install.sh --dry-run --with-aur --apply-config`
Expected: dry-run reports the four new packages as to-install (or already-installed, since they're present on this dev machine); no errors, no unrelated changes.

- [ ] **Step 3: Commit**

```bash
git add pkglist.txt
git commit -m "pkglist: declare tailscale/iproute2/wireguard-tools/openconnect for the VPN status indicator"
```

## Task 2: Vpn.qml — detection probe

**Files:**
- Create: `.config/quickshell/kessel/services/Vpn.qml`

**Interfaces:**
- Produces (consumed by Task 3 and Task 5):
  - `readonly property bool tailscaleAvailable`
  - `readonly property bool tailscaleUp`
  - `readonly property string tailscaleIp` (empty string if none)
  - `readonly property bool exitNodeActive`
  - `readonly property bool wgAvailable`
  - `readonly property string wgInterface` (empty string if no non-Tailscale WireGuard interface is up)
  - `readonly property bool openconnectAvailable`
  - `readonly property bool openconnectUp`
  - `readonly property bool fullTunnel` — `exitNodeActive || wgInterface !== "" || openconnectUp`
  - `readonly property bool anyBackendAvailable` — `tailscaleAvailable || wgAvailable || openconnectAvailable`

- [ ] **Step 1: Write the probe shell script and confirm its output shape manually**

The probe (one `sh -c` invocation, run directly in a terminal first to confirm the output format before wiring it into QML):

```sh
if command -v tailscale >/dev/null 2>&1; then
  echo "TSAVAIL=1"
  tailscale status --json 2>/dev/null
else
  echo "TSAVAIL=0"
fi
echo "==END_TS=="
if command -v ip >/dev/null 2>&1; then
  echo "WGAVAIL=1"
  ip -o link show type wireguard 2>/dev/null
else
  echo "WGAVAIL=0"
fi
echo "==END_WG=="
if command -v openconnect >/dev/null 2>&1; then
  echo "OCAVAIL=1"
else
  echo "OCAVAIL=0"
fi
pgrep -x openconnect >/dev/null 2>&1 && echo "OCUP=1" || echo "OCUP=0"
```

Run it directly (save to a scratch `.sh` file, `sh that_file.sh`) on this machine (Tailscale active, so `TSAVAIL=1` and real JSON should appear) and confirm: the `tailscale status --json` blob parses as valid JSON via `jq .` piped from the `TSAVAIL=1`-to-`==END_TS==` block, and that JSON contains either no `ExitNodeStatus` key or a non-null one depending on current exit-node state.

Then re-run it with a stripped PATH to confirm the "nothing installed" path: `env -i PATH=/nonexistent sh -c '<same script>'` — expect `TSAVAIL=0`, `WGAVAIL=0`, `OCAVAIL=0`, `OCUP=0`, no shell errors.

- [ ] **Step 2: Create `services/Vpn.qml` with the `Process` + `Timer`, following the `Gpu.qml` pattern**

```qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // ... properties listed in Interfaces above ...

    Process {
        id: proc
        command: ["sh", "-c", `<the Step 1 script, as a template literal>`]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!proc.running) proc.running = true }

    function parse(t) { /* see guidance below */ }
}
```

Parsing guidance (the algorithm, not a transcript): split `t` on `"==END_TS==\n"` then on `"==END_WG==\n"` to get three chunks (Tailscale block, WireGuard block, OpenConnect block). First line of the Tailscale chunk is `TSAVAIL=0` or `1`; if `1`, `JSON.parse` the remaining lines wrapped in a `try/catch` (parse failure or a `NeedsLogin`/non-running `BackendState` just leaves `tailscaleUp`/`tailscaleIp`/`exitNodeActive` at their default `false`/`""` — do not let a catch block throw further). `tailscaleUp` is `json.BackendState === "Running"`; `tailscaleIp` is `json.Self?.TailscaleIPs?.[0] ?? ""`; `exitNodeActive` is `json.ExitNodeStatus !== undefined && json.ExitNodeStatus !== null`. First line of the WireGuard chunk is `WGAVAIL=0`/`1`; remaining lines are `ip -o link show` output — take the first interface name (field after the leading `N: `, before any `@`/`:`) as `wgInterface`, or `""` if no lines remain. The OpenConnect chunk has exactly two lines, `OCAVAIL=...` and `OCUP=...`.

- [ ] **Step 3: Wire it into the island and verify in place**

Run: `~/.config/hypr/scripts/island.sh restart`
Run: `qs log -c kessel | grep -E 'WARN|ERROR|caused'`
Expected: no new output referencing `Vpn.qml`.

Run: `qs -c kessel ipc show` or add a temporary `console.log` inside `parse()` (remove before commit) to confirm `tailscaleUp`, `tailscaleIp`, and `exitNodeActive` match the real state observed in Step 1's manual run.

- [ ] **Step 4: Verify malformed-input handling without touching the real Tailscale connection**

Don't stop the real `tailscaled` to test this (it would drop the user's actual Tailscale connection). Instead, temporarily add a one-shot call — e.g. a `Component.onCompleted: console.log(JSON.stringify(parse("TSAVAIL=1\nnot valid json at all\n==END_TS==\nWGAVAIL=0\n==END_WG==\nOCAVAIL=0\nOCUP=0\n")))`, or wire it to a throwaway `Timer` that fires once — feeding `parse()` deliberately broken JSON after `TSAVAIL=1`. Restart the island, check `qs log -c kessel`: no `ERROR`/`caused` line, and the resulting `tailscaleUp`/`tailscaleIp`/`exitNodeActive` stay at their `false`/`""` defaults rather than throwing. Remove the temporary call afterward.

- [ ] **Step 5: Commit**

```bash
git add .config/quickshell/kessel/services/Vpn.qml
git commit -m "island: add Vpn service detecting Tailscale/WireGuard/OpenConnect state"
```

## Task 3: Vpn.qml — geolocation caching

**Files:**
- Modify: `.config/quickshell/kessel/services/Vpn.qml`

**Interfaces:**
- Consumes: `fullTunnel`, `exitNodeActive`, `wgInterface`, `openconnectUp` (Task 2)
- Produces (consumed by Task 5):
  - `readonly property string geoIp` (empty string until resolved)
  - `readonly property string geoLabel` (`"City, Country"`, empty string until resolved or when `fullTunnel` is false)

- [ ] **Step 1: Confirm the geolocation endpoint manually**

Run: `curl -s --max-time 3 https://ipapi.co/json/`
Expected: JSON containing `ip`, `city`, `country_name` fields.

- [ ] **Step 2: Add `backendKey`, the geolocation `Process`, and the trigger handler**

```qml
readonly property string backendKey: !fullTunnel ? ""
    : exitNodeActive ? "exit"
    : wgInterface !== "" ? "wg:" + wgInterface
    : "oc"
onBackendKeyChanged: {
    if (backendKey === "") { geoIp = ""; geoLabel = ""; return }
    if (!geoProc.running) geoProc.running = true
}
property string geoIp: ""
property string geoLabel: ""
Process {
    id: geoProc
    command: ["sh", "-c", "curl -s --max-time 3 https://ipapi.co/json/"]
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                const j = JSON.parse(text)
                root.geoIp = j.ip ?? ""
                root.geoLabel = (j.city && j.country_name) ? `${j.city}, ${j.country_name}` : ""
            } catch (e) { root.geoIp = ""; root.geoLabel = "" }
        }
    }
}
```

(`geoIp`/`geoLabel` must be plain `property`, not `readonly`, since `parse()`/the collector assign them from inside the singleton — matches the `readonly property var all` vs. internal-assignment split already used in `Gpu.qml`.)

- [ ] **Step 3: Verify transition behavior**

Run: `~/.config/hypr/scripts/island.sh restart`, then connect/disconnect the WireGuard tunnel or Tailscale exit node (whichever is convenient) and watch `qs log -c kessel` for errors while confirming (via a temporary `console.log`, removed before commit) that `geoProc.running` only goes `true` once per transition, not repeatedly.

Run: with the tunnel down, confirm `geoLabel` reads back as `""`.

Run: temporarily point `geoProc`'s command at an unreachable address (e.g. `curl -s --max-time 3 http://10.255.255.1/`) to simulate a failed lookup, restart, trigger a transition, and confirm `geoIp`/`geoLabel` stay `""` with no `ERROR`/`caused` line in `qs log -c kessel`. Revert the command string afterward.

If both a WireGuard tunnel and OpenConnect are available to test with: bring one up, let `geoLabel` resolve, then switch directly to the other without dropping `fullTunnel` to `false` in between (e.g. bring the second up before tearing the first down) and confirm `backendKey` changes value and a fresh `geoProc` run fires rather than keeping the first lookup's stale result. If this isn't practical to stage live, it's acceptable to verify by inspection instead — confirm `backendKey`'s expression produces a different string for each distinct active backend — and say so explicitly rather than claiming it was exercised live.

- [ ] **Step 4: Commit**

```bash
git add .config/quickshell/kessel/services/Vpn.qml
git commit -m "island: cache a geolocation lookup per VPN connection transition"
```

## Task 4: SideButton hover property

**Files:**
- Modify: `.config/quickshell/kessel/components/SideButton.qml`

**Interfaces:**
- Produces (consumed by Task 5): `readonly property alias hovered: ma.containsMouse` on `SideButton`, where `ma` is the component's existing internal `MouseArea`.

- [ ] **Step 1: Add the alias**

Add `readonly property alias hovered: ma.containsMouse` alongside the other `property` declarations at the top of the `Rectangle` (near `property bool active: false`).

- [ ] **Step 2: Verify existing buttons are unaffected**

Run: `~/.config/hypr/scripts/island.sh restart`
Run: `qs log -c kessel | grep -E 'WARN|ERROR|caused'`
Expected: no new output. Manually hover the gear and bell buttons in the running island; both must behave exactly as before (no visual change — `hovered` is additive and nothing reads it yet).

- [ ] **Step 3: Commit**

```bash
git add .config/quickshell/kessel/components/SideButton.qml
git commit -m "components: expose SideButton hover state for external tooltips"
```

## Task 5: Wire the VPN button into the island

**Files:**
- Modify: `.config/quickshell/kessel/ui/Island.qml`

**Interfaces:**
- Consumes: `Vpn.anyBackendAvailable`, `Vpn.fullTunnel`, `Vpn.tailscaleAvailable`, `Vpn.tailscaleUp`, `Vpn.tailscaleIp`, `Vpn.exitNodeActive`, `Vpn.wgInterface`, `Vpn.openconnectUp`, `Vpn.geoIp`, `Vpn.geoLabel` (Task 2 + 3); `SideButton.hovered` (Task 4); `Icons.shieldLock` (existing); `win.catGreen` (existing, `ui/Island.qml:23`).

- [ ] **Step 1: Add `vpnBtn` and re-slot `gearBtn`**

Change:
```qml
SideButton {
    id: gearBtn
    y: 0
    x: pill.x - width - 8
```
to:
```qml
SideButton {
    id: vpnBtn
    y: 0
    x: pill.x - width - 8
    visible: Vpn.anyBackendAvailable
    icon: Icons.shieldLock
    tint: win.catGreen
    active: Vpn.fullTunnel
    Hint {
        visible: vpnBtn.hovered
        text: [
            Vpn.tailscaleAvailable ? "Tailscale: " + (Vpn.tailscaleUp ? "up" + (Vpn.tailscaleIp !== "" ? ` (${Vpn.tailscaleIp})` : "") : "down") : "",
            Vpn.fullTunnel ? "Tunnel: " + (Vpn.exitNodeActive ? "Tailscale exit node" : Vpn.wgInterface !== "" ? `WireGuard (${Vpn.wgInterface})` : "OpenConnect") : "No full-tunnel VPN",
            Vpn.geoLabel !== "" ? `${Vpn.geoIp} — ${Vpn.geoLabel}` : ""
        ].filter(s => s).join("\n")
    }
}
SideButton {
    id: gearBtn
    y: 0
    x: vpnBtn.x - width - 8
```
(keep the rest of `gearBtn`'s existing body — `icon`, `active`, `onClicked` — unchanged below the `x:` line.)

- [ ] **Step 2: Add `vpnBtn` to the layershell mask**

In the `mask: Region { ... }` block, add `Region { item: vpnBtn }` alongside the existing `Region { item: gearBtn }` line.

- [ ] **Step 3: Restart and visually verify**

Run: `~/.config/hypr/scripts/island.sh restart`, wait ~3s.
Run: `qs log -c kessel | grep -E 'WARN|ERROR|caused'` — expect no new output.
Take a screenshot of the island (`grim -g "x,y wxh" /tmp/island.png`, logical coordinates from `hyprctl clients` or similar) and confirm the new button renders between the gear and the pill, tinted `catGreen` only while a full-tunnel VPN is actually active on this machine.
Hover the button and confirm the tooltip appears below it with the three expected lines (omitting the geo line until the first lookup resolves).
Click the button and confirm nothing breaks (no `onClicked` is wired — this is intentionally a read-only indicator).

- [ ] **Step 4: Commit**

```bash
git add .config/quickshell/kessel/ui/Island.qml
git commit -m "island: show a VPN status button between the gear icon and the pill"
```
