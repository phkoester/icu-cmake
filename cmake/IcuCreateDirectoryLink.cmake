#
# IcuCreateDirectoryLink.cmake
#
# Creates a directory symlink, or a junction on Windows when symlinks are not permitted.
# Included for the function, or run with `cmake -Doriginal=... -DlinkName=... -P` this file.
#

# IcuCreateDirectoryLink(original linkName)
function(IcuCreateDirectoryLink original linkName)
  if(IS_SYMLINK "${linkName}" OR EXISTS "${linkName}")
    return()
  endif()

  cmake_path(GET linkName PARENT_PATH parent)
  if(parent)
    file(MAKE_DIRECTORY "${parent}")
  endif()

  file(CREATE_LINK "${original}" "${linkName}" SYMBOLIC RESULT result)
  if(result AND WIN32)
    execute_process(
      COMMAND cmd /c mklink /J "${linkName}" "${original}"
      RESULT_VARIABLE result
    )
  endif()
  if(result)
    message(FATAL_ERROR "icu-cmake: Could not link `${linkName}` to `${original}`: ${result}")
  endif()
endfunction()

if(CMAKE_SCRIPT_MODE_FILE AND CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
  if(NOT DEFINED original OR NOT DEFINED linkName)
    message(FATAL_ERROR "icu-cmake: -Doriginal and -DlinkName are required")
  endif()
  IcuCreateDirectoryLink("${original}" "${linkName}")
endif()

# EOF
