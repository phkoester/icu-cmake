#
# CMakeLists.txt
#
# Builds the ICU libraries `icudata`, `icuuc`, `icui18n`, `icuio`, and `icutu`.
#
# Bootstrap order:
#
# 1. Object libraries for `common`, `i18n`, `io`, and `toolutil`
# 2. The stub data library and the ICU build tools (linked against the object libraries and the stub data)
# 3. The ICU data, generated from the text sources by `icutools.databuilder` and the tools
# 4. The libraries, assembled from the object libraries and the generated data. Static, unless
#    `BUILD_SHARED_LIBS` is on (`.so` on Linux, DLL on Windows).
#

include(GNUInstallDirs)

set(ICU_DATA_DIR      ${CMAKE_CURRENT_BINARY_DIR}/data)
set(ICU_GENERATED_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated)
set(ICU_TOOL_DIR      ${CMAKE_CURRENT_BINARY_DIR}/tools)

# `unix-exec` expects tools at `TOOL_DIR/name`. With a multi-config generator, each configuration gets its
# own `TOOL_DIR`. Native Windows Python uses `windows-exec` and a per-tool directory; see `IcuAddTool`.
get_property(isMultiConfig GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(isMultiConfig)
  set(toolBinDirSuffix /$<CONFIG>)
else()
  set(toolBinDirSuffix)
endif()
set(ICU_TOOL_BIN_DIR ${ICU_TOOL_DIR}${toolBinDirSuffix})

# System libraries ..........................................................................................

set(ICU_SYSTEM_LIBS Threads::Threads)
if(LINUX)
  list(APPEND ICU_SYSTEM_LIBS ${CMAKE_DL_LIBS})
elseif(WIN32)
  list(APPEND ICU_SYSTEM_LIBS advapi32)
endif()

# Data format ...............................................................................................
#
# - `asm`:    `genccode -a gcc` writes a `.S` file (Linux)
# - `object`: `genccode -o` writes a `.obj` file directly (Windows)
# - `c`:      `genccode` writes a `.c` file with a byte array (any platform; slow to compile)

if(WIN32)
  set(defaultDataFormat object)
else()
  set(defaultDataFormat asm)
endif()
IcuAddVar(ICU_CMAKE_DATA_FORMAT  STRING ${defaultDataFormat} "Format of the generated data: `asm`, `object`, or `c`")
IcuAddVar(ICU_CMAKE_DATA_VERBOSE BOOL   OFF                  "Print every command of the ICU data build")

if(NOT ICU_CMAKE_DATA_FORMAT MATCHES "^(asm|object|c)$")
  IcuFatalError("ICU_CMAKE_DATA_FORMAT: Invalid value `${ICU_CMAKE_DATA_FORMAT}`")
endif()
if(ICU_CMAKE_DATA_FORMAT STREQUAL "asm" AND WIN32)
  IcuFatalError("ICU_CMAKE_DATA_FORMAT=asm is not supported on Windows")
endif()
if(ICU_CMAKE_DATA_FORMAT STREQUAL "object" AND NOT WIN32)
  IcuFatalError("ICU_CMAKE_DATA_FORMAT=object is only supported on Windows")
endif()
if(ICU_CMAKE_DATA_FORMAT STREQUAL "asm")
  enable_language(ASM)
endif()

# Object libraries ------------------------------------------------------------------------------------------

IcuAddObjectLibrary(icuuc-obj ${ICU_SOURCE_DIR}/common)
target_compile_definitions(icuuc-obj PRIVATE U_COMMON_IMPLEMENTATION)
if(LINUX)
  # Lets `genccode` write ELF object files
  target_compile_definitions(icuuc-obj PUBLIC U_HAVE_ELF_H=1)
endif()

IcuAddObjectLibrary(icui18n-obj ${ICU_SOURCE_DIR}/i18n)
target_compile_definitions(icui18n-obj PRIVATE U_I18N_IMPLEMENTATION)
target_link_libraries(icui18n-obj PUBLIC icuuc-obj)

IcuAddObjectLibrary(icuio-obj ${ICU_SOURCE_DIR}/io)
target_compile_definitions(icuio-obj PRIVATE U_IO_IMPLEMENTATION)
target_link_libraries(icuio-obj PUBLIC icui18n-obj)

IcuAddObjectLibrary(icutu-obj ${ICU_SOURCE_DIR}/tools/toolutil)
target_compile_definitions(icutu-obj
  PRIVATE
    U_TOOLUTIL_IMPLEMENTATION
    UNISTR_FROM_CHAR_EXPLICIT=explicit
    UNISTR_FROM_STRING_EXPLICIT=explicit
)
target_link_libraries(icutu-obj PUBLIC icui18n-obj)

# The data tools always link ICU statically. On Windows, objects compiled for a DLL dllimport symbols from
# the other DLLs, so those objects cannot be linked into the tools. The tools get their own static objects.
if(WIN32 AND BUILD_SHARED_LIBS)
  IcuAddObjectLibrary(icuuc-tool ${ICU_SOURCE_DIR}/common FOR_TOOLS)
  target_compile_definitions(icuuc-tool PRIVATE U_COMMON_IMPLEMENTATION)

  IcuAddObjectLibrary(icui18n-tool ${ICU_SOURCE_DIR}/i18n FOR_TOOLS)
  target_compile_definitions(icui18n-tool PRIVATE U_I18N_IMPLEMENTATION)
  target_link_libraries(icui18n-tool PUBLIC icuuc-tool)

  IcuAddObjectLibrary(icutu-tool ${ICU_SOURCE_DIR}/tools/toolutil FOR_TOOLS)
  target_compile_definitions(icutu-tool
    PRIVATE
      U_TOOLUTIL_IMPLEMENTATION
      UNISTR_FROM_CHAR_EXPLICIT=explicit
      UNISTR_FROM_STRING_EXPLICIT=explicit
  )
  target_link_libraries(icutu-tool PUBLIC icui18n-tool)

  set(ICU_TOOL_OBJECT_LIBS icutu-tool icui18n-tool icuuc-tool)
else()
  set(ICU_TOOL_OBJECT_LIBS icutu-obj icui18n-obj icuuc-obj)
endif()

# Stub data -------------------------------------------------------------------------------------------------
#
# The build tools link against this empty data package, which lets them run before the real data exists.

IcuReadSources(${ICU_SOURCE_DIR}/stubdata stubSources)
add_library(icudata-stub STATIC ${stubSources})
IcuApplyCommonSettings(icudata-stub)
target_compile_definitions(icudata-stub PRIVATE STUBDATA_BUILD U_STATIC_IMPLEMENTATION)
target_include_directories(icudata-stub PRIVATE ${ICU_SOURCE_DIR}/common)

# Build tools -----------------------------------------------------------------------------------------------

set(ICU_TOOLS
  genbrk
  gencfu
  gencnval
  gendict
  genrb
  gensprep
  icupkg
  makeconv
  pkgdata
  genccode
)
foreach(it IN LISTS ICU_TOOLS)
  IcuAddTool(${it})
endforeach()

set(toolTargets ${ICU_TOOLS})
list(TRANSFORM toolTargets PREPEND icu-)

# Data ------------------------------------------------------------------------------------------------------

# The tools look up individual data files in `<data dir>/<package name>/`, so the output directory must be
# named after the package (like `out/build/icudt79l` in ICU's own build)
set(dataOutDir ${ICU_DATA_DIR}/out/${ICU_DATA_NAME})
set(dataTmpDir ${ICU_DATA_DIR}/tmp)
set(dataList   ${dataTmpDir}/icudata.lst)
set(datFile    ${ICU_DATA_DIR}/${ICU_DATA_NAME}.dat)

# Step 1: Compile the text sources into binary data files ...................................................

# MSYS Python treats `C:/...` as a relative path, so it receives Unix paths and `unix-exec`, as on Linux.
# Native Windows Python receives backslash paths and `windows-exec`: that mode rewrites `/` to `\` for
# `cmd`, and switches to PowerShell when a command exceeds `cmd`'s 8191-character limit.
IcuPythonPath("${ICU_DATA_SOURCE_DIR}" pySrcDir)
IcuPythonPath("${dataOutDir}"          pyOutDir)
IcuPythonPath("${dataTmpDir}"          pyTmpDir)
IcuPythonPath("${ICU_TOOL_DIR}"        pyToolDir)
if(ICU_PYTHON_NATIVE_WINDOWS)
  set(databuilderArgs --mode windows-exec --tool_dir "${pyToolDir}" --tool_cfg "$<CONFIG>")
else()
  set(pyToolDir "${pyToolDir}${toolBinDirSuffix}")
  set(databuilderArgs --mode unix-exec --tool_dir "${pyToolDir}")
endif()
set(databuilderDeps)
if(NOT ICU_CMAKE_DATA_FILTER_FILE STREQUAL "")
  IcuPythonPath("${ICU_CMAKE_DATA_FILTER_FILE}" pyFilterFile)
  list(APPEND databuilderArgs --filter_file "${pyFilterFile}")
  list(APPEND databuilderDeps ${ICU_CMAKE_DATA_FILTER_FILE})
endif()
if(ICU_CMAKE_DATA_VERBOSE)
  list(APPEND databuilderArgs --verbose)
endif()

# `python -m` puts the working directory first on `sys.path`, which is how `icutools` is found. (Setting
# `PYTHONPATH` to a Windows path would break the Git SDK Python, which splits `C:/...` at the colon.)
add_custom_command(
  OUTPUT  ${dataList}
  COMMAND ${CMAKE_COMMAND} -E rm -rf ${dataOutDir} ${dataTmpDir}
  COMMAND ${CMAKE_COMMAND} -E make_directory ${dataOutDir} ${dataTmpDir}
  COMMAND ${CMAKE_COMMAND} -E env PYTHONDONTWRITEBYTECODE=1
            ${Python3_EXECUTABLE} -m icutools.databuilder
              --src_dir "${pySrcDir}"
              --out_dir "${pyOutDir}"
              --tmp_dir "${pyTmpDir}"
              ${databuilderArgs}
  DEPENDS ${toolTargets} ${ICU_DATA_SOURCE_DIR}/BUILDRULES.py ${databuilderDeps}
  WORKING_DIRECTORY ${ICU_SOURCE_DIR}/python
  COMMENT "icu-cmake: Building the ICU data files (this takes a while)"
  VERBATIM
)

# Step 2: Package the data files into one `.dat` archive ....................................................

add_custom_command(
  OUTPUT  ${datFile}
  COMMAND icu-pkgdata -m common -q -c -p ${ICU_DATA_NAME} -s ${dataOutDir} -T ${dataTmpDir} -d ${ICU_DATA_DIR}
            ${dataList}
  DEPENDS icu-pkgdata ${dataList}
  COMMENT "icu-cmake: Packaging ${ICU_DATA_NAME}.dat"
  VERBATIM
)

# Step 3: Turn the archive into a compilable source or object file ..........................................

set(genccodeArgs -q -d ${ICU_GENERATED_DIR} -e ${ICU_DATA_ENTRY_POINT})
if(ICU_CMAKE_DATA_FORMAT STREQUAL "asm")
  set(dataFile ${ICU_GENERATED_DIR}/${ICU_DATA_NAME}_dat.S)
  list(APPEND genccodeArgs -a gcc)
elseif(ICU_CMAKE_DATA_FORMAT STREQUAL "object")
  set(dataFile ${ICU_GENERATED_DIR}/${ICU_DATA_NAME}_dat.obj)
  if(CMAKE_GENERATOR_PLATFORM MATCHES "^(Win32|x86)$")
    set(cpuArch x86)
  elseif(CMAKE_GENERATOR_PLATFORM MATCHES "^ARM64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "^(ARM64|aarch64)")
    set(cpuArch arm64)
  elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(cpuArch x64)
  else()
    set(cpuArch x86)
  endif()
  list(APPEND genccodeArgs -o -c ${cpuArch})
  if(NOT BUILD_SHARED_LIBS)
    list(APPEND genccodeArgs --skip-dll-export)
  endif()
else()
  set(dataFile ${ICU_GENERATED_DIR}/${ICU_DATA_NAME}_dat.c)
endif()

add_custom_command(
  OUTPUT  ${dataFile}
  COMMAND ${CMAKE_COMMAND} -E make_directory ${ICU_GENERATED_DIR}
  COMMAND icu-genccode ${genccodeArgs} ${datFile}
  DEPENDS icu-genccode ${datFile}
  COMMENT "icu-cmake: Generating ${dataFile}"
  VERBATIM
)

# Libraries -------------------------------------------------------------------------------------------------

if(BUILD_SHARED_LIBS)
  set(icuLibraryType SHARED)
else()
  set(icuLibraryType STATIC)
endif()

# `icudata` .................................................................................................

add_library(icudata ${icuLibraryType} ${dataFile})
if(ICU_CMAKE_DATA_FORMAT STREQUAL "c")
  IcuApplyCommonSettings(icudata)
  target_include_directories(icudata PRIVATE ${ICU_SOURCE_DIR}/common)
  if(NOT BUILD_SHARED_LIBS)
    target_compile_definitions(icudata PRIVATE U_STATIC_IMPLEMENTATION)
  endif()
endif()
if(BUILD_SHARED_LIBS)
  if(WIN32)
    # Data-only DLL: there is no `DllMain`. The object format already emits the export directive.
    target_link_options(icudata PRIVATE "/NOENTRY")
    if(NOT ICU_CMAKE_DATA_FORMAT STREQUAL "object")
      target_link_options(icudata PRIVATE "/EXPORT:${ICU_DATA_ENTRY_POINT}_dat,DATA")
    endif()
  else()
    # Same link line ICU uses for `libicudata`: the archive is pure data
    target_link_options(icudata PRIVATE -nodefaultlibs -nostdlib)
  endif()
endif()
set_target_properties(icudata
  PROPERTIES
    EXPORT_NAME     data
    LINKER_LANGUAGE C
    OUTPUT_NAME     icudata
)
add_library(icu-cmake::data ALIAS icudata)

# `icuuc` ...................................................................................................

add_library(icuuc ${icuLibraryType} $<TARGET_OBJECTS:icuuc-obj>)
if(NOT BUILD_SHARED_LIBS)
  # Static consumers take the symbols from the `.a` / `.lib`, so the headers leave them undecorated
  target_compile_definitions(icuuc INTERFACE U_STATIC_IMPLEMENTATION)
endif()
target_compile_features(icuuc INTERFACE cxx_std_17)
# Imported targets are treated as system includes anyway, so only the build interface is marked `SYSTEM`
target_include_directories(icuuc SYSTEM INTERFACE $<BUILD_INTERFACE:${ICU_SOURCE_DIR}/common>)
target_include_directories(icuuc INTERFACE $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>)
target_link_libraries(icuuc PUBLIC icudata ${ICU_SYSTEM_LIBS})
set_target_properties(icuuc
  PROPERTIES
    EXPORT_NAME     uc
    LINKER_LANGUAGE CXX
    OUTPUT_NAME     icuuc
)
add_library(icu-cmake::uc ALIAS icuuc)

# `icui18n` .................................................................................................

add_library(icui18n ${icuLibraryType} $<TARGET_OBJECTS:icui18n-obj>)
target_include_directories(icui18n SYSTEM INTERFACE $<BUILD_INTERFACE:${ICU_SOURCE_DIR}/i18n>)
target_link_libraries(icui18n PUBLIC icuuc)
set_target_properties(icui18n
  PROPERTIES
    EXPORT_NAME     i18n
    LINKER_LANGUAGE CXX
    OUTPUT_NAME     icui18n
)
add_library(icu-cmake::i18n ALIAS icui18n)

# `icuio` ...................................................................................................

add_library(icuio ${icuLibraryType} $<TARGET_OBJECTS:icuio-obj>)
target_include_directories(icuio SYSTEM INTERFACE $<BUILD_INTERFACE:${ICU_SOURCE_DIR}/io>)
target_link_libraries(icuio PUBLIC icui18n)
set_target_properties(icuio
  PROPERTIES
    EXPORT_NAME     io
    LINKER_LANGUAGE CXX
    OUTPUT_NAME     icuio
)
add_library(icu-cmake::io ALIAS icuio)

# `icutu` ...................................................................................................

add_library(icutu ${icuLibraryType} $<TARGET_OBJECTS:icutu-obj>)
target_include_directories(icutu SYSTEM INTERFACE $<BUILD_INTERFACE:${ICU_SOURCE_DIR}/tools/toolutil>)
target_include_directories(icutu INTERFACE $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/icu/toolutil>)
target_link_libraries(icutu PUBLIC icui18n)
set_target_properties(icutu
  PROPERTIES
    EXPORT_NAME     tu
    LINKER_LANGUAGE CXX
    OUTPUT_NAME     icutu
)
add_library(icu-cmake::tu ALIAS icutu)

# EOF
