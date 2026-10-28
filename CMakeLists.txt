#
# CMakeLists.txt
#

cmake_minimum_required(VERSION 4.2)

# No Gaia includes here, we want to be able to use this as a standalone project

include(${CMAKE_CURRENT_LIST_DIR}/cmake/IcuHelpers.cmake)

# Project ---------------------------------------------------------------------------------------------------

# Is this the master project?
if(NOT DEFINED ICU_CMAKE_MASTER_PROJECT)
  set(ICU_CMAKE_MASTER_PROJECT OFF)
  if(NOT DEFINED PROJECT_NAME)
    set(ICU_CMAKE_MASTER_PROJECT ON)
  endif()
endif()

project(icu-cmake VERSION 0.1.0 LANGUAGES C CXX)

# Prerequisites ---------------------------------------------------------------------------------------------

if(WIN32)
  if("$ENV{DevEnvDir}" STREQUAL "")
    IcuFatalError("Developer Command Prompt for Microsoft Visual Studio is required")
  endif()
  # Git SDK for Windows is not required, we can work with a native Windows Python, too
endif()

find_package(Python3 3.8 REQUIRED COMPONENTS Interpreter)
IcuDetectPython()
find_package(Threads REQUIRED)

# General settings ------------------------------------------------------------------------------------------

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Set compiler options -------------------------------------------------------------------------------------

set(COMPILE_FLAGS)
if(LINUX)
  # Linux
  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    # Linux, Clang
    set(COMPILE_FLAGS -Wno-bidi-chars)
  endif()
elseif(WIN32)
  # Windows
  if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    # Windows, Clang
    set(COMPILE_FLAGS
      -Wno-format
      -Wno-macro-redefined
      -Wno-parentheses
      -Wno-unused-function
      -Wno-unused-variable
    )
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    # Windows, MSVC
    set(COMPILE_FLAGS /wd4005 /wd4477 /wd4805)
  endif()
endif()

# Configuration ---------------------------------------------------------------------------------------------

IcuAddVar(BUILD_SHARED_LIBS             BOOL     OFF                         "Build shared libraries")
IcuAddVar(BUILD_TESTING                 BOOL     ON                          "Enable testing and build tests")
IcuAddVar(ICU_CMAKE_BUILD_TEST          BOOL     ${ICU_CMAKE_MASTER_PROJECT} "Enable testing and build the smoke test")
IcuAddVar(ICU_CMAKE_DATA_FILTER_FILE    FILEPATH ""                          "ICU data filter file (JSON) to reduce the data size")
IcuAddVar(ICU_CMAKE_ICU_DATA_SOURCE_DIR PATH     ""                          "Local ICU data sources (`icu4c/source/data`) to use instead of downloading them")
IcuAddVar(ICU_CMAKE_ICU_SOURCE_DIR      PATH     ""                          "Local ICU checkout to use instead of downloading the sources")
IcuAddVar(ICU_CMAKE_ICU_VERSION         STRING   79.1                        "ICU version to download (release-VERSION tag, 78.1 or later)")

# ICU looks up its common data as `icudt<major><letter>`, where the letter is `U_ICUDATA_TYPE_LETTER`:
# `l` on a little-endian ASCII target and `b` on a big-endian ASCII target. The data tools write bytes in
# the endianness they were compiled for, which is this target, so the letter has to follow it.
if(CMAKE_CXX_BYTE_ORDER STREQUAL "LITTLE_ENDIAN")
  set(ICU_DATA_ENDIAN_LETTER l)
elseif(CMAKE_CXX_BYTE_ORDER STREQUAL "BIG_ENDIAN")
  set(ICU_DATA_ENDIAN_LETTER b)
else()
  IcuFatalError("Cannot tell the target endianness from CMAKE_CXX_BYTE_ORDER (`${CMAKE_CXX_BYTE_ORDER}`)")
endif()

