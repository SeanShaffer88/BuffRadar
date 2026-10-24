"""Compile Lua files with real Lua 5.1 (via lupa) -- the same language WoW uses.

Usage: python -I luacheck51.py FILE...
Prints "OK" or the compiler's error for each file. Also self-tests that the
200-local limit is enforced, so a pass means something.
"""
import sys
from lupa import lua51

lua = lua51.LuaRuntime()
compile_src = lua.eval("function(src, name) local f, err = loadstring(src, name) return f ~= nil, err end")

# Self-test: 201 locals in one chunk must fail, 199 must pass.
ok_many, err_many = compile_src("\n".join(f"local v{i} = {i}" for i in range(201)), "=selftest201")
ok_few, _ = compile_src("\n".join(f"local v{i} = {i}" for i in range(199)), "=selftest199")
print(f"self-test: 199 locals ok={ok_few}; 201 locals ok={ok_many} ({err_many})")

for path in sys.argv[1:]:
    with open(path, "rb") as fh:
        src = fh.read().decode("utf-8")
    ok, err = compile_src(src, "=" + path.replace("\\", "/").split("/")[-1])
    print(f"{path}: {'OK' if ok else 'FAIL: ' + str(err)}")
