#!/bin/sh
# Builds dist/BuffRadar-<version>-Forever.zip and dist/SHA256SUMS.txt (Linux/CI twin of build.ps1).
# Usage: sh tools/package.sh
set -e
cd "$(dirname "$0")/.."
VER="$(sed -n 's/^## Version:[[:space:]]*//p' editions/forever/BuffRadar.toc | head -1 | tr -d '\r')"
[ -n "$VER" ] || { echo "No '## Version:' in editions/forever/BuffRadar.toc" >&2; exit 1; }
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/BuffRadar" dist
for f in BuffRadar/*; do
  case "$(basename "$f")" in BuffRadar.toc|README.md|CHANGELOG.md|DESCRIPTION.md|FEATURES.md) ;; *) cp -r "$f" "$STAGE/BuffRadar/" ;; esac
done
for f in BuffRadar.toc README.md CHANGELOG.md DESCRIPTION.md FEATURES.md; do cp "editions/forever/$f" "$STAGE/BuffRadar/"; done
ZIP="dist/BuffRadar-$VER-Forever.zip"
rm -f "$ZIP"
( cd "$STAGE" && python3 -I - "$OLDPWD/$ZIP" <<'PY'
import os, sys, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk("BuffRadar"):
        dirs.sort()
        z.write(root)
        for f in sorted(files):
            z.write(os.path.join(root, f))
PY
)
( cd dist && sha256sum "BuffRadar-$VER-Forever.zip" > SHA256SUMS.txt && cat SHA256SUMS.txt )
