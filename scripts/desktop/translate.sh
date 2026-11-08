#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# translate.sh — fully offline translation for the launcher (">de hello").
# Engine: Bergamot (same models as translateLocally / Firefox), via the `bergamot`
# Python package in a private Python 3.10 managed by uv — nothing to compile.
#
#   translate.sh setup [pairs…]   runtime + models (default: en-de de-en en-bg bg-en)
#   translate.sh available        every downloadable model (browsermt + opus)
#   translate.sh add <pair|code>…  download more, e.g. add en-fr or add deu-ukr-tiny
#   translate.sh installed        downloaded models
#   translate.sh remove <code>    delete a downloaded model
#   translate.sh repair           fix models the bergamot downloader left half-installed
#   translate.sh run <from> <to>  translate stdin → stdout (pivots through English)
#   translate.sh status           "ready" / "no-avx2" / "no-runtime" / "no-models" (for the island)
#
# Pairs are ISO-639-1 codes (en, de, bg, fr…). browsermt models are preferred
# (higher quality), "base" over "tiny"; OPUS-MT (3-letter codes) fills the gaps.
set -euo pipefail

ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/kessel/translate"
VENV="$ROOT/venv"
BIN="$VENV/bin/bergamot"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/kessel/translate"
BMT_URL="https://translatelocally.com/models.json"
OPUS_URL="https://object.pouta.csc.fi/OPUS-MT-models/app/models.json"
DEFAULT_PAIRS=(en-de de-en en-bg bg-en)
STAMP="$ROOT/.works"          # written once the engine has actually run on this CPU
mkdir -p "$CACHE"

die() { echo "translate: $*" >&2; exit 1; }

# ISO-639-1 → ISO-639-3 (OPUS codes) for common languages
iso3() {
    case $1 in
        en) echo eng;; de) echo deu;; bg) echo bul;; fr) echo fra;; es) echo spa;; it) echo ita;;
        pt) echo por;; nl) echo nld;; pl) echo pol;; cs) echo ces;; sk) echo slk;; sl) echo slv;;
        hr) echo hrv;; sr) echo srp;; ru) echo rus;; uk) echo ukr;; ro) echo ron;; hu) echo hun;;
        el) echo ell;; tr) echo tur;; sv) echo swe;; da) echo dan;; nb) echo nob;; fi) echo fin;;
        et) echo est;; lv) echo lav;; lt) echo lit;; ja) echo jpn;; zh) echo zho;; ko) echo kor;;
        ar) echo ara;; he) echo heb;; fa) echo fas;; hi) echo hin;; is) echo isl;; ca) echo cat;;
        *) echo "$1";;
    esac
}

inventory() { # inventory browsermt|opus → cached models.json (refreshed daily)
    local f="$CACHE/$1.json" url
    [[ $1 == browsermt ]] && url=$BMT_URL || url=$OPUS_URL
    if [[ ! -s $f || -n $(find "$f" -mtime +1 2>/dev/null) ]]; then
        curl -fsS --max-time 20 "$url" -o "$f.tmp" && mv "$f.tmp" "$f" || rm -f "$f.tmp"
    fi
    [[ -s $f ]] || die "cannot fetch the $1 model list (offline?)"
    cat "$f"
}

# resolve <from> <to> → "repo code" of the best direct model, or nothing
resolve() {
    local f=$1 t=$2 code
    code="$(inventory browsermt | jq -r --arg c "$f-$t" '[.models[] | select(.code | startswith($c + "-"))] | sort_by(if .type == "base" then 0 else 1 end) | .[0].code // empty')"
    [[ -n $code ]] && { echo "browsermt $code"; return; }
    code="$(inventory opus | jq -r --arg c "$(iso3 "$f")-$(iso3 "$t")" '[.models[] | select(.code | startswith($c + "-"))] | .[0].code // empty')"
    [[ -n $code ]] && echo "opus $code"
    true
}

installed_codes() { # "repo code" lines for downloaded models
    local d
    for repo in browsermt opus; do
        d="${XDG_DATA_HOME:-$HOME/.local/share}/bergamot/models/$repo"
        [[ -d $d ]] && find "$d" -mindepth 1 -maxdepth 1 -type l -printf "$repo %f\n"
    done
    true
}
is_installed() { installed_codes | grep -qx "$1 $2"; }

