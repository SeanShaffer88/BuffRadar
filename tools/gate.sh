#!/bin/sh
# Static checks and the TOC-driven smoke run used by GitHub CI.
# Usage: sh tools/gate.sh      (needs python3 or python, plus the lupa package)
set -e
cd "$(dirname "$0")/.."
# Windows and MSYS ship "python" with no python3 alias, which stopped this
# script (and so the pre-push hook that runs it) dead for contributors there.
# The Microsoft Store stub also answers to "python3" but cannot run anything,
# so probe each candidate by running it rather than by finding it.
PY=
for candidate in python3 python; do
  if "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then PY=$candidate; break; fi
done
[ -n "$PY" ] || { echo "Python 3.10 or newer is required."; exit 1; }
# Check all shared modules, including files added to either edition.
echo "== luacheck51";   "$PY" -I tools/luacheck51.py BuffRadar/*.lua BuffRadar/Locales/*.lua
echo "== lualimits";    for f in BuffRadar/*.lua; do "$PY" -I tools/lualimits.py "$f"; done
echo "== localecheck";  "$PY" -I tools/localecheck.py BuffRadar/BuffRadar.lua BuffRadar/Locales
echo "== locale regression fixtures"; "$PY" -I tools/test_localecheck.py
echo "== visible localization callsites"; "$PY" -I tools/localization_callsites.py
echo "== visible localization fixtures"; "$PY" -I tools/test_localization_callsites.py
echo "== locale-first flows"; "$PY" -I tools/locale_flows51.py
echo "== patterncheck"; "$PY" -I tools/patterncheck.py BuffRadar/*.lua BuffRadar/Locales/*.lua
echo "== smoke";        "$PY" -I tools/smoke51.py tools/wowstub.lua BuffRadar/BuffRadar.lua
echo "== coordination"; "$PY" -I tools/coordination51.py tools/wowstub.lua BuffRadar/BuffRadar.lua
echo "== packaging regression tests"; "$PY" -I tools/test_package.py
echo "Gate passed. Real luacheck 1.2.0: run tools/check.ps1 on Windows."
