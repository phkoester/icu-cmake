#
# CMakeLists.txt
#

# Tests -----------------------------------------------------------------------------------------------------

# test-icu-cmake ............................................................................................

if(ICU_CMAKE_BUILD_TEST)
  GaiaAddExecutable(test-icu-cmake test-icu-cmake.cc)
  target_link_libraries(test-icu-cmake PRIVATE ICU::i18n ICU::io ICU::uc)
  add_test(NAME test-icu-cmake COMMAND test-icu-cmake)
endif()

# ICU’s own tests ...........................................................................................

if(ICU_CMAKE_BUILD_ICU_TEST)
  include(${ICU_CMAKE_DIR}/cmake/IcuTests.cmake)
endif()

# EOF
