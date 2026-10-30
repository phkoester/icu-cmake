#
# CMakeLists.txt
#

cmake_minimum_required(VERSION 4.2)

include(${CMAKE_CURRENT_LIST_DIR}/cmake/IcuFunctions.cmake)

include(FetchContent)

# Project ---------------------------------------------------------------------------------------------------

# Is this the master project?
if(NOT DEFINED ICU_CMAKE_MASTER_PROJECT)
  set(ICU_CMAKE_MASTER_PROJECT OFF)
  if(NOT DEFINED PROJECT_NAME)
    set(ICU_CMAKE_MASTER_PROJECT ON)
  endif()
endif()

project(icu-cmake VERSION 0.1.1)

# Versions --------------------------------------------------------------------------------------------------

set(ICU_CMAKE_GAIA_VERSION 1.2.2)
set(ICU_CMAKE_GTEST_VERSION 1.17.0)

# Gaia ------------------------------------------------------------------------------------------------------

if(DEFINED ENV{GAIA_DIR})
  FetchContent_Declare(
    gaia
    SOURCE_DIR "$ENV{GAIA_DIR}"
  )
else()
  FetchContent_Declare(
    gaia
    GIT_REPOSITORY https://github.com/phkoester/gaia.git
    GIT_TAG        v${ICU_CMAKE_GAIA_VERSION}
    GIT_PROGRESS   TRUE
    SYSTEM
    EXCLUDE_FROM_ALL
  )
endif()
FetchContent_MakeAvailable(gaia)

# Prerequisites ---------------------------------------------------------------------------------------------

find_package(Threads REQUIRED)

# General settings ------------------------------------------------------------------------------------------

set(CMAKE_CXX_EXTENSIONS ON)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)
set(FETCHCONTENT_QUIET FALSE)

# Configuration ---------------------------------------------------------------------------------------------

if(GAIA_OS_WINDOWS)
  set(defaultDataFormat object)
else()
  set(defaultDataFormat asm)
endif()

GaiaAddVar(ICU_CMAKE_BUILD_ICU_TEST BOOL   ${ICU_CMAKE_MASTER_PROJECT} "Build the ICU tests")
GaiaAddVar(ICU_CMAKE_BUILD_TEST     BOOL   ${ICU_CMAKE_MASTER_PROJECT} "Build the smoke test")
GaiaAddVar(ICU_CMAKE_DATA_FORMAT    STRING ${defaultDataFormat}        "How `genccode` emits the data: `asm`, `object`, or `c`")
GaiaAddVar(ICU_CMAKE_DATA_VERBOSE   BOOL   OFF                         "Print every command of the ICU data build")
GaiaAddVar(ICU_CMAKE_ICU_VERSION    STRING 79.1                        "ICU version to download (`release-VERSION` tag; 78.1 or later use this naming scheme)")

# Set compiler and linker options ---------------------------------------------------------------------------

set(COMPILE_DEFS)
set(COMPILE_FEATURES)
set(COMPILE_FLAGS)
set(LINK_FLAGS)

if(GAIA_OS_LINUX)
  # Linux
  set(COMPILE_FLAGS -Wall -Werror -Wextra
    -Wno-unused-parameter
    -Wno-unused-variable
  )
  if(GAIA_CXX_COMPILER_GNU)
    list(APPEND COMPILE_FLAGS -Wno-bidi-chars)
  endif()
elseif(GAIA_OS_WINDOWS)
  if(GAIA_CXX_COMPILER_LLVM)
    # Windows, LLVM
    set(COMPILE_FLAGS -Werror -Wextra
      -Wno-deprecated-declarations
      -Wno-format
      -Wno-macro-redefined
      -Wno-parentheses
      -Wno-sign-compare
      -Wno-unused-but-set-variable
      -Wno-unused-function
      -Wno-unused-parameter
      -Wno-unused-variable
    )
  elseif(GAIA_CXX_COMPILER_MSVC)
    # Windows, MSVC
    set(COMPILE_FLAGS /bigobj /wd4005 /wd4068 /wd4312 /wd4477 /wd4805 /Zc:preprocessor)
  endif()
endif()

# Dependencies ----------------------------------------------------------------------------------------------

# GTest .....................................................................................................

