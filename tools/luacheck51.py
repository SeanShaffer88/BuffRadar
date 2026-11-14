"""Compile Lua files with real Lua 5.1 (via lupa) -- the same language WoW uses.

Usage: python -I luacheck51.py FILE...
Prints "OK" or the compiler's error for each file and exits non-zero if any of
them failed, so the gate stops rather than reporting past the problem. Also
self-tests both ceilings WoW enforces and luac 5.4 does not, so a pass means
something: 200 locals per chunk and 60 upvalues per function.
"""
import sys
from lupa import lua51

lua = lua51.LuaRuntime()
compile_src = lua.eval("function(src, name) local f, err = loadstring(src, name) return f ~= nil, err end")

failed = []


def locals_src(n):
    return "\n".join(f"local v{i} = {i}" for i in range(n))


def upvalues_src(n):
    """n file-scope locals plus one function reading all of them = n upvalues."""
    decls = "\n".join(f"local u{i} = {i}" for i in range(n))
    reads = "+".join(f"u{i}" for i in range(n))
    return f"{decls}\nlocal function f() return {reads} end"


# Self-test: 201 locals in one chunk must fail, 199 must pass.
ok_many, err_many = compile_src(locals_src(201), "=selftest201")
ok_few, _ = compile_src(locals_src(199), "=selftest199")
print(f"self-test: 199 locals ok={ok_few}; 201 locals ok={ok_many} ({err_many})")
if ok_many or not ok_few:
    failed.append("self-test: the 200-local limit is not being enforced")

# Self-test: 61 upvalues in one function must fail, 60 must pass. This is the
# ceiling that shipped 1.15.4 unloadable. luac 5.4 allows 255 of them, so
# nothing short of a real Lua 5.1 compile sees it, and the game only mentions
# it in Logs/FrameXML.log after it has already skipped the whole file.
ok_61, err_61 = compile_src(upvalues_src(61), "=selftest61up")
ok_60, _ = compile_src(upvalues_src(60), "=selftest60up")
print(f"self-test: 60 upvalues ok={ok_60}; 61 upvalues ok={ok_61} ({err_61})")
if ok_61 or not ok_60:
    failed.append("self-test: the 60-upvalue limit is not being enforced")

for path in sys.argv[1:]:
    with open(path, "rb") as fh:
        src = fh.read().decode("utf-8")
    ok, err = compile_src(src, "=" + path.replace("\\", "/").split("/")[-1])
    print(f"{path}: {'OK' if ok else 'FAIL: ' + str(err)}")
    if not ok:
        failed.append(f"{path}: {err}")

if failed:
    print(f"\nLUACHECK51 FAILED ({len(failed)}):")
    for line in failed:
        print(f"  {line}")
    sys.exit(1)
