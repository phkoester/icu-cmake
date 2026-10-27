#
# CMakeLists.txt
#

AddExecutable(test-icu-cmake test-icu-cmake.cc)
target_link_libraries(test-icu-cmake PRIVATE ICU-cmake::io ICU-cmake::i18n ICU-cmake::uc)

add_test(
  NAME    test-icu-cmake
  COMMAND test-icu-cmake
)

# EOF
