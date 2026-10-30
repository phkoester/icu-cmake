#
# CMakeLists.txt
#

# Tests -----------------------------------------------------------------------------------------------------

# test-icu-cmake ............................................................................................
#
# Smoke test: checks that the ICU libraries link and that the real (non-stub) data is available.
#
# ...........................................................................................................

if(ICU_CMAKE_BUILD_TEST)
  GaiaAddExecutable(test-icu-cmake test-icu-cmake.cc)
  target_link_libraries(test-icu-cmake PRIVATE icu-cmake::io icu-cmake::i18n icu-cmake::uc)

  # Register each entry of the `tests` table in `test-icu-cmake.cc` as its own test. Editing the source
  # re-runs CMake, so new entries are picked up on the next build.
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS test-icu-cmake.cc)
  file(STRINGS test-icu-cmake.cc testLines REGEX "^[ \t]*{\"[A-Za-z0-9_]+\", *test[A-Za-z0-9_]+},")
  if(NOT testLines)
    GaiaFatalError("No tests found in `test-icu-cmake.cc`")
  endif()
  foreach(line IN LISTS testLines)
    string(REGEX MATCH "\"([A-Za-z0-9_]+)\"" _ "${line}")
    add_test(
      NAME    test-icu-cmake.${CMAKE_MATCH_1}
      COMMAND test-icu-cmake ${CMAKE_MATCH_1}
    )
  endforeach()
endif()

# ICU's own tests are built in `src/main` and registered here, because `make test` runs this directory.
if(ICU_CMAKE_BUILD_ICU_TEST)
  include(${ICU_CMAKE_DIR}/cmake/IcuRegisterTests.cmake)
  IcuRegisterDiscoveredTests()
endif()

# EOF
