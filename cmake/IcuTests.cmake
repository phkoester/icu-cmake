#
# IcuTests.cmake
#
# Builds ICU's own test programs from `source/test` and registers them with CTest.
#
# The programs and their source lists come from each `Makefile.in`. Nothing under `source/test` is modified.
# A makefile is a test when its `check-local` (or `check`) recipe runs a program and Make is not told to
# ignore the result. `perf` does not run its benchmarks. `letest` is skipped when it needs the layout
# library. `hdrtst` and `depstest` have no such program.
#

include(${CMAKE_CURRENT_LIST_DIR}/IcuCreateDirectoryLink.cmake)

# Functions -------------------------------------------------------------------------------------------------

# IcuAddCtestfw(target [FOR_TOOLS])
#
# Static library from `tools/ctestfw/sources.txt`. `FOR_TOOLS` compiles it with `U_STATIC_IMPLEMENTATION`
# so `gentest` can link it into the data tools. The test programs use the copy that matches
# `BUILD_SHARED_LIBS`.
function(IcuAddCtestfw target)
  cmake_parse_arguments(PARSE_ARGV 1 ARG "FOR_TOOLS" "" "")

  IcuReadSources(${ICU_SOURCE_DIR}/tools/ctestfw sources)
  add_library(${target} STATIC ${sources})
  IcuApplyCommonSettings(${target})
  target_include_directories(${target}
    PUBLIC
      ${ICU_SOURCE_DIR}/tools/ctestfw
    PRIVATE
      ${ICU_SOURCE_DIR}/common
      ${ICU_SOURCE_DIR}/i18n
      ${ICU_SOURCE_DIR}/tools/toolutil
  )
  target_compile_definitions(${target} PRIVATE T_CTEST_IMPLEMENTATION)
  if(ARG_FOR_TOOLS OR NOT BUILD_SHARED_LIBS)
    target_compile_definitions(${target} PRIVATE U_STATIC_IMPLEMENTATION)
  endif()
endfunction()

# IcuTestSourceFromObject(dir object out)
#
# Maps `name.o` from a makefile to `dir/name.cpp` or `dir/name.c`.
function(IcuTestSourceFromObject dir object out)
  string(REGEX REPLACE "\\.o$" "" stem "${object}")
  if(EXISTS "${dir}/${stem}.cpp")
    set(${out} "${dir}/${stem}.cpp" PARENT_SCOPE)
  elseif(EXISTS "${dir}/${stem}.c")
    set(${out} "${dir}/${stem}.c" PARENT_SCOPE)
  else()
    set(${out} "" PARENT_SCOPE)
  endif()
endfunction()

# IcuAddOneIcuTest(target ...)
#
# One ICU test executable and its CTest entry.
function(IcuAddOneIcuTest target)
  cmake_parse_arguments(PARSE_ARGV 1 ARG "" "TEST_DIR" "SOURCES;LIBS;ARGS")

  # `collationperf` passes `char16_t *` to `CompareStringW` and `LCMapStringW`. MSVC converts that to
  # `wchar_t *`. Clang does not. The prefix header adds the missing overloads and `timeGetTime`, which
  # `WIN32_LEAN_AND_MEAN` leaves out of `windows.h`. The fetched source stays as it is.
  set(winLibs)
  foreach(source IN LISTS ARG_SOURCES)
    if(WIN32 AND source MATCHES "collationperf/collperf\\.cpp$")
      set(icuWin32Char16 "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/IcuWin32Char16.h")
      set_source_files_properties("${source}"
        PROPERTIES
          COMPILE_OPTIONS "/FI${icuWin32Char16}"
          OBJECT_DEPENDS "${icuWin32Char16}"
      )
      list(APPEND winLibs winmm)
    endif()
    # `std::insert_iterator` is not pulled in by the headers this fuzzer includes.
    if(source MATCHES "(^|/)locale_morph_fuzzer\\.cpp$")
      if(WIN32)
        set(stdIterator "/FIiterator")
      else()
        # Two list items: the Makefile generator does not expand `SHELL:` in source-file options
        set(stdIterator -include iterator)
      endif()
      set_source_files_properties("${source}" PROPERTIES COMPILE_OPTIONS "${stdIterator}")
    endif()
  endforeach()

  add_executable(${target} ${ARG_SOURCES})
  IcuApplyCommonSettings(${target})
  target_include_directories(${target}
    PRIVATE
      ${ARG_TEST_DIR}
      ${ICU_SOURCE_DIR}/common
      ${ICU_SOURCE_DIR}/i18n
      ${ICU_SOURCE_DIR}/io
      ${ICU_SOURCE_DIR}/tools/toolutil
      ${ICU_SOURCE_DIR}/tools/ctestfw
  )
  # The values are string literals: ICU concatenates them with the next string in the source.
  # Forward slashes and a trailing `/` keep that concatenation valid on Windows.
  target_compile_definitions(${target}
    PRIVATE
      "U_TOPSRCDIR=\"${icuTopSrc}\""
      "U_TOPBUILDDIR=\"${icuTopBuild}\""
      "ICUDATA_NAME=\"${ICU_DATA_NAME}\""
      "ICU_VERSION=\"${ICU_VERSION}\""
      "ICU_UNICODE_VERSION=\"${icuUnicodeVersion}\""
      "UNISTR_FROM_CHAR_EXPLICIT="
      "UNISTR_FROM_STRING_EXPLICIT="
  )
  target_link_libraries(${target}
    PRIVATE
      icu-ctestfw
      icu-cmake::io
      icu-cmake::tu
      ${ARG_LIBS}
      ${winLibs}
  )
  set_target_properties(${target} PROPERTIES LINKER_LANGUAGE CXX)
  add_dependencies(${target} icu-testdata)
  GaiaCopyRuntimeFiles(${target})

  add_test(NAME ${target} COMMAND ${target} ${ARG_ARGS})
  set_tests_properties(${target}
    PROPERTIES
      WORKING_DIRECTORY "${ARG_TEST_DIR}"
      TIMEOUT 3600
  )
