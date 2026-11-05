"""Run the pure-Lua unit tests: python3 tests/run_unit.py   (requires `pip install lupa`)."""
import os, sys
from lupa.luajit21 import LuaRuntime
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failed = False
for name in ("splitflap_test.lua", "logbook_test.lua"):
    lua = LuaRuntime(unpack_returned_tuples=True)
    src = open(os.path.join(root, "tests", name)).read()
    run = lua.eval("function(src, root, name) return load(src, '@' .. name)(root) end")
    try:
        run(src, root, name)
    except Exception as e:
        print(e)
        failed = True
sys.exit(1 if failed else 0)
