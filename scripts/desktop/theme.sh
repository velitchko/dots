#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# theme.sh — wallpaper + light/dark theme for the whole desktop.
#
#   theme.sh mode dark|light|toggle   switch mode (keeps the wallpaper)
#   theme.sh wallpaper <image>        set wallpaper and re-derive accents
#   theme.sh restore                  re-apply saved state (run at login)
#   theme.sh apply                    regenerate files from saved state
#   theme.sh precache                 prepare every wallpaper (screen-sized copy + colours)
#   theme.sh status                   print the saved state
#
# Base colours are fixed per mode (pitch black / eggshell); only the ACCENTS
# come from the wallpaper (matugen, if installed; cached per wallpaper).
# Outputs live in ~/.local/state/kessel/theme/ and are read by:
#   kitty (pushed over its socket, else SIGUSR1) → fish + starship follow its palette
#   fuzzel (include), Hyprland borders (hyprland.lua, hyprctl reload),
#   the Quickshell island (colors.json, watched live), GTK (gsettings).
set -euo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/kessel/theme"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/kessel/matugen"
mkdir -p "$STATE" "$CACHE"
STATE_FILE="$STATE/state.json"
DEFAULT_WALL="/usr/share/hypr/wall2.png"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1 || true)"; export HYPRLAND_INSTANCE_SIGNATURE
fi
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then   # awww finds its daemon by the Wayland socket name
    for s in "$XDG_RUNTIME_DIR"/wayland-*; do
        [[ -S $s ]] && { WAYLAND_DISPLAY="$(basename "$s")"; export WAYLAND_DISPLAY; break; }
    done
fi

# GTK3 theme. adw-gtk3 reads the libadwaita colour names that gtk.css defines below,
# so GTK3 apps (and Firefox's default "System theme", which follows GTK) pick up the
# wallpaper colours. Plain Adwaita ignores most of them.
gtk_theme() {
    local d
    for d in "$HOME/.local/share/themes" "$HOME/.themes" /usr/share/themes; do
        if [[ -d $d/adw-gtk3 ]]; then [[ $1 == dark ]] && echo adw-gtk3-dark || echo adw-gtk3; return; fi
    done
    [[ $1 == dark ]] && echo Adwaita-dark || echo Adwaita
}

state_get() { jq -r --arg k "$1" '.[$k] // empty' "$STATE_FILE" 2>/dev/null || true; }
state_set() {
    local tmp; tmp="$(mktemp "$STATE/.state.XXXXXX")"
    { [[ -s $STATE_FILE ]] && cat "$STATE_FILE" || echo '{}'; } | jq --arg k "$1" --arg v "$2" '.[$k] = $v' > "$tmp"
    mv "$tmp" "$STATE_FILE"
}
write() { local tmp; tmp="$(mktemp "$1.XXXXXX")"; cat > "$tmp"; mv "$tmp" "$1"; }   # atomic

# kset FILE < "group<TAB>key<TAB>value" lines: set many KConfig keys in one pass.
# Same result as one kwriteconfig6 call per key (groups and keys sorted, other
# content kept), but kwriteconfig6 costs ~12 ms a call and a theme switch set
# ~100 keys, which was most of the toggle's lag.
kset() {
    # -c (not `python3 - <<PY`): a heredoc on `python3 -` becomes the program's
    # stdin, so it's consumed as the SCRIPT and never reaches sys.stdin.read()
    # below — the piped group/key/value lines were silently discarded.
    python3 -c '
import os, sys, tempfile
path = sys.argv[1]
groups, head, order = {}, [], []
cur = None
if os.path.exists(path):
    for line in open(path, encoding="utf-8").read().splitlines():
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            cur = s[1:-1]
            if cur not in groups: groups[cur] = {}; order.append(cur)
        elif cur is None:
            if s: head.append(line)          # keys before any group: keep verbatim
        elif "=" in line:
            k, v = line.split("=", 1)
            groups[cur][k] = v
for line in sys.stdin.read().splitlines():
    if not line: continue
    g, k, v = line.split("\t", 2)
    if g not in groups: groups[g] = {}; order.append(g)
    groups[g][k] = v
out = head + ([""] if head else [])
for g in sorted(order):
    if not groups[g]: continue
    out.append(f"[{g}]")
    out += [f"{k}={groups[g][k]}" for k in sorted(groups[g])]
    out.append("")
d = os.path.dirname(path) or "."
os.makedirs(d, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=d, prefix=".kset.")
with os.fdopen(fd, "w", encoding="utf-8") as f: f.write("\n".join(out).rstrip("\n") + "\n")
os.replace(tmp, path)
' "$1"
}

