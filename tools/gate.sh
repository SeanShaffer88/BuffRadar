#!/bin/sh
# Static checks and the six-setup smoke run used by GitHub CI.
# Usage: sh tools/gate.sh      (needs python3 + the lupa package)
set -e
cd "$(dirname "$0")/.."
LUA="BuffRadar/Data.lua BuffRadar/BuffRadar.lua BuffRadar/Config.lua BuffRadar/Slash.lua BuffRadar/Extras.lua BuffRadar/Recaps.lua BuffRadar/Profiles.lua"
LOC="$(ls BuffRadar/Locales/*.lua)"
echo "== luacheck51";   python3 -I tools/luacheck51.py $LUA $LOC
echo "== lualimits";    for f in $LUA; do python3 -I tools/lualimits.py "$f"; done
echo "== localecheck";  python3 -I tools/localecheck.py BuffRadar/BuffRadar.lua BuffRadar/Locales
echo "== smoke";        python3 -I tools/smoke51.py tools/wowstub.lua BuffRadar/BuffRadar.lua
echo "Gate passed. Real luacheck 1.2.0: run tools/check.ps1 on Windows."
