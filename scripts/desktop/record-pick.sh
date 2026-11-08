#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# record-pick.sh — pick a region with slurp, then hand it to the island to record.
#   record-pick.sh    run detached (not a Quickshell Process child -- slurp never
#                      gets a layer-shell surface that way here); Esc cancels quietly
set -euo pipefail
geom="$(slurp -d)" || exit 0
qs -c kessel ipc call island recordRegionGeometry "$geom" >/dev/null 2>&1