# repair <repo> <code>: make a downloaded model usable.
# The bergamot package expects each archive to unpack into a folder named after
# its URL (ende.student.base.v2.37b172bc9b594f9b), but current archives unpack
# into a shorter one (ende.student.base). Its download then links the code to a
# folder that doesn't exist and dies before writing config.bergamot.yml, and
# translating fails with "You need to provide at least one model file or a
# config file". We link the expected name to the real folder and write the
# config with the same settings the package's patch step uses.
repair() {
    [[ -x $VENV/bin/python ]] || return 0
    inventory "$1" >/dev/null   # refreshes $CACHE/<repo>.json (the script itself comes on stdin)
    "$VENV/bin/python" -I - "$1" "$2" "${XDG_DATA_HOME:-$HOME/.local/share}/bergamot" "$CACHE/$1.json" <<'PY'
import json, os, sys, tarfile
import yaml
repo, code, base, invfile = sys.argv[1:5]
inv = json.load(open(invfile))
m = next((m for m in inv["models"] if m["code"] == code), None)
if m is None:
    sys.exit(0)
models = os.path.join(base, "models", repo)
want = os.path.join(models, os.path.basename(m["url"]).replace(".tar.gz", ""))
if not os.path.isdir(want):
    arch = os.path.join(base, "archives", repo, m["shortName"] + ".tar.gz")
    if not os.path.exists(arch):
        sys.exit(f"translate: {code}: archive {arch} missing, download again")
    with tarfile.open(arch) as t:
        top = next((n.split("/")[0] for n in t.getnames() if n.split("/")[0] not in ("", ".")), None)
        if top is None or not os.path.isdir(os.path.join(models, top)):
            t.extractall(models)
    if top and os.path.isdir(os.path.join(models, top)):
        if os.path.islink(want): os.remove(want)
        os.symlink(top, want)
    if not os.path.isdir(want):
        sys.exit(f"translate: {code}: can't find the unpacked model folder")
link = os.path.join(models, code)
if not os.path.exists(link):
    if os.path.islink(link): os.remove(link)
    os.symlink(want, link)
cfg = os.path.join(want, "config.bergamot.yml")
if not os.path.exists(cfg) or os.path.getsize(cfg) == 0:
    src = next((os.path.join(want, f) for f in ("config.intgemm8bitalpha.yml", "config.yml") if os.path.exists(os.path.join(want, f))), None)
    if src is None:
        sys.exit(f"translate: {code}: no marian config in {want}")
    data = yaml.load(open(src), Loader=yaml.FullLoader)
    data.update({"ssplit-prefix-file": "", "ssplit-mode": "paragraph", "max-length-break": 128,
                 "mini-batch-words": 1024, "workspace": 128, "alignment": "soft"})
    with open(cfg, "w") as f:
        print(yaml.dump(data, sort_keys=False), file=f)
    print(f"✓ {code}: config written")
PY
}

download() { # download <repo> <code>
    [[ -x $BIN ]] || die "runtime missing — run: translate.sh setup"
    if is_installed "$1" "$2"; then repair "$1" "$2"; echo "✓ $2 ($1) already installed"; return; fi
    echo "↓ $2 ($1)"
    # may exit non-zero on the folder-name mismatch above; repair finishes the job
    "$BIN" download -r "$1" -m "$2" || true
    repair "$1" "$2"
}

