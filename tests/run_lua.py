"""Run Lua checks using the system Lua shared library; no installed packages."""
import ctypes
import os
import pathlib
import sys

os.environ.setdefault("LOOTGOBLIN_ADDON", str(pathlib.Path(__file__).resolve().parents[1] / "LootGoblin"))

lua = ctypes.CDLL("liblua5.4.so.0")
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]

state = lua.luaL_newstate()
lua.luaL_openlibs(state)
try:
    for filename in sys.argv[1:]:
        status = lua.luaL_loadfilex(state, str(pathlib.Path(filename).resolve()).encode(), None)
        if status == 0:
            status = lua.lua_pcallk(state, 0, -1, 0, 0, None)
        if status:
            raise SystemExit(lua.lua_tolstring(state, -1, None).decode())
finally:
    lua.lua_close(state)
