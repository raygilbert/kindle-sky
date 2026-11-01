"""Run the pure-Lua unit tests: python3 tests/run_unit.py   (requires `pip install lupa`)."""
import os, sys
from lupa.luajit21 import LuaRuntime
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = LuaRuntime(unpack_returned_tuples=True)
src = open(os.path.join(root, "tests", "splitflap_test.lua")).read()
run = lua.eval("function(src, root) return load(src, '@splitflap_test.lua')(root) end")
try:
    run(src, root)
except Exception as e:
    print(e)
    sys.exit(1)
