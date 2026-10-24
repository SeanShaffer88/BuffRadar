"""Check BuffRadar translation files against the English table in BuffRadar.lua.

Usage: python -I localecheck.py BUFFRADAR_LUA LOCALES_DIR
Uses real Lua 5.1 (lupa) to read the `local L = { ... }` table and each
Locales\\*.lua file. Reports, per language: keys BuffRadar doesn't have (typos
or outdated text -- these are never shown), keys not translated yet (shown in
English; informational), and translations whose %d / %s placeholders or
|c / |r color codes differ from the English (these can break or garble text).
Prints "OK" or "FAIL" per file.
"""
import glob
import os
import re
import sys
from lupa import lua51

addon_path, locales_dir = sys.argv[1], sys.argv[2]
lua = lua51.LuaRuntime(unpack_returned_tuples=True)

src = open(addon_path, encoding="utf-8").read()
m = re.search(r"^local L = (\{.*?^\})", src, re.S | re.M)
if not m:
    sys.exit("could not find `local L = {` in " + addon_path)
english = dict(lua.execute("return " + m.group(1)).items())


def codes(s):
    return sorted(re.findall(r"%[ds]|\|c[0-9a-fA-F]{8}|\|r", s))


bad = False
for path in sorted(glob.glob(os.path.join(locales_dir, "*.lua"))):
    env = lua.eval("{}")
    chunk = lua.eval("function(src, name) return loadstring(src, name) end")(
        open(path, encoding="utf-8").read(), "=" + os.path.basename(path))
    if chunk is None:
        print(f"{os.path.basename(path)}: FAIL (doesn't compile)"); bad = True; continue
    lua.eval("setfenv")(chunk, env)
    chunk()
    packs = env["BuffRadarLocales"]
    for code, pack in (packs.items() if packs else []):
        pack = dict(pack.items())
        unknown = sorted(k for k in pack if k not in english)
        missing = sorted(k for k in english if k not in pack)
        mismatched = sorted(k for k in pack if k in english and codes(pack[k]) != codes(english[k]))
        status = "FAIL" if unknown or mismatched else "OK"
        bad = bad or status == "FAIL"
        print(f"{os.path.basename(path)} [{code}]: {status} - {len(pack)} of {len(english)} strings translated")
        for k in unknown:
            print(f"  not used by BuffRadar (typo or old text?): {k!r}")
        for k in mismatched:
            print(f"  placeholders/color codes differ: {k!r} -> {pack[k]!r}")
        for k in missing:
            print(f"  still English: {k!r}")
sys.exit(1 if bad else 0)
