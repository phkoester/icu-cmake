#
# CMakeLists.txt
#

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

# EOF
