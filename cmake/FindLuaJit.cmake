# Once found, defines:
#  LuaJit_FOUND
#  LuaJit_INCLUDE_DIRS
#  LuaJit_LIBRARIES

# Doesn't seem to work:
# include(LibFindMacros)

# libfind_pkg_detect(LuaJit luajit
        # FIND_PATH luajit.h
        # PATH_SUFFIXES luajit
        # FIND_LIBRARY NAMES luajit-5.1 luajit
        # )

# libfind_process(LuaJit)


# Copying from FindRakNet, which does work:
FIND_LIBRARY (LuaJit_LIBRARIES NAMES lua51
    PATHS
    ENV LD_LIBRARY_PATH
    ENV LIBRARY_PATH
    /usr/lib64
    /usr/lib
    /usr/local/lib64
    /usr/local/lib
    /opt/local/lib
    $ENV{LUAJIT_ROOT}/lib
    )
	
FIND_PATH (LuaJit_INCLUDE_DIRS lua/luajit.h
    ENV CPATH
    /usr/include
    /usr/local/include
    /opt/local/include
	$ENV{LUAJIT_ROOT}/include
    )
 
IF(LuaJit_INCLUDE_DIRS AND LuaJit_LIBRARIES)
    SET(LuaJit_FOUND TRUE)
ENDIF(LuaJit_INCLUDE_DIRS AND LuaJit_LIBRARIES)

IF(LuaJit_FOUND)
  SET(LuaJit_INCLUDE_DIRS ${LuaJit_INCLUDE_DIRS}/lua)
	SET(LuaJit_LIBRARIES ${LuaJit_LIBRARIES} )
   
  MESSAGE(STATUS "Found LuaJit_LIBRARIES: ${LuaJit_LIBRARIES}")
  MESSAGE(STATUS "Found LuaJit_INCLUDE_DIRS: ${LuaJit_INCLUDE_DIRS}")
ELSE(LuaJit_FOUND)
  MESSAGE(FATAL_ERROR "Could not find LuaJit")
ENDIF(LuaJit_FOUND)
