#
# IcuHelpers.cmake
#
# Helper functions for building ICU4C with CMake.
#

# Functions -------------------------------------------------------------------------------------------------

# IcuAddExecutable(name srcFile...)
function(IcuAddExecutable name)
  add_executable(${name})
  target_sources(${name} PRIVATE ${ARGN})
endfunction()

# IcuAddObjectLibrary(name dir)
#
# Adds an object library from `dir/sources.txt`.
function(IcuAddObjectLibrary name dir)
  IcuReadSources(${dir} sources)
  add_library(${name} OBJECT ${sources})
  IcuApplyCommonSettings(${name})
  target_include_directories(${name} PUBLIC ${dir})
endfunction()

# IcuAddTool(name)
#
# Adds a build-time tool from `tools/name/sources.txt`. The executable is placed at `ICU_TOOL_BIN_DIR/name`,
# where `icutools.databuilder` looks for it.
function(IcuAddTool name)
  set(dir ${ICU_SOURCE_DIR}/tools/${name})
  IcuReadSources(${dir} sources)

  set(target icu-${name})
  add_executable(${target} ${sources})
  IcuApplyCommonSettings(${target})
  target_include_directories(${target} PRIVATE ${dir})
  target_link_libraries(${target} PRIVATE icutu-obj icui18n-obj icuuc-obj icudata-stub ${ICU_SYSTEM_LIBS})

  set_target_properties(${target}
    PROPERTIES
      OUTPUT_NAME ${name}
      RUNTIME_OUTPUT_DIRECTORY ${ICU_TOOL_BIN_DIR}
  )
endfunction()

# IcuAddVar(name type default doc)
#
# Adds a CMMake variable. If it is already set, it is left unchanged. Otherwise, if there is an environment
# variable with the same name, it is used. As a fallback, the default value is used.
function(IcuAddVar name type default doc)
  if(NOT DEFINED ${name})
    if(NOT $ENV{${name}} STREQUAL "")
      set(${name} $ENV{${name}} CACHE ${type} "${doc}")
      IcuStatus("Setting ${name} by environment: ${${name}}")
    else()
      set(${name} ${default} CACHE ${type} "${doc}")
      IcuStatus("Setting ${name} to default: ${${name}}")
    endif()
  else()
    IcuStatus("Found ${name}: ${${name}}")
  endif()
endfunction()

# IcuApplyCommonSettings(name)
#
# Applies the compiler settings ICU's own build systems use to a target that compiles ICU sources.
function(IcuApplyCommonSettings name)
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
      U_STATIC_IMPLEMENTATION
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

  # MSVC and clang-cl: source and execution character set UTF-8, treat "not all control paths return a
  # value" as an error, like ICU's Visual Studio projects do
  target_compile_options(${name}
    PRIVATE
      $<$<COMPILE_LANG_AND_ID:CXX,MSVC>:/utf-8 /we4715>
      $<$<COMPILE_LANG_AND_ID:C,MSVC>:/utf-8 /we4715>
      $<$<AND:$<COMPILE_LANG_AND_ID:CXX,Clang>,$<STREQUAL:${CMAKE_CXX_SIMULATE_ID},MSVC>>:/utf-8>
      $<$<AND:$<COMPILE_LANG_AND_ID:C,Clang>,$<STREQUAL:${CMAKE_C_SIMULATE_ID},MSVC>>:/utf-8>
  )
endfunction()

# IcuFatalError(msg)
function(IcuFatalError msg)
  message(FATAL_ERROR "${PROJECT_NAME}: ${msg}")
endfunction()

# IcuReadSources(dir out)
#
# Reads `dir/sources.txt` and returns the listed files with `dir/` prepended.
function(IcuReadSources dir out)
  set(file ${dir}/sources.txt)
  if(NOT EXISTS ${file})
    IcuFatalError("Missing ${file}")
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

# IcuReadVersion(sourceDir outVersion outMajor)
#
# Reads `U_ICU_VERSION` and `U_ICU_VERSION_MAJOR_NUM` from `common/unicode/uvernum.h`.
function(IcuReadVersion sourceDir outVersion outMajor)
  set(header ${sourceDir}/common/unicode/uvernum.h)
  if(NOT EXISTS ${header})
    IcuFatalError("Missing ${header}")
  endif()

  file(STRINGS ${header} majorLine REGEX "^#define U_ICU_VERSION_MAJOR_NUM[ \t]+[0-9]+")
  string(REGEX REPLACE "^#define U_ICU_VERSION_MAJOR_NUM[ \t]+([0-9]+).*$" "\\1" major "${majorLine}")

  file(STRINGS ${header} versionLine REGEX "^#define U_ICU_VERSION[ \t]+\"[0-9.]+\"")
  string(REGEX REPLACE "^#define U_ICU_VERSION[ \t]+\"([0-9.]+)\".*$" "\\1" version "${versionLine}")

  if(NOT major MATCHES "^[0-9]+$" OR NOT version MATCHES "^[0-9.]+$")
    IcuFatalError("Cannot parse the ICU version from ${header}")
  endif()

  set(${outVersion} ${version} PARENT_SCOPE)
  set(${outMajor} ${major} PARENT_SCOPE)
endfunction()

# IcuStatus(msg)
function(IcuStatus msg)
  message(STATUS "${PROJECT_NAME}: ${msg}")
endfunction()

# IcuUnixPath(in out)
function(IcuUnixPath in out)
  if(WIN32)
    execute_process(COMMAND cygpath -u ${in} OUTPUT_VARIABLE localOut)
    string(STRIP ${localOut} localOut)
    set(${out} ${localOut} PARENT_SCOPE)
  else()
    set(${out} ${in} PARENT_SCOPE)
  endif()
endfunction()

# EOF