endfunction()

# IcuAddTestsFromMakefile(makefile)
#
# Parses one `Makefile.in` and adds a CTest target for each program it runs.
function(IcuAddTestsFromMakefile makefile)
  file(READ "${makefile}" text)
  string(REPLACE "\r\n" "\n" text "${text}")
  string(REPLACE "\r" "\n" text "${text}")
  # CMake's regex has no `\t`. A tab has to be inserted into the character class.
  string(ASCII 9 tab)
  string(REGEX REPLACE "\\\\[${tab} ]*\n" " " text "${text}")
  # Newlines become list separators, so semicolons already in the file have to survive that
  string(REPLACE ";" "<SEMICOLON>" text "${text}")
  string(REPLACE "\n" ";" lines "${text}")

  set(want check)
  foreach(line IN LISTS lines)
    string(REPLACE "<SEMICOLON>" ";" line "${line}")
    if(line MATCHES "^check-local:")
      set(want check-local)
      break()
    endif()
  endforeach()

  set(inRecipe FALSE)
  set(runs FALSE)
  set(runRecipe "")
  foreach(line IN LISTS lines)
    string(REPLACE "<SEMICOLON>" ";" line "${line}")
    if(NOT inRecipe)
      if(line MATCHES "^${want}:")
        set(inRecipe TRUE)
      endif()
    elseif(line MATCHES "^[${tab}]")
      if(line MATCHES "\\$\\(INVOKE\\)|\\./\\$\\((TARGET|TESTTARGET)\\)")
        # A leading `-` tells Make to ignore a failing command. `compat` is written that way
        if(NOT line MATCHES "^[${tab}][ ${tab}]*-")
          set(runs TRUE)
          if(runRecipe STREQUAL "")
            set(runRecipe "${line}")
          endif()
        endif()
      endif()
    elseif(NOT line STREQUAL "")
      set(inRecipe FALSE)
    endif()
  endforeach()
  if(NOT runs)
    return()
  endif()

  set(mfNames)
  foreach(line IN LISTS lines)
    string(REPLACE "<SEMICOLON>" ";" line "${line}")
    if(line MATCHES "^[ ]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*(\\+?=)[ \t]*(.*)$")
      set(varName "${CMAKE_MATCH_1}")
      set(op "${CMAKE_MATCH_2}")
      set(value "${CMAKE_MATCH_3}")
      string(REGEX REPLACE "[ \t]+#.*$" "" value "${value}")
      string(STRIP "${value}" value)
      if(NOT DEFINED mf_${varName})
        list(APPEND mfNames "${varName}")
        set("mf_${varName}" "")
      endif()
      if(op STREQUAL "+=")
        set("mf_${varName}" "${mf_${varName}} ${value}")
      else()
        set("mf_${varName}" "${value}")
      endif()
    endif()
  endforeach()
  if(NOT DEFINED mf_EXEEXT)
    list(APPEND mfNames EXEEXT)
    set(mf_EXEEXT "")
  endif()
  foreach(pass RANGE 1 3)
    foreach(varName IN LISTS mfNames)
      set(value "${mf_${varName}}")
      foreach(other IN LISTS mfNames)
        if(NOT value MATCHES "\\$\\(")
          break()
        endif()
        string(REGEX REPLACE "\\$\\(${other}\\)" "${mf_${other}}" value "${value}")
      endforeach()
      set("mf_${varName}" "${value}")
    endforeach()
  endforeach()

  if(DEFINED mf_LIBS AND mf_LIBS MATCHES "LIBICULX|layoutex")
    if(NOT TARGET icu-layoutex)
      cmake_path(GET makefile PARENT_PATH testDir)
      file(RELATIVE_PATH testRel "${ICU_SOURCE_DIR}/test" "${testDir}")
      GaiaStatus("Skipping `${testRel}`: needs the layout library")
      return()
    endif()
  endif()

  set(fuzzer FALSE)
  set(programs)
  if(DEFINED mf_FUZZER_TARGETS AND NOT mf_FUZZER_TARGETS MATCHES "^[ \t]*$")
    set(fuzzer TRUE)
    string(REGEX MATCHALL "[A-Za-z_][A-Za-z0-9_+-]*" programs "${mf_FUZZER_TARGETS}")
  else()
    set(program "${mf_TESTTARGET}")
    if(program STREQUAL "")
      set(program "${mf_TARGET}")
    endif()
    string(STRIP "${program}" program)
    if(NOT program STREQUAL "")
      list(APPEND programs "${program}")
    endif()
  endif()
  if(NOT programs)
    GaiaFatalError("No test program in `${makefile}`")
  endif()

  cmake_path(GET makefile PARENT_PATH testDir)
  set(objectNames)
  if(DEFINED mf_OBJECTS)
    string(REGEX MATCHALL "[A-Za-z0-9_+.-]+\\.o" objectNames "${mf_OBJECTS}")
  endif()

  set(extraLibs ${CMAKE_DL_LIBS})
  if(LINUX AND DEFINED mf_LIBS AND mf_LIBS MATCHES "LIB_M")
    list(APPEND extraLibs m)
  endif()

  # Fuzzer binaries share every object that is not itself a `*_fuzzer` program
  set(commonSources)
  if(fuzzer)
    foreach(object IN LISTS objectNames)
      set(isProgram FALSE)
      foreach(program IN LISTS programs)
        if(object STREQUAL "${program}.o")
          set(isProgram TRUE)
        endif()
      endforeach()
      if(isProgram)
        continue()
      endif()
      IcuTestSourceFromObject("${testDir}" "${object}" source)
      if(source STREQUAL "")
        GaiaFatalError("No source for `${object}` in `${makefile}`")
      endif()
      list(APPEND commonSources "${source}")
    endforeach()
  endif()

  set(added)
  foreach(program IN LISTS programs)
    if(NOT program MATCHES "^[A-Za-z_][A-Za-z0-9_+-]*$")
      GaiaFatalError("Invalid test name `${program}` in `${makefile}`")
    endif()
    set(target "icu-${program}")
    if(TARGET ${target})
      GaiaFatalError("Duplicate ICU test `${target}` from `${makefile}`")
    endif()

    set(sources)
    if(fuzzer)
      set(sources ${commonSources})
      IcuTestSourceFromObject("${testDir}" "${program}.o" ownSource)
      if(ownSource STREQUAL "")
        GaiaFatalError("No source for `${program}.o` in `${makefile}`")
      endif()
      list(APPEND sources "${ownSource}")
    else()
      foreach(object IN LISTS objectNames)
        IcuTestSourceFromObject("${testDir}" "${object}" source)
        if(source STREQUAL "")
          GaiaFatalError("No source for `${object}` in `${makefile}`")
        endif()
        list(APPEND sources "${source}")
      endforeach()
    endif()
    if(NOT sources)
      GaiaFatalError("No sources for `${program}` in `${makefile}`")
    endif()
    list(REMOVE_DUPLICATES sources)

    # Arguments are whatever the makefile passes after `./$(TARGET)`. Empty option variables such as
    # `$(INTLTEST_OPTS)` are dropped. `$(top_srcdir)` is this ICU source tree
    set(testArgs)
    if(fuzzer)
      set(testArgs "${ICU_FUZZER_INPUT}" -q)
    else()
      set(rawArgs "")
      if(runRecipe MATCHES "\\./\\$\\(TESTTARGET\\)(.*)$")
        set(rawArgs "${CMAKE_MATCH_1}")
      elseif(runRecipe MATCHES "\\./\\$\\(TARGET\\)(.*)$")
        set(rawArgs "${CMAKE_MATCH_1}")
      endif()
      file(TO_CMAKE_PATH "${ICU_SOURCE_DIR}" icuSrcPath)
      file(TO_CMAKE_PATH "${ICU_TEST_ROOT}" icuBuildPath)
      string(REPLACE "\$(top_srcdir)" "${icuSrcPath}" rawArgs "${rawArgs}")
      string(REPLACE "\$(top_builddir)" "${icuBuildPath}" rawArgs "${rawArgs}")
      string(REGEX REPLACE "\\$\\([A-Za-z_][A-Za-z0-9_]*\\)" "" rawArgs "${rawArgs}")
      string(STRIP "${rawArgs}" rawArgs)
      if(NOT rawArgs STREQUAL "")
        separate_arguments(testArgs NATIVE_COMMAND "${rawArgs}")
      endif()
    endif()
    IcuAddOneIcuTest(${target}
      TEST_DIR "${testDir}"
      SOURCES ${sources}
      LIBS ${extraLibs}
      ARGS ${testArgs}
    )
    list(APPEND added "${target}")
  endforeach()

  set(icuDiscoveredTests ${icuDiscoveredTests} ${added} PARENT_SCOPE)
