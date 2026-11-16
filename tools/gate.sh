#!/bin/sh
# Static checks and the six-setup smoke run used by GitHub CI.
# Usage: sh tools/gate.sh      (needs python3 or python, plus the lupa package)
set -e
cd "$(dirname "$0")/.."
# Windows and MSYS ship "python" with no python3 alias, which stopped this
# script (and so the pre-push hook that runs it) dead for contributors there.
# The Microsoft Store stub also answers to "python3" but cannot run anything,
# so probe each candidate by running it rather than by finding it.
PY=
for candidate in python3 python; do
  if "$candidate" -c "import sys" >/dev/null 2>&1; then PY=$candidate; break; fi
done
[ -n "$PY" ] || { echo "No working python3 or python found."; exit 1; }
LUA="BuffRadar/Data.lua BuffRadar/BuffRadar.lua BuffRadar/Config.lua BuffRadar/Slash.lua BuffRadar/Extras.lua BuffRadar/Recaps.lua BuffRadar/Profiles.lua"
LOC="$(ls BuffRadar/Locales/*.lua)"
echo "== luacheck51";   "$PY" -I tools/luacheck51.py $LUA $LOC
echo "== lualimits";    for f in $LUA; do "$PY" -I tools/lualimits.py "$f"; done
echo "== localecheck";  "$PY" -I tools/localecheck.py BuffRadar/BuffRadar.lua BuffRadar/Locales
echo "== patterncheck"; "$PY" -I tools/patterncheck.py $LUA $LOC
echo "== smoke";        "$PY" -I tools/smoke51.py tools/wowstub.lua BuffRadar/BuffRadar.lua
echo "== coordination"; "$PY" -I tools/coordination51.py tools/wowstub.lua BuffRadar/BuffRadar.lua
echo "Gate passed. Real luacheck 1.2.0: run tools/check.ps1 on Windows."
