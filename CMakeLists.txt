#
# CMakeLists.txt
#

cmake_minimum_required(VERSION 4.2)

# Project ---------------------------------------------------------------------------------------------------

# Is this the master project?
if(NOT DEFINED ICU_CMAKE_MASTER_PROJECT)
  set(ICU_CMAKE_MASTER_PROJECT OFF)
  if(NOT DEFINED PROJECT_NAME)
    set(ICU_CMAKE_MASTER_PROJECT ON)
  endif()
endif()

project(icu-cmake VERSION 0.1.0 LANGUAGES C CXX)

include($ENV{GAIA_DIR}/src/main/cmake/gaia.cmake)

include(cmake/IcuHelpers.cmake)

# Configuration ---------------------------------------------------------------------------------------------

AddVar(ICU_CMAKE_BUILD_TEST          BOOL     ${ICU_CMAKE_MASTER_PROJECT} "Enable testing and build tests")
AddVar(ICU_CMAKE_DATA_FILTER_FILE    FILEPATH ""                          "ICU data filter file (JSON) to reduce the data size")
AddVar(ICU_CMAKE_ICU_DATA_HASH       STRING   ""                          "Expected SHA-256 of the data archive (empty: skip check)")
AddVar(ICU_CMAKE_ICU_DATA_SOURCE_DIR PATH     ""                          "Local ICU data sources (`icu4c/source/data`) to use instead of downloading them")
AddVar(ICU_CMAKE_ICU_SOURCE_DIR      PATH     ""                          "Local ICU checkout to use instead of downloading the sources")
AddVar(ICU_CMAKE_ICU_SOURCE_HASH     STRING   ""                          "Expected SHA-256 of the sources archive (empty: skip check)")
AddVar(ICU_CMAKE_ICU_VERSION         STRING   79.1                        "ICU version to download (release-VERSION tag, 78.1 or later)")

if(BUILD_SHARED_LIBS)
  message(FATAL_ERROR "icu-cmake: Only static libraries are supported, set BUILD_SHARED_LIBS=OFF")
endif()
if(CMAKE_CXX_BYTE_ORDER STREQUAL "BIG_ENDIAN")
  message(FATAL_ERROR "icu-cmake: Big-endian targets are not supported")
endif()

# Known hashes of release archives
if(ICU_CMAKE_ICU_VERSION STREQUAL "79.1")
  if(ICU_CMAKE_ICU_SOURCE_HASH STREQUAL "")
    set(ICU_CMAKE_ICU_SOURCE_HASH 06fa63ecb521048f8082f12ad988f6b678d90cbd88aafce24cbc94902b191d99)
  endif()
  if(ICU_CMAKE_ICU_DATA_HASH STREQUAL "")
    set(ICU_CMAKE_ICU_DATA_HASH b3a430009bb5fab77b1a4b98fab85cc8f887e26d4e4166121724298ae14d7224)
  endif()
endif()

set(ICU_RELEASE_URL https://github.com/unicode-org/icu/releases/download/release-${ICU_CMAKE_ICU_VERSION})

# IcuFetch(name url hash): Downloads and extracts an archive, setting `${name}_SOURCE_DIR`
function(IcuFetch name url hash)
  include(FetchContent)

  set(hashArgs)
  if(NOT hash STREQUAL "")
    set(hashArgs URL_HASH SHA256=${hash})
  endif()

  message(STATUS "icu-cmake: Fetching ${url}")
  FetchContent_Declare(
    ${name}
    URL ${url}
    ${hashArgs}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    EXCLUDE_FROM_ALL
  )
  # The archives contain no `CMakeLists.txt` at their root, so this only downloads and extracts
  FetchContent_MakeAvailable(${name})

  set(${name}_SOURCE_DIR ${${name}_SOURCE_DIR} PARENT_SCOPE)
endfunction()

# Obtain the ICU sources ------------------------------------------------------------------------------------

if(ICU_CMAKE_ICU_SOURCE_DIR STREQUAL "")
  IcuFetch(icu ${ICU_RELEASE_URL}/icu4c-${ICU_CMAKE_ICU_VERSION}-sources.tgz "${ICU_CMAKE_ICU_SOURCE_HASH}")
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
    message(FATAL_ERROR "icu-cmake: No ICU sources found in ${ICU_CMAKE_ICU_SOURCE_DIR}")
  endif()
endif()
message(STATUS "icu-cmake: ICU_SOURCE_DIR: ${ICU_SOURCE_DIR}")

# Obtain the ICU data sources -------------------------------------------------------------------------------
#
# Since ICU 68, the release source archives ship without the data text sources (only a prebuilt `.dat`). They
# are published separately as `icu4c-VERSION-data.zip`. A Git checkout contains them in `icu4c/source/data`.

if(NOT ICU_CMAKE_ICU_DATA_SOURCE_DIR STREQUAL "")
  set(ICU_DATA_SOURCE_DIR ${ICU_CMAKE_ICU_DATA_SOURCE_DIR})
elseif(EXISTS ${ICU_SOURCE_DIR}/data/locales/LOCALE_DEPS.json)
  set(ICU_DATA_SOURCE_DIR ${ICU_SOURCE_DIR}/data)
else()
  IcuFetch(icu-data ${ICU_RELEASE_URL}/icu4c-${ICU_CMAKE_ICU_VERSION}-data.zip "${ICU_CMAKE_ICU_DATA_HASH}")
  # The archive's single top-level directory `data/` is usually stripped during extraction
  if(EXISTS ${icu-data_SOURCE_DIR}/BUILDRULES.py)
    set(ICU_DATA_SOURCE_DIR ${icu-data_SOURCE_DIR})
  else()
    set(ICU_DATA_SOURCE_DIR ${icu-data_SOURCE_DIR}/data)
  endif()
endif()
if(NOT EXISTS ${ICU_DATA_SOURCE_DIR}/BUILDRULES.py OR NOT EXISTS ${ICU_DATA_SOURCE_DIR}/locales/LOCALE_DEPS.json)
  message(FATAL_ERROR "icu-cmake: No ICU data sources found in ${ICU_DATA_SOURCE_DIR}")
endif()
message(STATUS "icu-cmake: ICU_DATA_SOURCE_DIR: ${ICU_DATA_SOURCE_DIR}")

# Determine the ICU version ---------------------------------------------------------------------------------

IcuReadVersion(${ICU_SOURCE_DIR} ICU_VERSION ICU_VERSION_MAJOR)
set(ICU_DATA_NAME icudt${ICU_VERSION_MAJOR}l) # Little-endian, ASCII-based data package
set(ICU_DATA_ENTRY_POINT icudt${ICU_VERSION_MAJOR})
message(STATUS "icu-cmake: ICU_VERSION: ${ICU_VERSION}, data package: ${ICU_DATA_NAME}")

# Dependencies ----------------------------------------------------------------------------------------------

find_package(Threads REQUIRED)

# Add subdirectories ----------------------------------------------------------------------------------------

add_subdirectory(src/main)
if(ICU_CMAKE_BUILD_TEST)
  enable_testing()
  add_subdirectory(src/test)
endif()

# EOF