endfunction()

# Unicode version -------------------------------------------------------------------------------------------

set(icuUnicodeHeader ${ICU_SOURCE_DIR}/common/unicode/uchar.h)
file(STRINGS "${icuUnicodeHeader}" icuUnicodeLine REGEX "^#define[ \t]+U_UNICODE_VERSION[ \t]+\"")
string(REGEX REPLACE
  "^#define[ \t]+U_UNICODE_VERSION[ \t]+\"([^\"]+)\".*" "\\1" icuUnicodeVersion "${icuUnicodeLine}")
if(NOT icuUnicodeVersion MATCHES "^[0-9.]+$")
  GaiaFatalError("Cannot parse `U_UNICODE_VERSION` from `${icuUnicodeHeader}`")
endif()

file(TO_CMAKE_PATH "${ICU_SOURCE_DIR}" icuTopSrc)
set(icuTopSrc "${icuTopSrc}/")
set(ICU_TEST_ROOT ${CMAKE_BINARY_DIR}/icu-test-root)
file(TO_CMAKE_PATH "${ICU_TEST_ROOT}" icuTopBuild)
set(icuTopBuild "${icuTopBuild}/")
file(TO_CMAKE_PATH "${ICU_TEST_ROOT}/fuzzer-input.txt" ICU_FUZZER_INPUT)
file(MAKE_DIRECTORY "${ICU_TEST_ROOT}")
file(WRITE "${ICU_FUZZER_INPUT}" "abc123\n")

