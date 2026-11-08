#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# scripts-index.sh — every script in ~/Scripts as JSON, read from each script's
# header comment (the Scripts tab of the SUPER+/ panel). Nothing to maintain:
# a script's first comment line is its purpose, indented "name args   what"
# lines are its usage.
#
#   scripts-index.sh          JSON array: { name, group, path, purpose, usage: [{cmd, what}] }
set -euo pipefail
dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"   # repo scripts/
exec python3 -I - "$dir" <<'PY'
import json, os, re, sys
root = sys.argv[1]
out = []
for group, sub, shown in (("Your tools", "", "~/Scripts/"), ("Desktop", "desktop", "~/Scripts/desktop/")):
    d = os.path.join(root, sub)
    for fn in sorted(os.listdir(d)):
        p = os.path.join(d, fn)
        if not fn.endswith(".sh") or not os.path.isfile(p):
            continue
        name = fn
        header = []
        with open(p, encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f):
                if i == 0 and line.startswith("#!"):
                    continue
                if not line.startswith("#"):
                    break
                if "SPDX-License-Identifier" in line:
                    continue
                header.append(line.rstrip("\n")[1:])          # drop the '#'
        purpose, synopsis, usage = "", "", []
        stem = re.escape(name)
        use_re = re.compile(r"^\s{2,}((?:~/Scripts/(?:desktop/)?)?" + stem + r"\b.*?)(?:\s{2,}(\S.*))?$")
        in_purpose = True
        prev_usage = False         # wrapped usage descriptions only directly follow one
        for i, h in enumerate(header):
            if i == 0:
                first = h.strip()
                m = re.match(r"^(?:~/Scripts/(?:desktop/)?)?(\S+(?:\s+[^—]*?)?)\s+—\s+(.*)$", first)
                if m and m.group(1).split()[0] == name:
                    synopsis, purpose = m.group(1).strip(), m.group(2).strip()
                else:
                    purpose = first
                continue
            m = use_re.match(h)
            if m:
                in_purpose = False
                cmd = re.sub(r"^~/Scripts/(?:desktop/)?", "", m.group(1).strip())
                usage.append({"cmd": cmd, "what": (m.group(2) or "").strip()})
                prev_usage = True
                continue
            if prev_usage and re.match(r"^\s{6,}\S", h):      # wrapped description
                usage[-1]["what"] = (usage[-1]["what"] + " " + h.strip()).strip()
                continue
            prev_usage = False
            if in_purpose and h.strip() and not h.startswith("   "):
                if len(purpose) < 220:
                    purpose = (purpose + " " + h.strip()).strip()
                continue
            if not h.strip():
                in_purpose = False
        if not usage and synopsis and synopsis != name:
            usage.append({"cmd": synopsis, "what": ""})
        purpose = purpose[:1].upper() + purpose[1:]
        out.append({"name": name, "group": group, "path": shown + name,
                    "purpose": purpose, "usage": usage})
json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
print()
PY
