"""Validate the Forever ZIP and load its Lua files in TOC order under Lua 5.1."""

import re
import sys
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree
from zipfile import BadZipFile, ZipFile

from lupa import lua51


def load_archive(archive):
    with ZipFile(archive) as package:
        broken = package.testzip()
        if broken:
            raise ValueError(f"CRC check failed for {broken}")
        members = {}
        used_names = set()
        for entry in package.infolist():
            name = entry.filename.rstrip("/")
            path = PurePosixPath(name)
            if (
                path.as_posix() != name
                or path.parts[:1] != ("BuffRadar",)
                or ".." in path.parts
                or "\\" in name
                or ":" in name
                or (len(path.parts) == 1 and not entry.is_dir())
                or name.casefold() in used_names
            ):
                raise ValueError(f"Invalid or duplicate package path: {entry.filename}")
            used_names.add(name.casefold())
            if not entry.is_dir():
                members[path.relative_to("BuffRadar").as_posix()] = package.read(entry)
    return members


def check_package(archive, project=None):
    members = load_archive(archive)
    if project is not None:
        edition = {"BuffRadar.toc", "README.md", "CHANGELOG.md", "DESCRIPTION.md", "FEATURES.md"}
        shared = project / "BuffRadar"
        expected = {path.relative_to(shared).as_posix(): path
                    for path in shared.rglob("*") if path.is_file()}
        expected.update({name: project / "editions" / "forever" / name for name in edition})
        if set(members) != set(expected):
            raise ValueError(f"Package inventory differs from source: {sorted(set(members) ^ set(expected))}")
        for name, path in expected.items():
            if members[name] != path.read_bytes():
                raise ValueError(f"Stale package entry {name}. Rebuild the ZIP.")
    toc = members["BuffRadar.toc"].decode("utf-8-sig").replace("\r\n", "\n")
    interface = re.findall(r"^## Interface:[ \t]*(.+)$", toc, re.MULTILINE)
    if len(interface) != 1 or interface[0].strip() != "16001":
        raise ValueError("The Forever TOC must declare Interface 16001")
    version = re.findall(r"^## Version:[ \t]*(\d+\.\d+\.\d+)[ \t]*$", toc, re.MULTILINE)
    if len(version) != 1 or archive.name != f"BuffRadar-{version[0]}-Forever.zip":
        raise ValueError("The ZIP filename must match the Forever TOC version")
    paths = [line.strip().replace("\\", "/") for line in toc.splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    if len(paths) != len(set(paths)):
        raise ValueError("Duplicate TOC entries")
    lua_files = {name for name in members if name.endswith(".lua")}
    if set(paths) != lua_files or not lua_files:
        raise ValueError(f"TOC and packaged Lua files differ: {sorted(set(paths) ^ lua_files)}")
    for icon in re.findall(r"^## IconTexture:[ \t]*Interface\\AddOns\\BuffRadar\\(.+)$", toc, re.MULTILINE):
        if icon.strip().replace("\\", "/") not in members:
            raise ValueError(f"Missing TOC icon asset: {icon}")

    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(Path(__file__).with_name("wowstub.lua").read_text(encoding="utf-8"))
    start = lua.eval(r"""function()
      local chat = {}
      local env = WOWSTUB(chat, true, false, true, true)
      env._G, env.strlower, env.format = env, string.lower, string.format
      setmetatable(env, {__index = _G})
      local ns = {}
      return env, function(source, name)
        local chunk = assert(loadstring(source, "@" .. name))
        setfenv(chunk, env)
        chunk("BuffRadar", ns)
      end, function()
        assert(ns.X and ns.X.OpenConfig and ns.X.HandleSlash and ns.X.Export
          and ns.X.DeathRecap, "packaged modules did not initialize")
        for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN"}) do
          for _, frame in ipairs(env.__frames) do
            if frame.events and frame.events[event] then
              frame.scripts.OnEvent(frame, event, "BuffRadar")
            end
          end
        end
        for _, line in ipairs(chat) do
          assert(not line:find("error", 1, true), line)
        end
        assert(env.BuffRadarFrame and env.SlashCmdList.BUFFRADAR, "packaged addon did not start")
      end
    end""")
    env, load, login = start()
    for path in paths:
        load(members[path].decode("utf-8-sig"), path)
    login()

    bindings = ElementTree.fromstring(members["Bindings.xml"])
    if bindings.tag != "Bindings" or not len(bindings):
        raise ValueError("Missing binding definitions")
    seen = set()
    for binding in bindings:
        name = binding.get("name")
        if binding.tag != "Binding" or not name or name in seen or not binding.get("category") or len(binding):
            raise ValueError(f"Invalid binding definition: {name}")
        seen.add(name)
        click = re.fullmatch(r"CLICK (\w+):\w+", name)
        if click:
            if env[click.group(1)] is None:
                raise ValueError(f"Missing binding target: {name}")
        else:
            code = (binding.text or "").strip()
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