# ctestfw ---------------------------------------------------------------------------------------------------

IcuAddCtestfw(icu-ctestfw)
if(WIN32 AND BUILD_SHARED_LIBS)
  # The data tools are static. A ctestfw built against the DLLs cannot be linked into `gentest`.
  IcuAddCtestfw(icu-ctestfw-tool FOR_TOOLS)
  set(gentestCtestfw icu-ctestfw-tool)
else()
  set(gentestCtestfw icu-ctestfw)
endif()

# Tools used only to build the test data ...................................................................

IcuAddTool(gentest)
IcuAddTool(gennorm2)
target_link_libraries(icu-gentest PRIVATE ${gentestCtestfw})
set_target_properties(icu-gentest PROPERTIES LINKER_LANGUAGE CXX)
add_dependencies(icu-gentest ${gentestCtestfw})

# Unidata ---------------------------------------------------------------------------------------------------
#
# Release source archives omit `data/unidata`. `gensprep` and the tests both look for it at
# `<ICU source>/data/unidata`, which is outside `source/test`.
#
# -----------------------------------------------------------------------------------------------------------

set(icuUnidataFile ${ICU_SOURCE_DIR}/data/unidata/UnicodeData.txt)
if(NOT EXISTS "${icuUnidataFile}")
  if(NOT EXISTS "${ICU_DATA_SOURCE_DIR}/unidata/UnicodeData.txt")
    GaiaFatalError("No `UnicodeData.txt` in `${ICU_SOURCE_DIR}/data/unidata` or `${ICU_DATA_SOURCE_DIR}/unidata`")
  endif()
  IcuCreateDirectoryLink("${ICU_DATA_SOURCE_DIR}/unidata" "${ICU_SOURCE_DIR}/data/unidata")
  GaiaStatus("Linked `${ICU_SOURCE_DIR}/data/unidata` to the fetched Unicode data")
endif()

# Test data -------------------------------------------------------------------------------------------------

