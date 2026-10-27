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
# 4. The static libraries, assembled from the object libraries and the generated data
#

include(GNUInstallDirs)

set(ICU_DATA_DIR      ${CMAKE_CURRENT_BINARY_DIR}/data)
set(ICU_GENERATED_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated)
set(ICU_TOOL_DIR      ${CMAKE_CURRENT_BINARY_DIR}/tools)

# Where `icutools.databuilder` expects the tool executables (see `IcuAddTool`):
#
# - `windows-exec`: `TOOL_DIR/name/CONFIG/name.exe`, with `--tool_dir TOOL_DIR --tool_cfg CONFIG`
# - `unix-exec`:    `TOOL_DIR/name`, with `--tool_dir TOOL_DIR`; one `TOOL_DIR` per configuration with a
#                   multi-config generator
get_property(isMultiConfig GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(ICU_DATABUILDER_MODE STREQUAL "unix-exec" AND isMultiConfig)
  set(toolBinDirSuffix /$<CONFIG>)
else()
  set(toolBinDirSuffix)
endif()
set(ICU_TOOL_BIN_DIR ${ICU_TOOL_DIR}${toolBinDirSuffix})

# System libraries ..........................................................................................

set(ICU_SYSTEM_LIBS Threads::Threads)
if(GAIA_OS_LINUX)
  list(APPEND ICU_SYSTEM_LIBS ${CMAKE_DL_LIBS})
elseif(GAIA_OS_WINDOWS)
  list(APPEND ICU_SYSTEM_LIBS advapi32)
endif()

# Data format ...............................................................................................
#
# - `asm`:    `genccode -a gcc` writes a `.S` file (Linux)
# - `object`: `genccode -o` writes a `.obj` file directly (Windows)
# - `c`:      `genccode` writes a `.c` file with a byte array (any platform; slow to compile)

if(GAIA_OS_WINDOWS)
  set(defaultDataFormat object)
else()
  set(defaultDataFormat asm)
endif()
AddVar(ICU_CMAKE_DATA_FORMAT  STRING ${defaultDataFormat} "Format of the generated data: `asm`, `object`, or `c`")
AddVar(ICU_CMAKE_DATA_VERBOSE BOOL   OFF                  "Print every command of the ICU data build")

if(NOT ICU_CMAKE_DATA_FORMAT MATCHES "^(asm|object|c)$")
  message(FATAL_ERROR "icu-cmake: ICU_CMAKE_DATA_FORMAT: Invalid value `${ICU_CMAKE_DATA_FORMAT}`")
endif()
if(ICU_CMAKE_DATA_FORMAT STREQUAL "asm" AND GAIA_OS_WINDOWS)
  message(FATAL_ERROR "icu-cmake: ICU_CMAKE_DATA_FORMAT=asm is not supported on Windows")
endif()
if(ICU_CMAKE_DATA_FORMAT STREQUAL "object" AND NOT GAIA_OS_WINDOWS)
  message(FATAL_ERROR "icu-cmake: ICU_CMAKE_DATA_FORMAT=object is only supported on Windows")
endif()
if(ICU_CMAKE_DATA_FORMAT STREQUAL "asm")
  enable_language(ASM)
endif()

# Object libraries ------------------------------------------------------------------------------------------

IcuAddObjectLibrary(icuuc-obj ${ICU_SOURCE_DIR}/common)
target_compile_definitions(icuuc-obj PRIVATE U_COMMON_IMPLEMENTATION)
if(GAIA_OS_LINUX)
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

# Stub data -------------------------------------------------------------------------------------------------
#
# The build tools link against this empty data package, which lets them run before the real data exists.

IcuReadSources(${ICU_SOURCE_DIR}/stubdata stubSources)
add_library(icudata-stub STATIC ${stubSources})
IcuApplyCommonSettings(icudata-stub)
target_compile_definitions(icudata-stub PRIVATE STUBDATA_BUILD)
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

# All paths passed to the data builder go through `IcuPythonPath` (POSIX form for an MSYS2 Python)
IcuPythonPath(${ICU_DATA_SOURCE_DIR} pySrcDir)
IcuPythonPath(${dataOutDir}          pyOutDir)
IcuPythonPath(${dataTmpDir}          pyTmpDir)
IcuPythonPath(${ICU_TOOL_DIR}        pyToolDir)

set(databuilderArgs --mode ${ICU_DATABUILDER_MODE} --tool_dir ${pyToolDir}${toolBinDirSuffix})
if(ICU_DATABUILDER_MODE STREQUAL "windows-exec")
  list(APPEND databuilderArgs --tool_cfg $<CONFIG>)
endif()
set(databuilderDeps)
if(NOT ICU_CMAKE_DATA_FILTER_FILE STREQUAL "")
  IcuPythonPath(${ICU_CMAKE_DATA_FILTER_FILE} pyFilterFile)
  list(APPEND databuilderArgs --filter_file ${pyFilterFile})
  list(APPEND databuilderDeps ${ICU_CMAKE_DATA_FILTER_FILE})
endif()
if(ICU_CMAKE_DATA_VERBOSE)
  list(APPEND databuilderArgs --verbose)
endif()

# `python -m` puts the working directory first on `sys.path`, which is how `icutools` is found. (Setting
# `PYTHONPATH` instead would break with an MSYS2 Python, which splits `C:/...` at the colon.)
add_custom_command(
  OUTPUT  ${dataList}
  COMMAND ${CMAKE_COMMAND} -E rm -rf ${dataOutDir} ${dataTmpDir}
  COMMAND ${CMAKE_COMMAND} -E make_directory ${dataOutDir} ${dataTmpDir}
  COMMAND ${CMAKE_COMMAND} -E env PYTHONDONTWRITEBYTECODE=1
            ${Python3_EXECUTABLE} -m icutools.databuilder
              --src_dir ${pySrcDir}
              --out_dir ${pyOutDir}
              --tmp_dir ${pyTmpDir}
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
  list(APPEND genccodeArgs -o -c ${cpuArch} --skip-dll-export)
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

# `icudata` .................................................................................................

add_library(icudata STATIC ${dataFile})
if(ICU_CMAKE_DATA_FORMAT STREQUAL "c")
  IcuApplyCommonSettings(icudata)
  target_include_directories(icudata PRIVATE ${ICU_SOURCE_DIR}/common)
endif()
set_target_properties(icudata
  PROPERTIES
    EXPORT_NAME     data
    LINKER_LANGUAGE C
    OUTPUT_NAME     icudata
)
add_library(icu-cmake::data ALIAS icudata)

# `icuuc` ...................................................................................................

add_library(icuuc STATIC $<TARGET_OBJECTS:icuuc-obj>)
target_compile_definitions(icuuc INTERFACE U_STATIC_IMPLEMENTATION)
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

add_library(icui18n STATIC $<TARGET_OBJECTS:icui18n-obj>)
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

add_library(icuio STATIC $<TARGET_OBJECTS:icuio-obj>)
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

add_library(icutu STATIC $<TARGET_OBJECTS:icutu-obj>)
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

# Install ---------------------------------------------------------------------------------------------------

if(ICU_CMAKE_INSTALL)
  include(CMakePackageConfigHelpers)

  set(configDir ${CMAKE_INSTALL_LIBDIR}/cmake/ICU)

  install(
    TARGETS icudata icuuc icui18n icuio icutu
    EXPORT  ICUTargets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  )
  install(
    DIRECTORY
      ${ICU_SOURCE_DIR}/common/unicode
      ${ICU_SOURCE_DIR}/i18n/unicode
      ${ICU_SOURCE_DIR}/io/unicode
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    FILES_MATCHING PATTERN "*.h"
  )
  install(
    DIRECTORY   ${ICU_SOURCE_DIR}/tools/toolutil/
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/icu/toolutil
    FILES_MATCHING PATTERN "*.h"
  )
  install(
    FILES       ${datFile}
    DESTINATION ${CMAKE_INSTALL_DATADIR}/icu/${ICU_VERSION}
  )
  install(
    EXPORT      ICUTargets
    NAMESPACE   icu-cmake::
    DESTINATION ${configDir}
  )

  configure_package_config_file(
    ${PROJECT_SOURCE_DIR}/cmake/ICUConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/ICUConfig.cmake
    INSTALL_DESTINATION ${configDir}
    PATH_VARS CMAKE_INSTALL_INCLUDEDIR CMAKE_INSTALL_DATADIR
  )
  write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/ICUConfigVersion.cmake
    VERSION       ${ICU_VERSION}
    COMPATIBILITY SameMajorVersion
  )
  install(
    FILES
      ${CMAKE_CURRENT_BINARY_DIR}/ICUConfig.cmake
      ${CMAKE_CURRENT_BINARY_DIR}/ICUConfigVersion.cmake
    DESTINATION ${configDir}
  )
endif()

# EOF
