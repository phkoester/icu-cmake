#
# CMakeLists.txt
#

# Tests -----------------------------------------------------------------------------------------------------

# test-icu-cmake ............................................................................................
#
# Smoke test: checks that the ICU libraries link and that the real (non-stub) data is available.
#
# ...........................................................................................................

GaiaAddExecutable(test-icu-cmake test-icu-cmake.cc)
target_link_libraries(test-icu-cmake PRIVATE icu-cmake::io icu-cmake::i18n icu-cmake::uc)
GaiaCopyRuntimeFiles(test-icu-cmake)
add_test(
  NAME    test-icu-cmake
  COMMAND test-icu-cmake
)

# EOF