set(icuTestDataOut ${ICU_TEST_ROOT}/test/testdata/out)
# Temporary files are not packaged. `nam.typ` and the old `zoneinfo64.res` are opened as individual files
# under the path `loadTestData()` returns, which is this directory
set(icuTestDataTmp ${icuTestDataOut}/testdata)
set(icuTestDataList ${icuTestDataTmp}/testdata.lst)
set(icuTestDataDat ${icuTestDataOut}/testdata.dat)
# pkgdata's own scratch directory. It is not the unpackaged-file directory: those files must remain beside
# testdata.dat after packaging
set(icuTestPkgTmp ${ICU_TEST_ROOT}/test/testdata/tmp)

GaiaPythonPath("${ICU_SOURCE_DIR}/test/testdata" pyTestSrc)
GaiaPythonPath("${icuTestDataOut}" pyTestOut)
GaiaPythonPath("${icuTestDataTmp}" pyTestTmp)

# `loadTestData()` opens `<U_TOPBUILDDIR>/test/testdata/out/testdata`. `genrb -i` reads
# `<out>/build/<data package>/coll/ucadata.icu`, so the link is the parent of the loose package and not the
# package directory itself. `ctest_dataOutDir()` reads `<U_TOPBUILDDIR>/data/out/build/`
add_custom_command(
  OUTPUT  ${icuTestDataList}
  COMMAND ${CMAKE_COMMAND} -E rm -rf "${icuTestDataOut}"
  COMMAND ${CMAKE_COMMAND} -E make_directory "${icuTestDataOut}" "${icuTestDataTmp}" "${ICU_TEST_ROOT}/data/out"
  COMMAND ${CMAKE_COMMAND} "-Doriginal=${ICU_DATA_DIR}/out" "-DlinkName=${icuTestDataOut}/build"
    -P ${ICU_CMAKE_DIR}/cmake/IcuCreateDirectoryLink.cmake
  COMMAND ${CMAKE_COMMAND} "-Doriginal=${ICU_DATA_DIR}/out" "-DlinkName=${ICU_TEST_ROOT}/data/out/build"
    -P ${ICU_CMAKE_DIR}/cmake/IcuCreateDirectoryLink.cmake
  COMMAND ${CMAKE_COMMAND} -E env PYTHONDONTWRITEBYTECODE=1
    ${Python3_EXECUTABLE} -m icutools.databuilder
      --src_dir "${pyTestSrc}"
      --out_dir "${pyTestOut}"
      --tmp_dir "${pyTestTmp}"
      ${ICU_DATABUILDER_ARGS}
  # The data list is generated in `src/main`. Naming `icudata` as well makes sure it is built first.
  DEPENDS icu-gentest icu-gennorm2 icudata ${ICU_DATA_LIST}
    ${ICU_SOURCE_DIR}/test/testdata/BUILDRULES.py
    ${ICU_CMAKE_DIR}/cmake/IcuCreateDirectoryLink.cmake
  WORKING_DIRECTORY ${ICU_SOURCE_DIR}/python
  COMMENT "icu-cmake: Building the ICU test data"
  VERBATIM
)

add_custom_command(
  OUTPUT  ${icuTestDataDat}
  COMMAND ${CMAKE_COMMAND} -E make_directory "${icuTestPkgTmp}"
  COMMAND icu-pkgdata -m common -q -c -p testdata -s "${icuTestDataOut}" -T "${icuTestPkgTmp}"
            -d "${icuTestDataOut}" "${icuTestDataList}"
  DEPENDS icu-pkgdata ${icuTestDataList}
  COMMENT "icu-cmake: Packaging testdata.dat"
  VERBATIM
)

add_custom_target(icu-testdata DEPENDS ${icuTestDataDat})

# Discover --------------------------------------------------------------------------------------------------

file(GLOB_RECURSE icuTestMakefiles CONFIGURE_DEPENDS "${ICU_SOURCE_DIR}/test/*.in")
list(FILTER icuTestMakefiles INCLUDE REGEX "/Makefile\\.in$")
list(SORT icuTestMakefiles)

set(icuDiscoveredTests)
foreach(makefile IN LISTS icuTestMakefiles)
  IcuAddTestsFromMakefile("${makefile}")
endforeach()
if(NOT icuDiscoveredTests)
  GaiaFatalError("No ICU tests were discovered under `${ICU_SOURCE_DIR}/test`")
endif()
list(SORT icuDiscoveredTests)
string(JOIN ", " icuDiscoveredText ${icuDiscoveredTests})
GaiaStatus("Discovered ICU tests: ${icuDiscoveredText}")

# EOF
