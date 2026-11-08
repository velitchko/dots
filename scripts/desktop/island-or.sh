#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# island-or.sh <ipc-function> [arg] -- <fallback command...> — ask the island, else run a fallback.
# If the Quickshell island is not running (or hidden), the fallback runs instead,
# so every bind stays usable without Quickshell.
#   island-or.sh open launcher -- fuzzel
fn=$1; shift
args=()
while (( $# )) && [[ $1 != -- ]]; do args+=("$1"); shift; done
[[ ${1:-} == -- ]] && shift
out="$(qs -c kessel ipc call island "$fn" "${args[@]}" 2>/dev/null)"
case $out in
    ok|shown|hidden\ *|"dnd on"|"dnd off") exit 0 ;;
esac
(( $# )) && exec "$@"
exit 0