# ── accents from the wallpaper ──────────────────────────────────────────────
# Prints: primary secondary tertiary   (for the given mode)
accents() {
    local wall=$1 mode=$2 key json
    if command -v matugen >/dev/null 2>&1 && [[ -r $wall ]]; then
        key="$(sha1sum "$wall" | cut -c1-16)"
        json="$CACHE/$key.json"
        if [[ ! -s $json ]]; then
            matugen image "$wall" --json hex --dry-run --prefer saturation > "$json.tmp" 2>/dev/null && mv "$json.tmp" "$json" || rm -f "$json.tmp"
        fi
        if [[ -s $json ]]; then
            # matugen's JSON has used both .colors.<mode>.<role> and .colors.<role>.<mode>
            jq -r --arg m "$mode" '
                def pick(r): (.colors[$m][r] // .colors[r][$m] // .colors[r][$m].color // empty)
                             | if type == "object" then (.color // .hex // empty) else . end;
                [pick("primary"), pick("secondary"), pick("tertiary")] | map(select(. != null)) | join(" ")' "$json" 2>/dev/null && return
        fi
    fi
    # fallback: the original Kessel accents
    if [[ $mode == dark ]]; then echo "#8aadf4 #a6da95 #c6a0f6"; else echo "#3d6ad6 #4f8a3a #7e57c2"; fi
}

# Material roles for the mode, as "name=#hex" lines (empty if matugen is unavailable).
roles() {
    local wall=$1 mode=$2 json
    command -v matugen >/dev/null 2>&1 && [[ -r $wall ]] || return 0
    json="$CACHE/$(sha1sum "$wall" | cut -c1-16).json"
    [[ -s $json ]] || return 0
    jq -r --arg m "$mode" '
        . as $doc
        | def pick(r): ($doc.colors[r][$m].color // $doc.colors[r][$m] // empty);
        ["primary","on_primary","primary_container","on_primary_container",
         "secondary","on_secondary","secondary_container","on_secondary_container",
         "tertiary","on_tertiary","tertiary_container","on_tertiary_container",
         "error","on_error","error_container","on_error_container",
         "outline","outline_variant","surface_variant","on_surface_variant"][]
        | . as $r | pick($r) | select(type == "string") | "\($r)=\(.)"' "$json" 2>/dev/null
}

# mix A B t → A blended toward B by t (0..1); used to "harmonize" fixed hues with the accent
mix() {
    local a=${1#\#} b=${2#\#} t=$3
    python3 -c "import sys;a,b,t=sys.argv[1:];t=float(t);print('#'+''.join('%02x'%round(int(a[i:i+2],16)*(1-t)+int(b[i:i+2],16)*t) for i in (0,2,4)))" "$a" "$b" "$t"
}

apply() {
    local mode wall
    mode="$(state_get mode)"; mode="${mode:-dark}"
    wall="$(state_get wallpaper)"; [[ -r $wall ]] || wall="$DEFAULT_WALL"
    read -r A A2 A3 <<<"$(accents "$wall" "$mode")"
    A=${A:-#8aadf4}; A2=${A2:-$A}; A3=${A3:-$A}
    declare -A M=()
    while IFS='=' read -r k v; do [[ -n $k ]] && M[$k]=$v; done < <(roles "$wall" "$mode")

    # Fixed bases. Dark = pitch black, light = eggshell.
    if [[ $mode == dark ]]; then
        BG="#000000"; SURFACE="#0b0b0b"; SURFACE2="#161616"; OVERLAY="#262626"
        TEXT="#e8e8e8"; SUBTEXT="#9a9a9a"; MUTED="#5a5a5a"
        RED="#e06c75"; GREEN="#a6da95"; YELLOW="#eed49f"; PURPLE="#c6a0f6"; CYAN="#8bd5ca"
        # ANSI: 0 black, 7 white, 8 bright-black, 15 bright-white (prompt pills rely on these)
        C0="#000000"; C7="#c8c8c8"; C8="#3a3a3a"; C15="#f2f2f2"
        GTK_SCHEME="prefer-dark"; GTK_THEME="$(gtk_theme dark)"
    else
        BG="#f0ead6"; SURFACE="#e8e1cb"; SURFACE2="#ddd5bc"; OVERLAY="#cfc6aa"
        TEXT="#1d1b16"; SUBTEXT="#5d584b"; MUTED="#9a937f"
        RED="#c0392b"; GREEN="#5f9e4a"; YELLOW="#a07800"; PURPLE="#7e57c2"; CYAN="#2a8a7e"
        C0="#1d1b16"; C7="#d6cdb2"; C8="#6b6556"; C15="#ffffff"
        GTK_SCHEME="prefer-light"; GTK_THEME="$(gtk_theme light)"
    fi

    # Material roles with sensible fallbacks
    local P=${M[primary]:-$A} ONP=${M[on_primary]:-$BG}
    local PC=${M[primary_container]:-$SURFACE2} ONPC=${M[on_primary_container]:-$TEXT}
    local S2=${M[secondary]:-$A2} SC=${M[secondary_container]:-$SURFACE2} ONSC=${M[on_secondary_container]:-$TEXT}
    local T=${M[tertiary]:-$A3} TC=${M[tertiary_container]:-$SURFACE2} ONTC=${M[on_tertiary_container]:-$TEXT}
    local ERR=${M[error]:-$RED} OUT=${M[outline]:-$MUTED} SV=${M[surface_variant]:-$OVERLAY} ONSV=${M[on_surface_variant]:-$SUBTEXT}
    # terminal hues: blue/magenta/cyan from the scheme, red = error,
    # green/yellow = fixed hues harmonized 25% toward the primary
    local H_RED=$ERR H_GRN H_YEL
    H_GRN="$(mix "$GREEN" "$P" 0.25)"; H_YEL="$(mix "$YELLOW" "$P" 0.25)"
    RED=$ERR; GREEN=$H_GRN; YELLOW=$H_YEL; PURPLE=$T; CYAN=$S2

    jq -n --arg mode "$mode" --arg wallpaper "$wall" --arg lockWallpaper "$(lock_wall "$wall")" \
          --arg bg "$BG" --arg surface "$SURFACE" --arg surface2 "$SURFACE2" --arg overlay "$OVERLAY" \
          --arg text "$TEXT" --arg subtext "$SUBTEXT" --arg muted "$MUTED" \
          --arg accent "$A" --arg accent2 "$A2" --arg accent3 "$A3" \
          --arg red "$RED" --arg green "$GREEN" --arg yellow "$YELLOW" --arg purple "$PURPLE" --arg cyan "$CYAN" \
          '$ARGS.named' | write "$STATE/colors.json"

    write "$STATE/kitty.conf" <<EOF
# generated by theme.sh ($mode) — do not edit
background $BG
foreground $TEXT
cursor $A
cursor_text_color $BG
selection_background $OVERLAY
selection_foreground $TEXT
url_color $A
active_border_color $A
inactive_border_color $OVERLAY
color0  $C0
color8  $C8
color1  $RED
color9  $( mix "$RED" "$C15" 0.25 )
color2  $GREEN
color10 $GREEN
color3  $YELLOW
color11 $YELLOW
color4  $P
color12 $( [[ $mode == dark ]] && echo "$ONPC" || echo "$PC" )
color5  $T
color13 $( [[ $mode == dark ]] && echo "$ONTC" || echo "$TC" )
color6  $S2
color14 $( [[ $mode == dark ]] && echo "$ONSC" || echo "$SC" )
color7  $C7
color15 $C15
EOF

    write "$STATE/fuzzel.ini" <<EOF
# generated by theme.sh ($mode) — do not edit
[colors]
background=${BG#\#}f2
text=${TEXT#\#}ff
prompt=${A#\#}ff
input=${TEXT#\#}ff
placeholder=${MUTED#\#}ff
match=${A#\#}ff
selection=${OVERLAY#\#}ff
selection-text=${TEXT#\#}ff
selection-match=${A#\#}ff
border=${A#\#}cc
EOF

    write "$STATE/hyprland.lua" <<EOF
-- generated by theme.sh ($mode) — do not edit
return {
    active   = { "rgba(${A#\#}ee)", "rgba(${A3#\#}ee)" },
    inactive = "rgba(${OVERLAY#\#}aa)",
}
EOF

    # KDE apps (Dolphin): a "Kessel" colour scheme from the same palette.
    if command -v kwriteconfig6 >/dev/null; then
        local cs="${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes"; mkdir -p "$cs"
        rgb() { local h=${1#\#}; printf '%d,%d,%d' 0x${h:0:2} 0x${h:2:2} 0x${h:4:2}; }
        local SEL_FG; [[ $mode == dark ]] && SEL_FG="$BG" || SEL_FG="#ffffff"
        {
            echo "[General]"; echo "ColorScheme=Kessel"; echo "Name=Kessel"; echo
            for g in Window View Button Tooltip Header Complementary; do
                local bgn="$BG" alt="$SURFACE"
                [[ $g == Button ]] && bgn="$SURFACE" && alt="$SURFACE2"
                [[ $g == View ]] && alt="$SURFACE"
                echo "[Colors:$g]"
                echo "BackgroundNormal=$(rgb "$bgn")"; echo "BackgroundAlternate=$(rgb "$alt")"
                echo "ForegroundNormal=$(rgb "$TEXT")"; echo "ForegroundInactive=$(rgb "$SUBTEXT")"
                echo "ForegroundActive=$(rgb "$A")"; echo "ForegroundLink=$(rgb "$A")"; echo "ForegroundVisited=$(rgb "$A3")"
                echo "ForegroundNegative=$(rgb "$RED")"; echo "ForegroundNeutral=$(rgb "$YELLOW")"; echo "ForegroundPositive=$(rgb "$GREEN")"
                echo "DecorationFocus=$(rgb "$A")"; echo "DecorationHover=$(rgb "$A")"; echo
            done
            echo "[Colors:Selection]"
            echo "BackgroundNormal=$(rgb "$A")"; echo "BackgroundAlternate=$(rgb "$A")"
            echo "ForegroundNormal=$(rgb "$SEL_FG")"; echo "ForegroundInactive=$(rgb "$SEL_FG")"; echo "ForegroundActive=$(rgb "$SEL_FG")"
            echo "ForegroundLink=$(rgb "$SEL_FG")"; echo "ForegroundVisited=$(rgb "$SEL_FG")"
            echo "ForegroundNegative=$(rgb "$RED")"; echo "ForegroundNeutral=$(rgb "$YELLOW")"; echo "ForegroundPositive=$(rgb "$GREEN")"
            echo "DecorationFocus=$(rgb "$A")"; echo "DecorationHover=$(rgb "$A")"; echo
            # standard effect groups (as in KDE's stock schemes); without them some
            # widgets derive unreadable text colours
            echo "[ColorEffects:Disabled]"; echo "Color=56,56,56"; echo "ColorAmount=0"; echo "ColorEffect=0"
            echo "ContrastAmount=0.65"; echo "ContrastEffect=1"; echo "IntensityAmount=0.1"; echo "IntensityEffect=2"; echo
            echo "[ColorEffects:Inactive]"; echo "ChangeSelectionColor=true"; echo "Color=112,111,110"; echo "ColorAmount=0.025"
            echo "ColorEffect=2"; echo "ContrastAmount=0.1"; echo "ContrastEffect=2"; echo "Enable=false"; echo "IntensityAmount=0"; echo "IntensityEffect=0"; echo
            echo "[WM]"; echo "activeBackground=$(rgb "$BG")"; echo "activeForeground=$(rgb "$TEXT")"
            echo "inactiveBackground=$(rgb "$BG")"; echo "inactiveForeground=$(rgb "$SUBTEXT")"
        } | write "$cs/Kessel.colors"
        local icons; [[ $mode == dark ]] && icons="Papirus-Dark" || icons="Papirus-Light"
        local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
        printf 'UiSettings\tColorScheme\tKessel\n' | kset "$cfg/dolphinrc"
        {
            printf 'General\tColorScheme\tKessel\n'
            printf 'General\tTerminalApplication\tkitty\n'
            printf 'General\tTerminalService\tkitty.desktop\n'
            printf 'Icons\tTheme\t%s\n' "$icons"
            printf 'KDE\twidgetStyle\tBreeze\n'
            # the scheme's colours, into the [Colors:*] groups KDE apps read from kdeglobals
            awk '/^\[Colors:.*\]$/ { g = substr($0, 2, length($0) - 2); next }
                 /^\[/ { g = ""; next }
                 g != "" && index($0, "=") { i = index($0, "="); printf "%s\t%s\t%s\n", g, substr($0, 1, i - 1), substr($0, i + 1) }' "$cs/Kessel.colors"
        } | kset "$cfg/kdeglobals"
    fi

    # Qt apps (Dolphin, …): qt6ct palette, applied at app start. KDE apps outside
    # Plasma otherwise apply their colour scheme too late for item views
    # (black text on black). Only our keys are set; other qt6ct settings survive.
    local qd="${XDG_CONFIG_HOME:-$HOME/.config}/qt6ct"; mkdir -p "$qd/colors"
    # role order: WindowText Button Light Midlight Dark Mid Text BrightText ButtonText Base
    #             Window Shadow Highlight HighlightedText Link LinkVisited AlternateBase
    #             NoRole ToolTipBase ToolTipText PlaceholderText Accent
    local HL_TXT; [[ $mode == dark ]] && HL_TXT="$BG" || HL_TXT="#ffffff"
    local act="$TEXT, $SURFACE, $OVERLAY, $SURFACE2, $BG, $SURFACE2, $TEXT, #ffffff, $TEXT, $BG, $BG, #000000, $A, $HL_TXT, $A, $A3, $SURFACE, $BG, $SURFACE, $TEXT, $MUTED, $A"
    local dis="$MUTED, $SURFACE, $OVERLAY, $SURFACE2, $BG, $SURFACE2, $MUTED, #ffffff, $MUTED, $BG, $BG, #000000, $OVERLAY, $MUTED, $MUTED, $MUTED, $SURFACE, $BG, $SURFACE, $MUTED, $MUTED, $OVERLAY"
    printf '[ColorScheme]\nactive_colors=%s\ninactive_colors=%s\ndisabled_colors=%s\n' "$act" "$act" "$dis" | write "$qd/colors/Kessel.conf"
    if command -v kwriteconfig6 >/dev/null; then
        local icons6; [[ $mode == dark ]] && icons6="Papirus-Dark" || icons6="Papirus-Light"
        local qstyle; ls /usr/lib/qt6/plugins/styles 2>/dev/null | grep -qi breeze && qstyle=Breeze || qstyle=Fusion
        {
            printf 'Appearance\tcustom_palette\ttrue\n'
            printf 'Appearance\tcolor_scheme_path\t%s\n' "$qd/colors/Kessel.conf"
            printf 'Appearance\ticon_theme\t%s\n' "$icons6"
            printf 'Appearance\tstyle\t%s\n' "$qstyle"
            printf 'Fonts\tgeneral\t%s\n' '"JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"'
            printf 'Fonts\tfixed\t%s\n' '"JetBrainsMono Nerd Font,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"'
        } | kset "$qd/qt6ct.conf"
    fi

    # Starship: repo config + a generated [palettes.kessel] (fish points STARSHIP_CONFIG here)
    local SREPO="$HOME/.config/starship.toml"
    if [[ -r $SREPO ]]; then
        { sed '/^\[palettes\.kessel\]/,$d' "$SREPO"
          cat <<EOS
[palettes.kessel]
primary = "$P"
on_primary = "$ONP"
primary_container = "$PC"
on_primary_container = "$ONPC"
secondary_container = "$SC"
on_secondary_container = "$ONSC"
tertiary_container = "$TC"
on_tertiary_container = "$ONTC"
surface_variant = "$SV"
on_surface_variant = "$ONSV"
error = "$ERR"
outline = "$OUT"
EOS
        } | write "$STATE/starship.toml"
    fi

    # fish: universal colour variables → running shells re-colour immediately
    if command -v fish >/dev/null; then
        fish -c "set -U fish_color_command ${P#\#}; set -U fish_color_param ${TEXT#\#}; set -U fish_color_quote ${T#\#}
                 set -U fish_color_error ${ERR#\#}; set -U fish_color_comment ${OUT#\#}; set -U fish_color_autosuggestion ${OUT#\#}
                 set -U fish_color_operator ${S2#\#}; set -U fish_color_escape ${T#\#}; set -U fish_color_redirection ${S2#\#} --bold
                 set -U fish_color_end ${S2#\#}; set -U fish_color_valid_path --underline
                 set -U fish_color_search_match --background=${SV#\#}; set -U fish_color_selection --background=${SV#\#}
                 set -U fish_pager_color_prefix ${P#\#} --bold --underline; set -U fish_pager_color_description ${ONSV#\#}
                 set -U fish_pager_color_progress ${ONP#\#} --background=${P#\#}" 2>/dev/null || true
    fi

    # Neovim: base16 palette for lua/kessel/theme.lua (re-applied live when this changes)
    jq -n --arg mode "$mode" \
        --arg b00 "$BG" --arg b01 "$SURFACE" --arg b02 "$SURFACE2" --arg b03 "$MUTED" \
        --arg b04 "$SUBTEXT" --arg b05 "$TEXT" --arg b06 "$TEXT" --arg b07 "$TEXT" \
        --arg b08 "$RED" --arg b09 "$T" --arg b0a "$YELLOW" --arg b0b "$GREEN" \
        --arg b0c "$CYAN" --arg b0d "$P" --arg b0e "$PURPLE" --arg b0f "$OUT" \
        '{mode: $mode, palette: {base00: $b00, base01: $b01, base02: $b02, base03: $b03,
          base04: $b04, base05: $b05, base06: $b06, base07: $b07, base08: $b08, base09: $b09,
          base0A: $b0a, base0B: $b0b, base0C: $b0c, base0D: $b0d, base0E: $b0e, base0F: $b0f}}' \
        | write "$STATE/nvim.json"

    # btop: theme file + select it (btop rewrites its own conf; only our keys are touched)
    local bd="${XDG_CONFIG_HOME:-$HOME/.config}/btop"; mkdir -p "$bd/themes"
    write "$bd/themes/kessel.theme" <<EOB
# generated by theme.sh ($mode) — do not edit
theme[main_bg]="$BG"
theme[main_fg]="$TEXT"
theme[title]="$TEXT"
theme[hi_fg]="$P"
theme[selected_bg]="$PC"
theme[selected_fg]="$ONPC"
theme[inactive_fg]="$OUT"
theme[graph_text]="$ONSV"
theme[meter_bg]="$SV"
theme[proc_misc]="$S2"
theme[cpu_box]="$P"
theme[mem_box]="$T"
theme[net_box]="$S2"
theme[proc_box]="$OUT"
theme[div_line]="$SV"
theme[temp_start]="$P"
theme[temp_mid]="$T"
theme[temp_end]="$ERR"
theme[cpu_start]="$P"
theme[cpu_mid]="$T"
theme[cpu_end]="$ERR"
theme[free_start]="$GREEN"
theme[free_mid]="$S2"
theme[free_end]="$P"
theme[cached_start]="$S2"
theme[cached_mid]="$P"
theme[cached_end]="$T"
theme[available_start]="$T"
theme[available_mid]="$P"
theme[available_end]="$S2"
theme[used_start]="$P"
theme[used_mid]="$T"
theme[used_end]="$ERR"
theme[download_start]="$S2"
theme[download_mid]="$P"
theme[download_end]="$T"
theme[upload_start]="$T"
theme[upload_mid]="$P"
theme[upload_end]="$ERR"
theme[process_start]="$P"
theme[process_mid]="$T"
theme[process_end]="$ERR"
EOB
    local bc="$bd/btop.conf"
    if [[ -f $bc ]]; then
        sed -i 's|^color_theme = .*|color_theme = "kessel"|; s|^theme_background = .*|theme_background = True|' "$bc"
        grep -q '^color_theme' "$bc" || echo 'color_theme = "kessel"' >> "$bc"
    else
        printf 'color_theme = "kessel"\ntheme_background = True\n' > "$bc"
    fi

    # yazi: generated theme (left alone if you replaced it with your own)
    local yd="${XDG_CONFIG_HOME:-$HOME/.config}/yazi"; mkdir -p "$yd"
    if [[ ! -e $yd/theme.toml ]] || head -1 "$yd/theme.toml" | grep -q 'generated by theme.sh'; then
        write "$yd/theme.toml" <<EOY
# generated by theme.sh ($mode) — delete this line to keep your own edits
[mgr]
cwd = { fg = "$P" }
hovered = { fg = "$ONPC", bg = "$PC" }
preview_hovered = { underline = true }
find_keyword = { fg = "$T", bold = true }
find_position = { fg = "$S2" }
marker_selected = { fg = "$P", bg = "$P" }
marker_copied = { fg = "$GREEN", bg = "$GREEN" }
marker_cut = { fg = "$ERR", bg = "$ERR" }
tab_active = { fg = "$ONP", bg = "$P" }
tab_inactive = { fg = "$ONSV", bg = "$SV" }
border_style = { fg = "$SV" }

[mode]
normal_main = { fg = "$ONP", bg = "$P", bold = true }
normal_alt = { fg = "$P", bg = "$SV" }
select_main = { fg = "$ONTC", bg = "$TC", bold = true }
select_alt = { fg = "$T", bg = "$SV" }
unset_main = { fg = "$ONSC", bg = "$SC", bold = true }
unset_alt = { fg = "$S2", bg = "$SV" }

[status]
perm_type = { fg = "$P" }
perm_read = { fg = "$YELLOW" }
perm_write = { fg = "$ERR" }
perm_exec = { fg = "$GREEN" }
perm_sep = { fg = "$OUT" }
progress_label = { fg = "$TEXT", bold = true }
progress_normal = { fg = "$P", bg = "$SV" }
progress_error = { fg = "$ERR", bg = "$SV" }

[filetype]
rules = [
  { mime = "image/*", fg = "$T" },
  { mime = "{audio,video}/*", fg = "$YELLOW" },
  { mime = "application/{zip,gzip,x-tar,x-bzip*,x-7z-compressed,x-xz,x-rar,zstd}", fg = "$ERR" },
  { mime = "application/{pdf,doc,rtf}", fg = "$S2" },
  { url = "*", is = "exec", fg = "$GREEN" },
  { url = "*/", fg = "$P" },
]
EOY
    fi

    # GTK 4 / libadwaita (OmniGlyph, …) and GTK 3: named colours from the palette
    local gtkcss
    gtkcss="$(cat <<EOG
/* generated by theme.sh ($mode) — delete this line to keep your own edits */
@define-color accent_color $P;
@define-color accent_bg_color $P;
@define-color accent_fg_color $ONP;
@define-color destructive_color $ERR;
@define-color destructive_bg_color $ERR;
@define-color window_bg_color $BG;
@define-color window_fg_color $TEXT;
@define-color view_bg_color $BG;
@define-color view_fg_color $TEXT;
@define-color headerbar_bg_color $SURFACE;
@define-color headerbar_fg_color $TEXT;
@define-color headerbar_backdrop_color $BG;
@define-color sidebar_bg_color $SURFACE;
@define-color sidebar_fg_color $TEXT;
@define-color card_bg_color $SURFACE;
@define-color card_fg_color $TEXT;
@define-color popover_bg_color $SURFACE;
@define-color popover_fg_color $TEXT;
@define-color dialog_bg_color $SURFACE;
@define-color dialog_fg_color $TEXT;
@define-color theme_bg_color $BG;
@define-color theme_fg_color $TEXT;
@define-color theme_base_color $BG;
@define-color theme_text_color $TEXT;
@define-color theme_selected_bg_color $P;
@define-color theme_selected_fg_color $ONP;
@define-color borders $SV;
EOG
)"
    local gd
    for gd in "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0" "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0"; do
        mkdir -p "$gd"
        if [[ ! -e $gd/gtk.css ]] || head -1 "$gd/gtk.css" | grep -q 'generated by theme.sh'; then
            printf '%s\n' "$gtkcss" | write "$gd/gtk.css"
        fi
    done

    # ── OnlyOffice ──
    # Pick a built-in theme matching light/dark, keeping the user's own choice when
    # it already matches (e.g. Dark Contrast). Custom theme files only recolour its
    # native tab strip in 10.0 (editors and start page fall back), so we don't ship
    # one. System title bar: the custom one draws a transparent margin inside the
    # tiled window. Read at start-up, so a running OnlyOffice changes on restart.
    local ooconf="${XDG_CONFIG_HOME:-$HOME/.config}/onlyoffice/DesktopEditors.conf"
    if [[ -f $ooconf ]]; then
        local cur want
        cur="$(sed -n 's/^UITheme=//p' "$ooconf")"
        if [[ $mode == dark ]]; then
            case $cur in theme-night|theme-dark|theme-contrast-dark) want=$cur ;; *) want=theme-night ;; esac
        else
            case $cur in theme-white|theme-light|theme-classic-light|theme-gray) want=$cur ;; *) want=theme-white ;; esac
        fi
        if grep -q '^UITheme=' "$ooconf"; then sed -i "s/^UITheme=.*/UITheme=$want/" "$ooconf"
        else sed -i "/^\[General\]/a UITheme=$want" "$ooconf"; fi
        if grep -q '^titlebar=' "$ooconf"; then sed -i 's/^titlebar=.*/titlebar=system/' "$ooconf"
        else sed -i '/^\[General\]/a titlebar=system' "$ooconf"; fi
    fi
    # The setting above only exists once OnlyOffice has run and a theme switch has
    # followed, and OnlyOffice rewrites the file on exit. The --system-title-bar
    # flag always wins: a user copy of its launcher entry (shadows the system one
    # for the island launcher, fuzzel, Dolphin's "Open with") adds it to every Exec.
    # Rebuilt from the system file each time, so package updates carry over.
    local oodesk=/usr/share/applications/onlyoffice-desktopeditors.desktop
    local oouser="${XDG_DATA_HOME:-$HOME/.local/share}/applications/onlyoffice-desktopeditors.desktop"
    if [[ -r $oodesk ]] && { [[ ! -e $oouser ]] || grep -q '^# generated by theme.sh' "$oouser"; }; then
        mkdir -p "${oouser%/*}"
        { echo "# generated by theme.sh (adds --system-title-bar) — do not edit"
          sed -E 's#^(Exec=[^ ]*onlyoffice-desktopeditors)( |$)#\1 --system-title-bar\2#' "$oodesk"
        } | write "$oouser"
    fi

    # ── reload consumers (each optional) ──
    # kitty: push the colours to every running instance and window (smooth, no
    # restart). Decided PER PROCESS: before, one successful push skipped the
    # fallback for all the others, so a second kitty without a working socket
    # kept the old colours. Each kitty listens on kitty-<pid>.sock (kitty.conf);
    # one that doesn't (or doesn't answer within 3 s) gets SIGUSR1 (config reload).
    # Pushed in parallel; outcomes go to kitty.log for diagnosis.
    local pid sock klog="$STATE/kitty.log"
    : > "$klog"
    for pid in $(pgrep -x kitty 2>/dev/null); do
        sock="$XDG_RUNTIME_DIR/kitty-$pid.sock"
        (
            if [[ -S $sock ]] && timeout 3 env -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON \
                   kitten @ --to "unix:$sock" set-colors --all --configured "$STATE/kitty.conf" >/dev/null 2>>"$klog"; then
                echo "kitty $pid: pushed" >> "$klog"
            else
                echo "kitty $pid: $([[ -S $sock ]] && echo 'push failed' || echo 'no socket') -> SIGUSR1" >> "$klog"
                kill -USR1 "$pid" 2>/dev/null || true
            fi
        ) &
    done
    wait
    if command -v gsettings >/dev/null; then
        gsettings set org.gnome.desktop.interface color-scheme "$GTK_SCHEME" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" 2>/dev/null || true
    fi
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null; then
        hyprctl reload >/dev/null 2>&1 || true                   # borders
    fi
    # GTK apps that stay resident keep the colours they started with; OmniGlyph is
    # a picker that lingers in the background, so close it — the next SUPER+. is fresh.
    if pgrep -x omniglyph >/dev/null 2>&1; then
        for p in $(pgrep -x omniglyph); do kill "$p" 2>/dev/null || true; done
        for _ in $(seq 20); do pgrep -x omniglyph >/dev/null || break; sleep 0.1; done   # wait up to 2 s
        for p in $(pgrep -x omniglyph 2>/dev/null); do kill -9 "$p" 2>/dev/null || true; done
    fi

    # Quickshell island: reload its colours (no-op if it is not running).
    qs -c kessel ipc call island reloadTheme >/dev/null 2>&1 || true
    echo "theme: $mode · accent $A · $(basename "$wall")"
}

# ── wallpaper speed ──
# Wallpapers are often 8K PNGs: awww spends a second or more decoding and scaling
# one before its transition can start, and matugen ~1-2 s the first time. So:
#   sized_wall   a copy at the widest display's width (cached), which awww loads fast
#   precompute   that copy + the matugen colours, so a switch only reads caches
#   precache     both for every wallpaper, run in the background by the island
TRANSITION_S=1.2
WALLS="${XDG_CACHE_HOME:-$HOME/.cache}/kessel/walls"
screen_width() {
    local w=""
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && w="$(hyprctl monitors -j 2>/dev/null | jq -r 'map(.width) | max // empty' 2>/dev/null)"
    [[ $w =~ ^[0-9]+$ ]] && echo "$w" || echo 3840
}
# sized_wall <image> → path of a copy no wider than the widest display (or the
# image itself when it's already small, or when ffmpeg isn't available).
sized_wall() {
    local wall=$1 w iw out
    command -v ffmpeg >/dev/null || { echo "$wall"; return; }
    w="${SCREEN_W:-$(screen_width)}"
    iw="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$wall" 2>/dev/null | head -1)"
    [[ $iw =~ ^[0-9]+$ ]] && (( iw > w )) || { echo "$wall"; return; }
    out="$WALLS/$(sha1sum "$wall" | cut -c1-16)-$w.png"
    if [[ ! -s $out ]]; then
        mkdir -p "$WALLS"
        ffmpeg -nostdin -loglevel error -y -i "$wall" -vf "scale=$w:-2:flags=lanczos" -compression_level 1 "$out.tmp.png" \
            && mv "$out.tmp.png" "$out" || { rm -f "$out.tmp.png"; echo "$wall"; return; }
    fi
    echo "$out"
}
# lock_wall <image> → a small JPEG for the lock screen, which only shows it
# blurred: decodes instantly instead of popping in after the full image.
lock_wall() {
    local wall=$1 out
    command -v ffmpeg >/dev/null || { echo "$wall"; return; }
    out="$WALLS/$(sha1sum "$wall" | cut -c1-16)-lock.jpg"
    if [[ ! -s $out ]]; then
        mkdir -p "$WALLS"
        ffmpeg -nostdin -loglevel error -y -i "$wall" -vf "scale=1280:-2:flags=lanczos" -q:v 3 "$out.tmp.jpg" \
            && mv "$out.tmp.jpg" "$out" || { rm -f "$out.tmp.jpg"; echo "$wall"; return; }
    fi
    echo "$out"
}
precompute() { accents "$1" dark >/dev/null; sized_wall "$1" >/dev/null; lock_wall "$1" >/dev/null; }

set_wallpaper() {
    local wall=$1
    [[ -r $wall ]] || { echo "theme: cannot read $wall" >&2; exit 1; }
    wall="$(realpath "$wall")"
    state_set wallpaper "$wall"
    show_wallpaper "$wall" || echo "theme: no wallpaper daemon answered (awww-daemon / hyprpaper)" >&2
}

# Put $1 on every display. Retries for up to ~5 s so a call right after login
# doesn't lose the race against the daemon starting (that used to fail silently).
show_wallpaper() {
    local wall=$1 i shown
    # awww and hyprpaper are Wayland clients: no display, nothing to do (a stale
    # Hyprland runtime dir used to make this retry for ~18 s over SSH).
    [[ -n ${WAYLAND_DISPLAY:-} ]] || return 0
    shown="$(sized_wall "$wall")"
    # awww installed but its daemon isn't running (not started at login, or it
    # crashed): start it ourselves instead of failing silently.
    if command -v awww-daemon >/dev/null && ! pgrep -x awww-daemon >/dev/null; then
        setsid -f awww-daemon >"$STATE/awww-daemon.log" 2>&1 </dev/null || true
    fi
    for (( i = 0; i < 25; i++ )); do
        if command -v awww >/dev/null && awww query >/dev/null 2>&1; then
            awww img "$shown" --transition-type grow --transition-pos 0.5,0.97 \
                --transition-duration "$TRANSITION_S" --transition-fps 60 --transition-bezier .2,.8,.2,1 >/dev/null 2>&1 && return 0
        elif ! command -v awww-daemon >/dev/null && pgrep -x hyprpaper >/dev/null &&
             hyprctl hyprpaper wallpaper ",$shown" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

# Smooth switch: the island shows a frozen snapshot of each screen (freeze), we
# change everything underneath, then it fades the snapshot out (thaw). Without the
# island this is a no-op and the switch is simply instant.
freeze() {
    [[ -n ${KESSEL_NO_FADE:-} ]] && return 0
    qs -c kessel ipc call island freeze >/dev/null 2>&1 && FROZEN=1 && sleep 0.15 || true
}
thaw() {
    [[ -n ${FROZEN:-} ]] || return 0
    sleep 0.2                      # let kitty / GTK repaint before revealing them
    qs -c kessel ipc call island thaw >/dev/null 2>&1 || true
}

# One switch at a time: a keybind and an island click (or two quick clicks)
# used to interleave, each reading the old mode and racing freeze/thaw and
# state.json. A queued "toggle" reads the mode only once it holds the lock.
# (precache has its own lock and only fills caches, so it never blocks a switch.)
case ${1:-status} in
    status|precache|precompute-one) ;;
    *) if command -v flock >/dev/null; then exec 9>"$STATE/.lock"; flock 9; fi ;;
esac

case "${1:-status}" in
    mode)
        case "${2:-toggle}" in
            dark|light) m=$2 ;;
            toggle) [[ "$(state_get mode)" == light ]] && m=dark || m=light ;;
            *) echo "usage: $0 mode dark|light|toggle" >&2; exit 2 ;;
        esac
        state_set mode "$m"; freeze; apply; thaw ;;
    wallpaper)
        [[ -n ${2:-} ]] || { echo "usage: $0 wallpaper <image>" >&2; exit 2; }
        # The new picture grows in from the island at once (no frozen screen);
        # its colours are worked out meanwhile, then only the recolour crossfades.
        [[ -r $2 ]] && { accents "$(realpath "$2")" dark >/dev/null & }   # matugen, in parallel
        set_wallpaper "$2"
        t0=$EPOCHREALTIME
        wait
        rest="$(awk -v a="$t0" -v b="$EPOCHREALTIME" -v d="$TRANSITION_S" 'BEGIN { r = d - (b - a); print (r > 0 ? r : 0) }')"
        sleep "$rest"                    # let the transition finish before the snapshot
        freeze; apply; thaw ;;
    precache)
        # Every wallpaper's screen-sized copy + colours, at idle priority; one run at a time.
        exec 8>"$STATE/.precache.lock"; flock -n 8 || exit 0
        SCREEN_W="$(screen_width)"
        dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Wallpapers"
        find -L "$dir" -maxdepth 2 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) ! -iname '*lock*' 2>/dev/null |
            while IFS= read -r f; do nice -n 19 ionice -c 3 "$0" precompute-one "$f" || true; done ;;
    precompute-one)
        [[ -r ${2:-} ]] && precompute "$(realpath "$2")" ;;
    restore)
        w="$(state_get wallpaper)"; [[ -r $w ]] || w="$DEFAULT_WALL"
        set_wallpaper "$w"; apply ;;
    apply)  apply ;;
    status) cat "$STATE_FILE" 2>/dev/null || echo '{}' ;;
    *) echo "usage: $0 mode|wallpaper|restore|apply|precache|status" >&2; exit 2 ;;
esac
