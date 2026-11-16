# VPN status indicator — design

## Intent and why

The user runs Tailscale essentially all the time (mesh networking, not an
egress tunnel) and layers one of several full-tunnel VPNs on top of it when
needed: a Tailscale exit node, a manually-configured WireGuard tunnel (this
is how they run ProtonVPN — raw `wg-quick` config, not Proton's own
app/CLI), or OpenConnect. There is currently no at-a-glance way to tell,
from the island, whether traffic is actually leaving the machine through a
VPN right now. The ask: a new optional button between the gear icon and the
island's pill, indicating VPN state, with a mouseover that resolves the
current public IP and its city/country.

## Goals

- One button, between `gearBtn` and `pill`, that reflects whether a
  **full-tunnel** VPN (one that changes the egress IP) is currently active.
- Supports, as detection sources: Tailscale (mesh + exit-node mode),
  generic kernel WireGuard interfaces (covers the user's ProtonVPN setup),
  and OpenConnect.
- Hides itself entirely on a machine with none of the three tools
  installed, per this repo's "hardware/service-dependent UI hides itself"
  convention.
- Mouseover/tooltip shows Tailscale mesh state (even when not driving the
  icon), the active full-tunnel backend and its local IP, and a
  once-per-connection, cached public IP + city/country.

## Non-goals

- Not a VPN control surface (no connect/disconnect/switch-exit-node
  actions from this button) — read-only status, click behavior out of
  scope unless trivial (TBD in plan: likely no click action, or opens
  `nm-connection-editor`/a terminal at most).
- Not a general network-quality or latency indicator.
- Not replacing `services/Net.qml` (Wi-Fi/wired) — this is VPN-specific
  and additive.

## Anti-goals

- Icon must **not** read as "on" just because Tailscale mesh is up — that
  would make it permanently lit for this user and useless as a signal.
  Mesh-only Tailscale is visible only in the tooltip.
- No fresh external geolocation request on every hover — one request per
  connection-state transition, cached.
- No new Nerd Font codepoint guessed from memory — reuse an
  already-verified glyph (`Icons.shieldLock`) rather than adding one.

## Constraints

- Must follow existing island conventions: logic in a `services/*.qml`
  singleton, visuals in `ui/`/`components/`, `Hint.qml` for tooltips,
  `SideButton.qml`-style component for the button itself, fixed semantic
  color (not wallpaper-driven `Theme.accent`) for a fixed-meaning
  indicator (matches privacy=red, updates=green precedent).
- Every shell command the service calls must come from a declared
  package: `tailscale`, `wireguard-tools`, `openconnect` (all in Arch's
  official `extra` repo) go into `pkglist.txt`. `curl` is already there.
- No sudo, no secrets, no new systemd units/services.
- `ip -o link show type wireguard` must be relied on specifically because
  Tailscale's `tailscale0` is a userspace TUN interface, not a kernel
  `wireguard`-type link — so this check naturally excludes Tailscale mesh
  traffic and only catches a *separate* kernel WireGuard tunnel (i.e. the
  user's ProtonVPN `wg-quick` config).

## Approaches considered

Only one approach was really in play — everything else considered was a
variant of "how to detect fullTunnel," not a different architecture:

1. **Single shell probe, three checks, one singleton (chosen).** One
   `Process` on a timer runs `tailscale status --json` +
   `ip -o link show type wireguard` + `pgrep -x openconnect` in sequence,
   parses all three in one `StdioCollector.onStreamFinished`. Matches the
   `Gpu.qml`/`Updates.qml` pattern already in the codebase exactly — one
   process spawn per tick instead of three, simpler state management.
2. **Three separate singletons** (`Tailscale.qml`, `Wireguard.qml`,
   `Openconnect.qml`), each polling independently, composed in the UI.
   Rejected: triples the process-spawn overhead for no real benefit, since
   nothing else in the codebase needs these three signals independently —
   only the combined `fullTunnel` state and a few display fields matter.
3. **Rely on NetworkManager** (`nmcli` VPN connections) instead of
   probing each tool directly. Rejected: none of the three backends here
   are managed through NetworkManager in this setup (Tailscale has its own
   daemon, the WireGuard tunnel is raw `wg-quick`, OpenConnect runs
   standalone), so NetworkManager would see none of them.

## Decided design

- **Service**: `services/Vpn.qml`, pragma Singleton, `Process` + `Timer`
  (~10s interval, `triggeredOnStart: true`, guarded by `!proc.running` to
  avoid overlap — same shape as `Gpu.qml`).
  - Probe script (conceptually):
    ```sh
    command -v tailscale >/dev/null && tailscale status --json 2>/dev/null
    echo "---"
    ip -o link show type wireguard 2>/dev/null
    echo "---"
    pgrep -x openconnect >/dev/null && echo openconnect_up
    ```
  - Parsed fields: `tailscaleAvailable`, `tailscaleUp` (BackendState ==
    "Running"), `tailscaleIp` (`Self.TailscaleIPs[0]`), `exitNodeActive`
    (`ExitNodeStatus` key present and non-null), `wgAvailable`,
    `wgInterface` (first interface name from the `ip link` output, or
    `""`), `openconnectAvailable`, `openconnectUp`.
  - Derived: `readonly property bool fullTunnel: exitNodeActive ||
    wgInterface !== "" || openconnectUp`.
  - Derived: `readonly property bool anyBackendAvailable:
    tailscaleAvailable || wgAvailable || openconnectAvailable` — drives
    the button's `visible`.
  - Geolocation: a second `Process` (curl to a key-less JSON
    geolocation endpoint, e.g. `ip-api.com/json`, 3s timeout), fired only
    from a `Connections`/`onFullTunnelChanged`-style handler when
    `fullTunnel` transitions `false → true` or the active backend
    identity changes while already `true`. Result cached into
    `property string geoIp`, `property string geoLabel` ("City, Country")
    until the next transition; cleared (or left stale-but-unlabeled) when
    `fullTunnel` goes back to `false`.
- **UI**: `ui/Island.qml` — new `SideButton { id: vpnBtn }` at
  `x: pill.x - width - 8`; `gearBtn.x` becomes `vpnBtn.x - width - 8`
  (shifts gear one slot left; `timerPill`, already relative to
  `gearBtn.x`, cascades with no change needed). `vpnBtn` added to the
  layershell `mask` Region list. `visible: Vpn.anyBackendAvailable`.
  `icon: Icons.shieldLock` (existing glyph, no new codepoint). `tint`:
  a fixed semantic color distinct from `Theme.accent` (candidate:
  `win.catGreen` when `fullTunnel`, otherwise a muted/plain state like the
  inactive `SideButton` default) — exact color left to the builder,
  matching the privacy/updates fixed-color precedent.
  - Tooltip (`Hint`, `HoverHandler`/`containsMouse`-gated): multi-line,
    e.g. `Tailscale: up (100.x.x.x)` / active backend line
    (`wg0 — ProtonVPN` or `OpenConnect` or `Exit node`) / cached
    `geoIp — geoLabel` (or "resolving…" the first time, or omitted if the
    lookup hasn't completed yet).
  - No click action planned (read-only indicator) unless the plan stage
    finds a trivial, obviously-useful one.
- **Packages**: add `tailscale`, `iproute2`, `wireguard-tools`,
  `openconnect` to `pkglist.txt`. `iproute2` because the probe's
  WireGuard-detection command (`ip -o link show type wireguard`) actually
  comes from that package, not `wireguard-tools` (confirmed present on
  this machine today only transitively, not declared anywhere).
  `wireguard-tools` additionally because the user's existing ProtonVPN
  `wg-quick` setup depends on it and it was never declared — a
  pre-existing gap, closed here since it's directly relevant.
- **`components/SideButton.qml`**: add a `readonly property alias hovered:
  ma.containsMouse` (additive; `ma` is the component's existing private
  `MouseArea` id). Lets `vpnBtn.hovered` drive an external `Hint` in
  `Island.qml` the same way `privacyPill`/`updatesPill` already do,
  without bolting a second hover-catcher onto the button or changing
  `gearBtn`/`bellBtn` behavior.

## Left to the builder / plan stage

- Exact geolocation endpoint and its field names (`ip-api.com/json` vs.
  `ipapi.co/json` — pick one, document the exact JSON path parsed).
- Exact poll interval (proposed 10s, matching other lightweight pollers).
- Exact tint/color choice for the active state.
- Exact tooltip copy and line order.
- Whether `tailscale` needs `sudo` for `status --json` on this system (it
  normally does not — confirm during implementation; if it does, that's a
  blocker to flag back, not a silent `sudo` add).