if(BUILD_TESTING AND ICU_CMAKE_BUILD_TEST)
  FetchContent_Declare(
    GTest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v${ICU_CMAKE_GTEST_VERSION}
    GIT_PROGRESS   TRUE
    SYSTEM
    EXCLUDE_FROM_ALL
  )

  block()
    set(BUILD_SHARED_LIBS OFF)
    if(GAIA_OS_WINDOWS)
      # For Windows: Prevent overriding the parent project's compiler/linker settings
      set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
    endif()
    FetchContent_MakeAvailable(GTest)
    if(GAIA_CXX_COMPILER_LLVM)
      target_compile_options(gtest PRIVATE -Wno-character-conversion)
      target_compile_options(gmock PRIVATE -Wno-character-conversion)
    endif()
  endblock()
endif()

# Fetch -----------------------------------------------------------------------------------------------------

set(ICU_RELEASE_URL https://github.com/unicode-org/icu/releases/download/release-${ICU_CMAKE_ICU_VERSION})

# Fetch the ICU sources .....................................................................................

IcuFetch(icu ${ICU_RELEASE_URL}/icu4c-${ICU_CMAKE_ICU_VERSION}-sources.tgz)
set(ICU_SOURCE_DIR ${icu_SOURCE_DIR}/source)
GaiaStatus("ICU_SOURCE_DIR: ${ICU_SOURCE_DIR}")

# Fetch the ICU data sources ................................................................................
#
# Since ICU 68, the release source archives ship without the data text sources (only a prebuilt `.dat`). They
# are published separately as `icu4c-VERSION-data.zip`. A Git checkout contains them in `icu4c/source/data`.
#
# ...........................................................................................................

IcuFetch(icu-data ${ICU_RELEASE_URL}/icu4c-${ICU_CMAKE_ICU_VERSION}-data.zip)
# The archive's single top-level directory `data/` is usually stripped during extraction
if(EXISTS ${icu-data_SOURCE_DIR}/BUILDRULES.py)
  set(ICU_DATA_SOURCE_DIR ${icu-data_SOURCE_DIR})
else()
  set(ICU_DATA_SOURCE_DIR ${icu-data_SOURCE_DIR}/data)
endif()
if(NOT EXISTS ${ICU_DATA_SOURCE_DIR}/BUILDRULES.py OR NOT EXISTS ${ICU_DATA_SOURCE_DIR}/locales/LOCALE_DEPS.json)
  GaiaFatalError("No ICU data sources found in ${ICU_DATA_SOURCE_DIR}")
endif()
GaiaStatus("ICU_DATA_SOURCE_DIR: ${ICU_DATA_SOURCE_DIR}")

# Determine the ICU version and data-package name -----------------------------------------------------------

# ICU looks up its common data as `icudt<major><letter>`, where the letter is `U_ICUDATA_TYPE_LETTER`: `l` on
# a little-endian ASCII target and `b` on a big-endian ASCII target. The data tools write bytes in the
# endianness they were compiled for, which is this target, so the letter has to follow it
if(CMAKE_CXX_BYTE_ORDER STREQUAL "LITTLE_ENDIAN")
  set(ICU_DATA_ENDIAN_LETTER l)
elseif(CMAKE_CXX_BYTE_ORDER STREQUAL "BIG_ENDIAN")
  set(ICU_DATA_ENDIAN_LETTER b)
else()
  GaiaFatalError("Cannot tell the target endianness from `CMAKE_CXX_BYTE_ORDER` (`${CMAKE_CXX_BYTE_ORDER}`)")
endif()

IcuReadVersion(${ICU_SOURCE_DIR} ICU_VERSION ICU_VERSION_MAJOR)
set(ICU_DATA_NAME icudt${ICU_VERSION_MAJOR}${ICU_DATA_ENDIAN_LETTER}) # `l` or `b`; see the endianness check above
set(ICU_DATA_ENTRY_POINT icudt${ICU_VERSION_MAJOR})
GaiaStatus("ICU_VERSION: ${ICU_VERSION}, data package: ${ICU_DATA_NAME}")

# Add subdirectories ----------------------------------------------------------------------------------------

set(ICU_CMAKE_DIR ${CMAKE_CURRENT_SOURCE_DIR})

add_subdirectory(src/main)
if(BUILD_TESTING AND (ICU_CMAKE_BUILD_TEST OR ICU_CMAKE_BUILD_ICU_TEST))
  enable_testing()
  add_subdirectory(src/test)
endif()

# EOF
