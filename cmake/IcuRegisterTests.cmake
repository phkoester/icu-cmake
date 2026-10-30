#
# IcuRegisterTests.cmake
#
# Adds the CTest entries for the ICU programs built by `IcuTests.cmake`.
# Included from `src/test`, which is the directory `make test` runs.
#

# IcuRegisterDiscoveredTests()
function(IcuRegisterDiscoveredTests)
  get_property(targets GLOBAL PROPERTY ICU_CMAKE_ICU_TEST_TARGETS)
  foreach(target IN LISTS targets)
    get_property(testDir GLOBAL PROPERTY "ICU_CMAKE_ICU_TEST_${target}_DIR")
    get_property(testArgs GLOBAL PROPERTY "ICU_CMAKE_ICU_TEST_${target}_ARGS")
    add_test(NAME ${target} COMMAND ${target} ${testArgs})
    set_tests_properties(${target}
      PROPERTIES
        WORKING_DIRECTORY "${testDir}"
        TIMEOUT 3600
    )
  endforeach()
endfunction()

# EOF
