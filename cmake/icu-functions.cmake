# icu-functions.cmake
#
# Helper functions for building ICU4C with CMake.

# Functions -------------------------------------------------------------------------------------------------

# icuAddObjectLibrary(name dir [FOR_TOOLS])
#
# Adds an object library from `dir/sources.txt`. `FOR_TOOLS` compiles with `U_STATIC_IMPLEMENTATION`
# for the data tools, which always link statically against the stub data. Otherwise the objects follow
# `BUILD_SHARED_LIBS`: position-independent code when shared, `U_STATIC_IMPLEMENTATION` when static.
function(icuAddObjectLibrary name dir)
  icuReadSources(${dir} sources)
  add_library(${name} OBJECT ${sources})
  icuApplyCommonSettings(${name})
  target_include_directories(${name} PUBLIC ${dir})

  if(ARGN STREQUAL "FOR_TOOLS" OR NOT BUILD_SHARED_LIBS)
    target_compile_definitions(${name} PRIVATE U_STATIC_IMPLEMENTATION)
  endif()
  if(BUILD_SHARED_LIBS AND NOT ARGN STREQUAL "FOR_TOOLS")
    set_target_properties(${name} PROPERTIES POSITION_INDEPENDENT_CODE ON)
  endif()
endfunction()

# icuAddTool(name)
#
# Adds a build-time tool from `tools/name/sources.txt`. Linux, macOS, and MSYS place it at
# `ICU_TOOL_BIN_DIR/name` for `unix-exec`. Native Windows Python places it at `ICU_TOOL_DIR/name/name.exe`
# for `windows-exec`, with `<config>` directory before `name.exe` under a multi-config generator.
function(icuAddTool name)
  set(dir ${ICU_SOURCE_DIR}/tools/${name})
  icuReadSources(${dir} sources)

  set(target icu-${name})
  add_executable(${target} ${sources})
  icuApplyCommonSettings(${target})
  target_include_directories(${target} PRIVATE ${dir})
  target_compile_definitions(${target} PRIVATE U_STATIC_IMPLEMENTATION)
  target_link_libraries(${target} PRIVATE ${ICU_TOOL_OBJECT_LIBS} icudata-stub ${ICU_SYSTEM_LIBS})

  if(GAIA_PYTHON_NATIVE_WINDOWS)
    set(toolDir ${ICU_TOOL_DIR}/${name}${ICU_TOOL_CFG_SUFFIX})
  else()
    set(toolDir ${ICU_TOOL_BIN_DIR})
  endif()
  set_target_properties(${target}
    PROPERTIES
      OUTPUT_NAME ${name}
      RUNTIME_OUTPUT_DIRECTORY ${toolDir}
  )
endfunction()

# icuApplyCommonSettings(name)
#
# Applies the compiler settings ICU’s own build systems use to a target that compiles ICU sources.
function(icuApplyCommonSettings name)
  target_compile_options(${name} PRIVATE ${COMPILE_FLAGS})

  set_target_properties(${name}
    PROPERTIES
      C_STANDARD 11
      C_STANDARD_REQUIRED ON
      CXX_STANDARD 17
      CXX_STANDARD_REQUIRED ON
      CXX_EXTENSIONS OFF
  )

  target_compile_definitions(${name}
    PRIVATE
      U_ATTRIBUTE_DEPRECATED=
  )

  if(LINUX)
    target_compile_definitions(${name} PRIVATE _REENTRANT)
  elseif(WIN32)
    target_compile_definitions(${name}
      PRIVATE
        _CRT_SECURE_NO_DEPRECATE
        U_PLATFORM_USES_ONLY_WIN32_API=1
        WIN32_LEAN_AND_MEAN
    )
  endif()
endfunction()

# icuFetch(name url)
#
# Downloads and extracts an archive, setting `${name}_SOURCE_DIR`.
function(icuFetch name url)
  gaiaStatus("fetching `${url}` ...")
  FetchContent_Declare(
    ${name}
    URL ${url}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    EXCLUDE_FROM_ALL
  )
  # The archives contain no `CMakeLists.txt` at their root, so this only downloads and extracts
  FetchContent_MakeAvailable(${name})

  set(${name}_SOURCE_DIR ${${name}_SOURCE_DIR} PARENT_SCOPE)
endfunction()

# icuReadSources(dir out)
#
# Reads `dir/sources.txt` and returns the listed files with `dir/` prepended.
function(icuReadSources dir out)
  set(file ${dir}/sources.txt)
  if(NOT EXISTS ${file})
    gaiaFatalError("missing `${file}`")
  endif()

  file(STRINGS ${file} lines)
  set(sources)
  foreach(line IN LISTS lines)
    string(STRIP "${line}" line)
    if(line STREQUAL "" OR line MATCHES "^#")
      continue()
    endif()
    list(APPEND sources ${dir}/${line})
  endforeach()

  set(${out} ${sources} PARENT_SCOPE)
endfunction()

# icuReadVersion(sourceDir outVersion outMajor)
#
# Reads `U_ICU_VERSION` and `U_ICU_VERSION_MAJOR_NUM` from `common/unicode/uvernum.h`.
function(icuReadVersion sourceDir outVersion outMajor)
  set(header ${sourceDir}/common/unicode/uvernum.h)
  if(NOT EXISTS ${header})
    gaiaFatalError("missing `${header}`")
  endif()

  file(STRINGS ${header} majorLine REGEX "^#define U_ICU_VERSION_MAJOR_NUM[ \t]+[0-9]+")
  string(REGEX REPLACE "^#define U_ICU_VERSION_MAJOR_NUM[ \t]+([0-9]+).*$" "\\1" major "${majorLine}")

  file(STRINGS ${header} versionLine REGEX "^#define U_ICU_VERSION[ \t]+\"[0-9.]+\"")
  string(REGEX REPLACE "^#define U_ICU_VERSION[ \t]+\"([0-9.]+)\".*$" "\\1" version "${versionLine}")

  if(NOT major MATCHES "^[0-9]+$" OR NOT version MATCHES "^[0-9.]+$")
    gaiaFatalError("cannot parse the ICU version from `${header}`")
  endif()

  set(${outVersion} ${version} PARENT_SCOPE)
  set(${outMajor} ${major} PARENT_SCOPE)
endfunction()

# EOF
