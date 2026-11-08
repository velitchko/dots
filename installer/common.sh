# SPDX-License-Identifier: GPL-3.0-or-later
# Shared helpers for install.sh. Sourced, not executed.

REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dot-files"
BACKUP_ROOT="$STATE_DIR/backups"
DRY_RUN=0

if [[ -t 1 ]]; then
    C_B=$'\e[1m' C_DIM=$'\e[2m' C_G=$'\e[32m' C_Y=$'\e[33m' C_R=$'\e[31m' C_C=$'\e[36m' C_0=$'\e[0m'
else
    C_B='' C_DIM='' C_G='' C_Y='' C_R='' C_C='' C_0=''
fi

step()  { printf '\n%s==> %s%s\n' "$C_B$C_C" "$*" "$C_0"; }
ok()    { printf '  %s✓%s %s\n' "$C_G" "$C_0" "$*"; }
info()  { printf '  %s·%s %s\n' "$C_DIM" "$C_0" "$*"; }
warn()  { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
fail()  { printf '  %s✗%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()   { fail "$*"; exit 1; }

# run CMD... — execute, or only print it in --dry-run mode.
run() {
    if (( DRY_RUN )); then
        printf '  %s[dry-run]%s %s\n' "$C_Y" "$C_0" "$*"
    else
        "$@"
    fi
}

# read_manifest FILE — print non-empty, non-comment lines (first field).
read_manifest() {
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | awk 'NF { print $1 }'
}

# read_links FILE — print "src<TAB>dest" pairs.
read_links() {
    sed -e 's/#.*//' "$1" | awk 'NF >= 2 { print $1 "\t" $2 }'
}
