#
# CMakeLists.txt
#

if(ICU_CMAKE_BUILD_TEST)
  IcuAddExecutable(test-icu-cmake test-icu-cmake.cc)
  target_link_libraries(test-icu-cmake PRIVATE icu-cmake::io icu-cmake::i18n icu-cmake::uc)
  if(WIN32 AND BUILD_SHARED_LIBS)
    # The DLLs are built in `src/main`; Windows looks for them next to the executable
    add_custom_command(
      TARGET  test-icu-cmake POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_newer $<TARGET_RUNTIME_DLLS:test-icu-cmake> $<TARGET_FILE_DIR:test-icu-cmake>
      COMMAND_EXPAND_LISTS
    )
  endif()
  add_test(
    NAME    test-icu-cmake
    COMMAND test-icu-cmake
  )
endif()

if(NOT ICU_CMAKE_BUILD_ICU_TEST)
  return()
endif()

# ICU test programs -----------------------------------------------------------------------------------------
#
# Every directory under `source/test` is inspected. A directory is one test program when its
# `Makefile.in` links `LIBCTESTFW` and lists concrete object files. The programs found that way are
# the ones ICU runs with `make check`: `cintltst`, `intltest`, and `iotest`. Data, scripts,
# benchmarks, fuzz targets, and the layout-engine test do not match, so they are not named here.