set(ICU_RELEASE_URL https://github.com/unicode-org/icu/releases/download/release-${ICU_CMAKE_ICU_VERSION})

# IcuFetch(name url): Downloads and extracts an archive, setting `${name}_SOURCE_DIR`
function(IcuFetch name url)
  include(FetchContent)

  IcuStatus("Fetching ${url}")
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

# Obtain the ICU sources ------------------------------------------------------------------------------------

if(ICU_CMAKE_ICU_SOURCE_DIR STREQUAL "")
  IcuFetch(icu ${ICU_RELEASE_URL}/icu4c-${ICU_CMAKE_ICU_VERSION}-sources.tgz)
  set(ICU_SOURCE_DIR ${icu_SOURCE_DIR}/source)
else()
  # Accept a repository root, `icu4c`, or `icu4c/source`
  set(ICU_SOURCE_DIR)
  foreach(it IN ITEMS icu4c/source source .)
    if(EXISTS ${ICU_CMAKE_ICU_SOURCE_DIR}/${it}/common/unicode/uvernum.h)
      cmake_path(SET ICU_SOURCE_DIR NORMALIZE ${ICU_CMAKE_ICU_SOURCE_DIR}/${it})
      break()
    endif()
  endforeach()
  if(NOT ICU_SOURCE_DIR)
    IcuFatalError("No ICU sources found in ${ICU_CMAKE_ICU_SOURCE_DIR}")
  endif()
endif()
IcuStatus("ICU_SOURCE_DIR: ${ICU_SOURCE_DIR}")

# Obtain the ICU data sources -------------------------------------------------------------------------------
#
# Since ICU 68, the release source archives ship without the data text sources (only a prebuilt `.dat`). They
# are published separately as `icu4c-VERSION-data.zip`. A Git checkout contains them in `icu4c/source/data`.

if(NOT ICU_CMAKE_ICU_DATA_SOURCE_DIR STREQUAL "")
  set(ICU_DATA_SOURCE_DIR ${ICU_CMAKE_ICU_DATA_SOURCE_DIR})
elseif(EXISTS ${ICU_SOURCE_DIR}/data/locales/LOCALE_DEPS.json)
  set(ICU_DATA_SOURCE_DIR ${ICU_SOURCE_DIR}/data)
else()
  IcuFetch(icu-data ${ICU_RELEASE_URL}/icu4c-${ICU_CMAKE_ICU_VERSION}-data.zip)
  # The archive's single top-level directory `data/` is usually stripped during extraction
  if(EXISTS ${icu-data_SOURCE_DIR}/BUILDRULES.py)
    set(ICU_DATA_SOURCE_DIR ${icu-data_SOURCE_DIR})
  else()
    set(ICU_DATA_SOURCE_DIR ${icu-data_SOURCE_DIR}/data)
  endif()
endif()
if(NOT EXISTS ${ICU_DATA_SOURCE_DIR}/BUILDRULES.py OR NOT EXISTS ${ICU_DATA_SOURCE_DIR}/locales/LOCALE_DEPS.json)
  IcuFatalError("No ICU data sources found in ${ICU_DATA_SOURCE_DIR}")
endif()
IcuStatus("ICU_DATA_SOURCE_DIR: ${ICU_DATA_SOURCE_DIR}")

# Determine the ICU version ---------------------------------------------------------------------------------

IcuReadVersion(${ICU_SOURCE_DIR} ICU_VERSION ICU_VERSION_MAJOR)
set(ICU_DATA_NAME icudt${ICU_VERSION_MAJOR}${ICU_DATA_ENDIAN_LETTER}) # `l` or `b`; see the endianness check above
set(ICU_DATA_ENTRY_POINT icudt${ICU_VERSION_MAJOR})
IcuStatus("ICU_VERSION: ${ICU_VERSION}, data package: ${ICU_DATA_NAME}")

# Add subdirectories ----------------------------------------------------------------------------------------

add_subdirectory(src/main)
if(BUILD_TESTING AND ICU_CMAKE_BUILD_TEST)
  enable_testing()
  add_subdirectory(src/test)
endif()

# EOF
