#
# CMakeLists.txt
#

IcuAddExecutable(test-icu-cmake test-icu-cmake.cc)
target_link_libraries(test-icu-cmake PRIVATE icu-cmake::io icu-cmake::i18n icu-cmake::uc)
add_test(
  NAME    test-icu-cmake
  COMMAND test-icu-cmake
)

# EOF
