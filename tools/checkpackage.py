"""Validate the Forever ZIP and load its Lua files in TOC order under Lua 5.1."""

import re
import runpy
import stat
import sys
from pathlib import Path
from xml.etree import ElementTree
from zipfile import BadZipFile, ZIP_STORED, ZipFile

from lupa import lua51

manifest = runpy.run_path(str(Path(__file__).with_name("package.py")))
BINDINGS = {
    "CLICK BuffRadarNextButton:LeftButton": "",
    "CLICK BuffRadarGroupButton:LeftButton": "",
    "BUFFRADAR_TOGGLE": "BuffRadar_ToggleWindow()",
    "BUFFRADAR_MUTE": "BuffRadar_ToggleSound()",
    "BUFFRADAR_ACTIONS": "BuffRadar_OpenActions()",
}


def load_archive(archive, require_deterministic=False):
    with ZipFile(archive) as package:
        broken = package.testzip()
        if broken:
            raise ValueError(f"CRC check failed for {broken}")
        members, spellings = {}, {}
        used_names = set()
        if require_deterministic and (package.comment or package.namelist() != sorted(package.namelist())):
            raise ValueError("Expected deterministic archive metadata and member order")
        for entry in package.infolist():
            name = entry.filename[:-1] if entry.is_dir() else entry.filename
            path = manifest["register_path"](name, spellings)
            if (
                entry.orig_filename != entry.filename
                or path.parts[:1] != ("BuffRadar",)
                or (len(path.parts) == 1 and not entry.is_dir())
                or stat.S_ISLNK(entry.external_attr >> 16)
                or name in used_names
            ):
                raise ValueError(f"Invalid or duplicate package path: {entry.filename}")
            if require_deterministic and (entry.is_dir() or entry.compress_type != ZIP_STORED
                    or entry.date_time != manifest["FIXED_DATE"] or entry.create_system != 3
                    or entry.external_attr != manifest["FIXED_MODE"] or entry.extra or entry.comment):
                raise ValueError(f"Unexpected package metadata: {entry.filename}")
            used_names.add(name)
            if not entry.is_dir():
                members[path.relative_to("BuffRadar").as_posix()] = package.read(entry)
    return members


def check_package(archive, project=None):
    members = load_archive(archive, require_deterministic=project is not None)
    if project is not None:
        _, expected = manifest["source_manifest"](project)
        if set(members) != set(expected):
            raise ValueError(f"Package inventory differs from source: {sorted(set(members) ^ set(expected))}")
        for name, path in expected.items():
            if members[name] != path.read_bytes():
                raise ValueError(f"Stale package entry {name}. Rebuild the ZIP.")
    toc = members["BuffRadar.toc"].decode("utf-8-sig").replace("\r\n", "\n")
    manifest["metadata"](toc, "Interface", manifest["INTERFACE"])
    version = manifest["metadata"](toc, "Version", r"[0-9]+\.[0-9]+\.[0-9]+")
    if archive.name != f"BuffRadar-{version}-Forever.zip":
        raise ValueError("The ZIP filename must match the Forever TOC version")
    sums = archive.with_name("SHA256SUMS.txt")
    if (project is not None or sums.exists()) and sums.read_bytes() != manifest["checksum"](archive).encode("ascii"):
        raise ValueError("SHA256SUMS.txt does not match the archive bytes")
    paths = [line.strip().replace("\\", "/") for line in toc.splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    if len(paths) != len(set(paths)):
        raise ValueError("Duplicate TOC entries")
    lua_files = {name for name in members if name.endswith(".lua")}
    if set(paths) != lua_files or not lua_files:
        raise ValueError(f"TOC and packaged Lua files differ: {sorted(set(paths) ^ lua_files)}")
    expected_names = lua_files | manifest["EDITION"] | manifest["SHARED_ASSETS"]
    if set(members) != expected_names:
        raise ValueError(f"Unexpected package inventory: {sorted(set(members) ^ expected_names)}")
    for icon in re.findall(r"^## IconTexture:[ \t]*Interface\\AddOns\\BuffRadar\\(.+)$", toc, re.MULTILINE):
        if icon.strip().replace("\\", "/") not in members:
            raise ValueError(f"Missing TOC icon asset: {icon}")

    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(Path(__file__).with_name("wowstub.lua").read_text(encoding="utf-8"))
    start = lua.eval(r"""function(version)
      local chat = {}
      local env = WOWSTUB(chat, true, false, true, false)
      env._G, env.strlower, env.format = env, string.lower, string.format
      env.C_AddOns = { GetAddOnMetadata = function(addon, key)
        if addon == "BuffRadar" and key == "Version" then return version end
      end }
      setmetatable(env, {__index = _G})
      local ns = {}
      return env, function(source, name)
        local chunk = assert(loadstring(source, "@" .. name))
        setfenv(chunk, env)
        chunk("BuffRadar", ns)
      end, function()
        assert(ns.X and ns.X.OpenConfig and env.SlashCmdList.BUFFRADAR and ns.X.Export
          and ns.X.DeathRecap, "packaged modules did not initialize")
        for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN"}) do
          for _, frame in ipairs(env.__frames) do
            if frame.events and frame.events[event] then
              frame.scripts.OnEvent(frame, event, "BuffRadar")
            end
          end
        end
        assert(ns.X.classic and env.BuffRadarFrame and env.SlashCmdList.BUFFRADAR, "packaged addon did not start")
        local nextLine, versionFound = #chat + 1, false
        env.SlashCmdList.BUFFRADAR("selftest")
        for i, line in ipairs(chat) do
          assert(not line:find("|cffff4040error:|r", 1, true), line)
          if i >= nextLine and line:find("version " .. version .. " · Forever edition · interface 16001", 1, true) then
            versionFound = true
          end
        end
        assert(versionFound, "Self-test did not report the installed version and edition")
      end
    end""")
    env, load, login = start(version)
    for path in paths:
        load(members[path].decode("utf-8-sig"), path)
    login()

    bindings = ElementTree.fromstring(members["Bindings.xml"])
    if bindings.tag != "Bindings" or len(bindings) != len(BINDINGS):
        raise ValueError("Missing binding definitions")
    seen = set()
    for binding in bindings:
        name = binding.get("name")
        code = (binding.text or "").strip()
        if (binding.tag != "Binding" or name not in BINDINGS or name in seen
                or binding.get("category") != "BUFFRADAR" or len(binding) or code != BINDINGS[name]):
            raise ValueError(f"Invalid binding definition: {name}")
        seen.add(name)
        click = re.fullmatch(r"CLICK (\w+):\w+", name)
        if click:
            if env[click.group(1)] is None:
                raise ValueError(f"Missing binding target: {name}")
        else:
            handler = re.fullmatch(r"(\w+)\(\)", code)
            if not handler or lua.eval("type")(env[handler.group(1)]) != "function":
                raise ValueError(f"Missing binding handler: {name}")
    print(f"{archive.name}: {len(members)} files, {len(paths)} TOC entries, {len(seen)} bindings")


if __name__ == "__main__":
    if len(sys.argv) not in {2, 3}:
        sys.exit("usage: checkpackage.py BuffRadar-<version>-Forever.zip [PROJECT_ROOT]")
    try:
        check_package(Path(sys.argv[1]), Path(sys.argv[2]) if len(sys.argv) == 3 else None)
    except (BadZipFile, KeyError, OSError, ValueError, ElementTree.ParseError, lua51.LuaError) as exc:
        sys.exit(f"Forever package check failed: {exc}")
