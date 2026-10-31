#
# CMakeLists.txt
#

include(GoogleTest)

# Tests -----------------------------------------------------------------------------------------------------

# test-icu-cmake ............................................................................................

if(ICU_CMAKE_BUILD_TEST)
  GaiaAddExecutable(test-icu-cmake test-icu-cmake.cc)
  target_link_libraries(test-icu-cmake PRIVATE GTest::gtest_main ICU::i18n ICU::io ICU::uc)
  gtest_discover_tests(test-icu-cmake DISCOVERY_MODE PRE_TEST)
endif()

# ICU's own tests ...........................................................................................

if(ICU_CMAKE_BUILD_ICU_TEST)
  include(${ICU_CMAKE_DIR}/cmake/IcuTests.cmake)
endif()

# EOF