add() { # add <pair|code>…
    local a r
    for a in "$@"; do
        if [[ $a =~ ^[a-z]{2}-[a-z]{2}$ ]]; then
            r="$(resolve "${a%-*}" "${a#*-}")"
            [[ -n $r ]] || { echo "✗ no direct model for $a (pivoting through English needs ${a%-*}-en and en-${a#*-})"; continue; }
            download $r
        else
            if inventory browsermt | jq -e --arg c "$a" '.models[] | select(.code == $c)' >/dev/null; then download browsermt "$a"
            elif inventory opus | jq -e --arg c "$a" '.models[] | select(.code == $c)' >/dev/null; then download opus "$a"
            else echo "✗ unknown model code $a (see: translate.sh available)"; fi
        fi
    done
}

# run <from> <to>: direct model if installed, else pivot via English (same repository)
run_translate() {
    local f=$1 t=$2 r1 r2 text
    [[ -x $BIN ]] || die "runtime missing — run: ~/.config/hypr/scripts/translate.sh setup"
    text="$(cat)"
    [[ -n $text ]] || return 0
    # fix models downloaded before repair() existed (cheap once fixed)
    local r; while read -r r; do [[ -n $r ]] && repair $r >&2; done < <(installed_codes)
    r1="$(resolve "$f" "$t")"
    if [[ -n $r1 ]] && is_installed $r1; then
        printf '%s' "$text" | "$BIN" translate -r "${r1% *}" -m "${r1#* }"; echo; return
    fi
    if [[ $f != en && $t != en ]]; then
        r1="$(resolve "$f" en)"; r2="$(resolve en "$t")"
        if [[ -n $r1 && -n $r2 ]] && is_installed $r1 && is_installed $r2; then
            if [[ ${r1% *} == "${r2% *}" ]]; then
                printf '%s' "$text" | "$BIN" translate -r "${r1% *}" -m "${r1#* }" "${r2#* }"; echo
            else  # different repositories: two passes
                printf '%s' "$text" | "$BIN" translate -r "${r1% *}" -m "${r1#* }" | "$BIN" translate -r "${r2% *}" -m "${r2#* }"; echo
            fi
            return
        fi
    fi
    die "no model installed for $f→$t — try: translate.sh add $f-$t"
}

case "${1:-}" in
    setup)
        shift
        command -v uv >/dev/null || die "uv is not installed (sudo pacman -S uv)"
        # The prebuilt Bergamot engine needs AVX2. Generic virtual CPU models
        # (e.g. "kvm64", "QEMU Virtual CPU") don't expose it: use CPU type "host".
        if ! grep -qw avx2 /proc/cpuinfo; then
            die "this CPU has no AVX2, which the translation engine needs.
  On a VM: set the virtual CPU type to 'host' in your hypervisor, then cold-boot it.
  Real laptops/desktops from the last decade have AVX2."
        fi
        mkdir -p "$ROOT"
        if [[ ! -x $BIN ]]; then
            echo "• private Python 3.10 + bergamot → $VENV"
            uv venv --quiet --python 3.10 "$VENV"
            VIRTUAL_ENV="$VENV" uv pip install --quiet bergamot
        fi
        "$BIN" --help >/dev/null 2>&1 || { rm -f "$STAMP"; die "bergamot did not start (see above)"; }
        touch "$STAMP"
        echo "✓ runtime ready"
        (( $# )) && add "$@" || add "${DEFAULT_PAIRS[@]}"
        ;;
    available)
        echo "browsermt (preferred):"
        inventory browsermt | jq -r '.models[] | "  \(.code)\t\(.src) → \(.trg)\t\(.type)"' | sort
        echo "opus:"
        inventory opus | jq -r '.models[] | "  \(.code)\t\(.src) → \(.trg)"' | sort
        ;;
    add)       shift; (( $# )) || die "usage: translate.sh add <pair|code>…"; add "$@" ;;
    installed) installed_codes ;;
    remove)
        shift; (( $# )) || die "usage: translate.sh remove <code>"
        for repo in browsermt opus; do
            l="${XDG_DATA_HOME:-$HOME/.local/share}/bergamot/models/$repo/$1"
            if [[ -L $l ]]; then
                rm -rf -- "$(readlink -f "$l")"; rm -f -- "$l"
                find "${l%/*}" -maxdepth 1 -xtype l -delete   # the URL-named link repair() made
                echo "removed $1 ($repo)"
            fi
        done ;;
    repair)    while read -r r; do [[ -n $r ]] && repair $r; done < <(installed_codes); echo "✓ models checked" ;;
    run)       shift; (( $# == 2 )) || die "usage: translate.sh run <from> <to>  (text on stdin)"; run_translate "$1" "$2" ;;
    status)
        if ! grep -qw avx2 /proc/cpuinfo; then echo no-avx2
        elif [[ ! -x $BIN || ! -e $STAMP ]]; then echo no-runtime
        elif [[ -z "$(installed_codes)" ]]; then echo no-models
        else echo ready; fi ;;
    *) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
