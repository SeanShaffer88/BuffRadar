"""Check BuffRadar translation files against the English table in BuffRadar.lua.

Usage: python -I localecheck.py BUFFRADAR_LUA LOCALES_DIR
Uses real Lua 5.1 (lupa) to read the `local L = { ... }` table and each
Locales\\*.lua file. Reports, per language: keys BuffRadar doesn't have (typos
or outdated text -- these are never shown), keys not translated yet (shown in
English; German must be complete), and translations whose %d / %s placeholders or
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


required = {"deDE", "esES", "frFR", "ruRU", "zhCN"}
paths = sorted(glob.glob(os.path.join(locales_dir, "*.lua")))
missing_files = required - {os.path.splitext(os.path.basename(path))[0] for path in paths}
bad = bool(missing_files)
for code in sorted(missing_files):
    print(f"{code}.lua: FAIL (missing locale file)")
for path in paths:
    filename = os.path.basename(path)
    code = os.path.splitext(filename)[0]
    env = lua.eval("{}")
    ns = lua.eval("{}")
    try:
        load = lua.eval("function(src, name, env, ns) setfenv(assert(loadstring(src, name)), env)('BuffRadar', ns) end")
        load(open(path, encoding="utf-8").read(), "=" + filename, env, ns)
        packs = dict(ns["Locales"].items()) if ns["Locales"] is not None else {}
        if set(packs) != {code} or lua51.lua_type(packs[code]) != "table" or env["BuffRadarLocales"] is not None:
            raise ValueError(f"expected one private {code} pack")
        pack = dict(packs[code].items())
        if any(not isinstance(k, str) or not isinstance(v, str) or not v for k, v in pack.items()):
            raise ValueError("expected nonempty string translations")
    except (OSError, ValueError, lua51.LuaError) as exc:
        print(f"{filename}: FAIL ({exc})")
        bad = True
        continue
    unknown = sorted(k for k in pack if k not in english)
    missing = sorted(k for k in english if k not in pack)
    mismatched = sorted(k for k in pack if k in english and codes(pack[k]) != codes(english[k]))
    status = "FAIL" if unknown or mismatched or (code == "deDE" and missing) else "OK"
    bad = bad or status == "FAIL"
    print(f"{filename} [{code}]: {status} - {len(pack)} of {len(english)} strings translated")
    for k in unknown:
        print(f"  not used by BuffRadar (typo or old text?): {k!r}")
    for k in mismatched:
        print(f"  placeholders/color codes differ: {k!r} -> {pack[k]!r}")
    for k in missing:
        print(f"  still English: {k!r}")
sys.exit(1 if bad else 0)
