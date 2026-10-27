#
# CMakeLists.txt
#

AddExecutable(test-icu-cmake test-icu-cmake.cc)
target_link_libraries(test-icu-cmake PRIVATE ICU::io ICU::i18n ICU::uc)

add_test(
  NAME    test-icu-cmake
  COMMAND test-icu-cmake
)

# EOF
