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
  GaiaCopyRuntimeFiles(test-icu-cmake)
  add_test(
    NAME    test-icu-cmake
    COMMAND test-icu-cmake
  )
endif()

# ICU's own tests are built in `src/main` and registered here, because `make test` runs this directory.
if(ICU_CMAKE_BUILD_ICU_TEST)
  include(${ICU_CMAKE_DIR}/cmake/IcuRegisterTests.cmake)
  IcuRegisterDiscoveredTests()
endif()

# EOF
