# Once found, defines:
#  LuaJit_FOUND
#  LuaJit_INCLUDE_DIRS
#  LuaJit_LIBRARIES

# Doesn't seem to work
# include(LibFindMacros)

# libfind_pkg_detect(LuaJit luajit
        # FIND_PATH luajit.h
        # PATH_SUFFIXES luajit
        # FIND_LIBRARY NAMES luajit-5.1 luajit
        # )

# libfind_process(LuaJit)

# attempt to hard-code -- doesn't work with either _DIR/_LIBRARY or _DIRS/_LIBRARIES
# set (LuaJit_INCLUDE_DIR D:/GitHub/TES3MP/deps/luajit/include)
# set (LuaJit_LIBRARY D:/GitHub/TES3MP/deps/luajit/lib/lua51.lib)
# set (LuaJit_FOUND TRUE)