file(GLOB testEntries CONFIGURE_DEPENDS ${ICU_SOURCE_DIR}/test/*)
list(SORT testEntries)

set(testdataDirs)
set(programDirs)
foreach(dir IN LISTS testEntries)
  if(NOT IS_DIRECTORY ${dir})
    continue()
  endif()
  if(EXISTS ${dir}/BUILDRULES.py)
    list(APPEND testdataDirs ${dir})
  endif()
  IcuReadTestProgram(${dir} sources)
  if(sources)
    list(APPEND programDirs ${dir})
  endif()
endforeach()

list(LENGTH testdataDirs testdataCount)
if(NOT testdataCount EQUAL 1)
  IcuFatalError("Expected one test-data directory under ${ICU_SOURCE_DIR}/test, found ${testdataCount}")
endif()
if(NOT programDirs)
  IcuFatalError("No ICU test programs found under ${ICU_SOURCE_DIR}/test")
endif()

list(GET testdataDirs 0 testdataDir)
cmake_path(GET testdataDir FILENAME testdataName)

set(programNames)
foreach(dir IN LISTS programDirs)
  cmake_path(GET dir FILENAME name)
  list(APPEND programNames ${name})
endforeach()
IcuStatus("ICU tests: ${programNames}")

# Paths the test programs bake in. `U_TOPBUILDDIR` must contain `data/out/build/<package>/` and
# `test/<testdata>/out/`. `U_TOPSRCDIR` must contain real `data/` and `test/` directories: the
# programs open `data/../test/testdata/...`, and `..` is resolved in the directory a symlink points
# at, so `data` itself cannot be a symlink.
set(ICU_TEST_BUILDDIR ${CMAKE_CURRENT_BINARY_DIR}/icu-top-build)
if(EXISTS ${ICU_SOURCE_DIR}/data/unidata/UnicodeData.txt AND NOT IS_SYMLINK ${ICU_SOURCE_DIR}/data)
  set(ICU_TEST_SRCDIR ${ICU_SOURCE_DIR})
else()
  if(NOT EXISTS ${ICU_DATA_SOURCE_DIR}/unidata/UnicodeData.txt)
    IcuFatalError("ICU tests need the data text sources, including unidata/UnicodeData.txt")
  endif()
  set(ICU_TEST_SRCDIR ${CMAKE_CURRENT_BINARY_DIR}/icu-top-src)
  # A previous configure may have linked these paths. `..` has to stay inside this tree.
  if(IS_SYMLINK ${ICU_TEST_SRCDIR}/data)
    file(REMOVE ${ICU_TEST_SRCDIR}/data)
  endif()
  if(IS_SYMLINK ${ICU_TEST_SRCDIR}/test)
    file(REMOVE ${ICU_TEST_SRCDIR}/test)
  endif()
  file(MAKE_DIRECTORY ${ICU_TEST_SRCDIR}/data ${ICU_TEST_SRCDIR}/test/${testdataName})
  file(GLOB dataChildren ${ICU_DATA_SOURCE_DIR}/*)
  foreach(child IN LISTS dataChildren)
    cmake_path(GET child FILENAME name)
    IcuEnsureSymlink(${child} ${ICU_TEST_SRCDIR}/data/${name})
  endforeach()
  file(GLOB testChildren ${ICU_SOURCE_DIR}/test/*)
  foreach(child IN LISTS testChildren)
    cmake_path(GET child FILENAME name)
    if(name STREQUAL testdataName)
      file(GLOB testdataChildren ${child}/*)
      foreach(item IN LISTS testdataChildren)
        cmake_path(GET item FILENAME itemName)
        IcuEnsureSymlink(${item} ${ICU_TEST_SRCDIR}/test/${testdataName}/${itemName})
      endforeach()
    else()
      IcuEnsureSymlink(${child} ${ICU_TEST_SRCDIR}/test/${name})
    endif()
  endforeach()
endif()

# `U_UNICODE_VERSION` lives in `uchar.h`. Older releases defined it in `uvernum.h`.
set(ICU_UNICODE_VERSION)
foreach(header IN ITEMS
  ${ICU_SOURCE_DIR}/common/unicode/uchar.h
  ${ICU_SOURCE_DIR}/common/unicode/uvernum.h
)
  if(NOT EXISTS ${header})
    continue()
  endif()
  file(STRINGS ${header} unicodeLine REGEX "^#define[ \t]+U_UNICODE_VERSION[ \t]+\"[^\"]+\"")
  if(unicodeLine MATCHES "^#define[ \t]+U_UNICODE_VERSION[ \t]+\"([^\"]+)\"")
    set(ICU_UNICODE_VERSION ${CMAKE_MATCH_1})
    break()
  endif()
endforeach()
if(NOT ICU_UNICODE_VERSION MATCHES "^[0-9.]+$")
  IcuFatalError("Cannot parse U_UNICODE_VERSION from the ICU headers")
endif()

# C test framework ------------------------------------------------------------------------------------------

IcuReadSources(${ICU_SOURCE_DIR}/tools/ctestfw ctestfwSources)
add_library(icuctest STATIC ${ctestfwSources})
IcuApplyCommonSettings(icuctest)
target_compile_options(icuctest PRIVATE ${COMPILE_FLAGS})
# The framework is linked statically into each test, so the test sources must see the same
# implementation macro the framework was compiled with
target_compile_definitions(icuctest PUBLIC T_CTEST_IMPLEMENTATION)
target_include_directories(icuctest PUBLIC ${ICU_SOURCE_DIR}/tools/ctestfw)
target_link_libraries(icuctest PUBLIC icu-cmake::io icu-cmake::tu icu-cmake::i18n icu-cmake::uc)

# Test data -------------------------------------------------------------------------------------------------
#
# `icutools.databuilder` reads `BUILDRULES.py` from `--src_dir` and runs every tool that file names.
# `genrb` reads the built library data through `LIBRARY_DATA_DIR`, which the driver sets to
# `<out dir>/build`, so that path is a link to the library data. `pkgdata` then writes
# `test/<name>/out/<name>.dat`, which is where the test programs open it.

file(STRINGS ${testdataDir}/BUILDRULES.py toolLines REGEX "IcuTool\\(\"")
set(testdataTools)
foreach(line IN LISTS toolLines)
  if(line MATCHES "IcuTool\\(\"([^\"]+)\"\\)")
    list(APPEND testdataTools ${CMAKE_MATCH_1})
  endif()
endforeach()
list(REMOVE_DUPLICATES testdataTools)
if(NOT testdataTools)
  IcuFatalError("No tools named in ${testdataDir}/BUILDRULES.py")
endif()

set(testdataToolTargets)
foreach(tool IN LISTS testdataTools)
  if(NOT TARGET icu-${tool})
    IcuAddTool(${tool})
    set(toolMakefile ${ICU_SOURCE_DIR}/tools/${tool}/Makefile.in)
    if(EXISTS ${toolMakefile})
      file(STRINGS ${toolMakefile} mentionsCtestfw REGEX "ctestfw")
      if(mentionsCtestfw)
        target_include_directories(icu-${tool} PRIVATE ${ICU_SOURCE_DIR}/tools/ctestfw)
      endif()
    endif()
  endif()
  list(APPEND testdataToolTargets icu-${tool})
endforeach()

file(STRINGS ${testdataDir}/BUILDRULES.py listLine REGEX "TmpFile\\(\"[^\"]+\\.lst\"\\)")
if(NOT listLine MATCHES "TmpFile\\(\"([^\"]+)\"\\)")
  IcuFatalError("No list file named in ${testdataDir}/BUILDRULES.py")
endif()
set(testdataListName ${CMAKE_MATCH_1})

set(testTop ${ICU_TEST_BUILDDIR})
set(testOut ${testTop}/test/${testdataName}/out)
set(testOutBuild ${testOut}/build)
set(testTmp ${testOut}/${testdataName})
set(testDat ${testOut}/${testdataName}.dat)
set(layoutStamp ${CMAKE_CURRENT_BINARY_DIR}/icu-test-layout.stamp)

# `cintltst` and `intltest` read `data/out/build/<package>`. `iotest` reads `data/out/<package>`.
add_custom_command(
  OUTPUT  ${layoutStamp}
  COMMAND ${CMAKE_COMMAND} -E make_directory ${testTop}/data/out
  COMMAND ${CMAKE_COMMAND} -E rm -rf ${testTop}/data/out/build ${testTop}/data/out/${ICU_DATA_NAME}
  COMMAND ${CMAKE_COMMAND} -E create_symlink ${ICU_DATA_DIR}/out ${testTop}/data/out/build
  COMMAND ${CMAKE_COMMAND} -E create_symlink ${ICU_DATA_DIR}/out/${ICU_DATA_NAME} ${testTop}/data/out/${ICU_DATA_NAME}
  COMMAND ${CMAKE_COMMAND} -E touch ${layoutStamp}
  DEPENDS icudata
  COMMENT "icu-cmake: Linking the built ICU data into the test tree"
  VERBATIM
)

set(testdataSrc ${ICU_TEST_SRCDIR}/test/${testdataName})
IcuPythonPath("${testdataSrc}"   pyTestSrc)
IcuPythonPath("${testOutBuild}"  pyTestOutBuild)
IcuPythonPath("${testTmp}"       pyTestTmp)
IcuPythonPath("${ICU_TOOL_DIR}"  pyToolDir)
if(ICU_PYTHON_NATIVE_WINDOWS)
  set(databuilderArgs --mode windows-exec --tool_dir "${pyToolDir}" --tool_cfg "$<CONFIG>")
else()
  IcuPythonPath("${ICU_TOOL_BIN_DIR}" pyToolDir)
  set(databuilderArgs --mode unix-exec --tool_dir "${pyToolDir}")
endif()
if(ICU_CMAKE_DATA_VERBOSE)
  list(APPEND databuilderArgs --verbose)
endif()

file(GLOB_RECURSE testdataInputs CONFIGURE_DEPENDS ${testdataDir}/*)

add_custom_command(
  OUTPUT  ${testDat}
  COMMAND ${CMAKE_COMMAND} -E rm -rf ${testOut}
  COMMAND ${CMAKE_COMMAND} -E make_directory ${testOutBuild} ${testTmp}
  COMMAND ${CMAKE_COMMAND} -E create_symlink ${ICU_DATA_DIR}/out ${testOutBuild}/build
  COMMAND ${CMAKE_COMMAND} -E env PYTHONDONTWRITEBYTECODE=1
            ${Python3_EXECUTABLE} -m icutools.databuilder
              --src_dir "${pyTestSrc}"
              --out_dir "${pyTestOutBuild}"
              --tmp_dir "${pyTestTmp}"
              ${databuilderArgs}
  COMMAND icu-pkgdata -m common -q -c -p ${testdataName} -s ${testOutBuild} -T ${testTmp} -d ${testOut}
            ${testTmp}/${testdataListName}
  DEPENDS ${testdataToolTargets} icu-pkgdata ${layoutStamp} ${testdataInputs}
  WORKING_DIRECTORY ${ICU_SOURCE_DIR}/python
  COMMENT "icu-cmake: Building the ICU test data"
  VERBATIM
)
add_custom_target(icu-testdata DEPENDS ${testDat})

# Test programs ---------------------------------------------------------------------------------------------

foreach(dir IN LISTS programDirs)
  cmake_path(GET dir FILENAME name)
  IcuReadTestProgram(${dir} sources)
  IcuAddExecutable(${name} ${sources})
  IcuApplyCommonSettings(${name})
  target_include_directories(${name} PRIVATE ${dir})
  # Trailing slash, as in ICU's makefiles. The sources append another separator.
  target_compile_definitions(${name}
    PRIVATE
      "U_TOPSRCDIR=\"${ICU_TEST_SRCDIR}/\""
      "U_TOPBUILDDIR=\"${ICU_TEST_BUILDDIR}/\""
      "ICU_VERSION=\"${ICU_VERSION}\""
      "ICU_UNICODE_VERSION=\"${ICU_UNICODE_VERSION}\""
      "ICUDATA_NAME=\"${ICU_DATA_NAME}\""
      "UNISTR_FROM_CHAR_EXPLICIT="
      "UNISTR_FROM_STRING_EXPLICIT="
  )
  target_link_libraries(${name} PRIVATE icuctest)
  # `cintltst` is C, and the test framework is C++
  set_target_properties(${name} PROPERTIES LINKER_LANGUAGE CXX)
  if(WIN32 AND BUILD_SHARED_LIBS)
    add_custom_command(
      TARGET  ${name} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_newer $<TARGET_RUNTIME_DLLS:${name}> $<TARGET_FILE_DIR:${name}>
      COMMAND_EXPAND_LISTS
    )
  endif()
  add_dependencies(${name} icu-testdata)
  add_test(
    NAME    ${name}
    COMMAND ${name}
  )
  # A debug `intltest` can take well over an hour
  set_tests_properties(${name} PROPERTIES TIMEOUT 7200)
endforeach()

# EOF
