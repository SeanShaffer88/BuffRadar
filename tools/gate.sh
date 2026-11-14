#!/bin/sh
# Static checks and the six-setup smoke run used by GitHub CI.
# Usage: sh tools/gate.sh      (needs python3 or python, plus the lupa package)
set -e
cd "$(dirname "$0")/.."
# Windows and MSYS ship "python" with no python3 alias, which stopped this
# script (and so the pre-push hook that runs it) dead for contributors there.
PY=python3
command -v python3 >/dev/null 2>&1 || PY=python
LUA="BuffRadar/Data.lua BuffRadar/BuffRadar.lua BuffRadar/Config.lua BuffRadar/Slash.lua BuffRadar/Extras.lua BuffRadar/Recaps.lua BuffRadar/Profiles.lua"
LOC="$(ls BuffRadar/Locales/*.lua)"
echo "== luacheck51";   "$PY" -I tools/luacheck51.py $LUA $LOC
echo "== lualimits";    for f in $LUA; do "$PY" -I tools/lualimits.py "$f"; done
echo "== localecheck";  "$PY" -I tools/localecheck.py BuffRadar/BuffRadar.lua BuffRadar/Locales
echo "== smoke";        "$PY" -I tools/smoke51.py tools/wowstub.lua BuffRadar/BuffRadar.lua
echo "Gate passed. Real luacheck 1.2.0: run tools/check.ps1 on Windows."
