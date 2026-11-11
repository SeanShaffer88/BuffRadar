#!/bin/sh
# Full local gate (no CI in this repo): static checks + the six-setup smoke run.
# Usage: sh tools/gate.sh      (needs python3 + the lupa package)
set -e
cd "$(dirname "$0")/.."
LUA="BuffRadar/Data.lua BuffRadar/BuffRadar.lua BuffRadar/Extras.lua"
LOC="$(ls BuffRadar/Locales/*.lua)"
echo "== luacheck51";   python3 -I tools/luacheck51.py $LUA $LOC
echo "== lualimits";    python3 -I tools/lualimits.py BuffRadar/BuffRadar.lua BuffRadar/Data.lua
echo "== localecheck";  python3 -I tools/localecheck.py BuffRadar/BuffRadar.lua BuffRadar/Locales
echo "== smoke";        OUT="$(python3 -I tools/smoke51.py tools/wowstub.lua BuffRadar/BuffRadar.lua)"; echo "$OUT"
echo "$OUT" | grep -v ", 0 with errors" | grep -q " with errors" && { echo "GATE FAILED (smoke)"; exit 1; }
echo "Gate passed. Real luacheck 1.2.0: run tools/check.ps1 on Windows."
