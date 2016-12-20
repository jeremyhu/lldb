function(add_lldb_library name)
  # only supported parameters to this macro are the optional
  # MODULE;SHARED;STATIC library type and source files
  cmake_parse_arguments(PARAM
    "MODULE;SHARED;STATIC;OBJECT;PLUGIN"
    ""
    "DEPENDS;LINK_LIBS;LINK_COMPONENTS"
    ${ARGN})
  llvm_process_sources(srcs ${PARAM_UNPARSED_ARGUMENTS})
  list(APPEND LLVM_LINK_COMPONENTS ${PARAM_LINK_COMPONENTS})

  if(PARAM_PLUGIN)
    set_property(GLOBAL APPEND PROPERTY LLDB_PLUGINS ${name})
  endif()

  if (MSVC_IDE OR XCODE)
    string(REGEX MATCHALL "/[^/]+" split_path ${CMAKE_CURRENT_SOURCE_DIR})
    list(GET split_path -1 dir)
    file(GLOB_RECURSE headers
      ../../include/lldb${dir}/*.h)
    set(srcs ${srcs} ${headers})
  endif()
  if (PARAM_MODULE)
    set(libkind MODULE)
  elseif (PARAM_SHARED)
    set(libkind SHARED)
  elseif (PARAM_OBJECT)
    set(libkind OBJECT)
  else ()
    # PARAM_STATIC or library type unspecified. BUILD_SHARED_LIBS
    # does not control the kind of libraries created for LLDB,
    # only whether or not they link to shared/static LLVM/Clang
    # libraries.
    set(libkind STATIC)
  endif()

  #PIC not needed on Win
  if (NOT WIN32)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC")
  endif()

  if (PARAM_OBJECT)
    add_library(${name} ${libkind} ${srcs})
  else()
    llvm_add_library(${name} ${libkind} ${srcs} LINK_LIBS
                                ${PARAM_LINK_LIBS}
                                DEPENDS ${PARAM_DEPENDS})

    if (NOT LLVM_INSTALL_TOOLCHAIN_ONLY OR ${name} STREQUAL "liblldb")
      if (PARAM_SHARED)
        set(out_dir lib${LLVM_LIBDIR_SUFFIX})
        if(${name} STREQUAL "liblldb" AND LLDB_BUILD_FRAMEWORK)
          set(out_dir ${LLDB_FRAMEWORK_INSTALL_DIR})
        endif()
        install(TARGETS ${name}
          COMPONENT ${name}
          RUNTIME DESTINATION bin
          LIBRARY DESTINATION ${out_dir}
          ARCHIVE DESTINATION ${out_dir})
      else()
        install(TARGETS ${name}
          COMPONENT ${name}
          LIBRARY DESTINATION lib${LLVM_LIBDIR_SUFFIX}
          ARCHIVE DESTINATION lib${LLVM_LIBDIR_SUFFIX})
      endif()
      if (NOT CMAKE_CONFIGURATION_TYPES)
        add_custom_target(install-${name}
                          DEPENDS ${name}
                          COMMAND "${CMAKE_COMMAND}"
                                  -DCMAKE_INSTALL_COMPONENT=${name}
                                  -P "${CMAKE_BINARY_DIR}/cmake_install.cmake")
      endif()
    endif()
  endif()

  # Hack: only some LLDB libraries depend on the clang autogenerated headers,
  # but it is simple enough to make all of LLDB depend on some of those
  # headers without negatively impacting much of anything.
  get_property(CLANG_TABLEGEN_TARGETS GLOBAL PROPERTY CLANG_TABLEGEN_TARGETS)
  if(CLANG_TABLEGEN_TARGETS)
    add_dependencies(${name} ${CLANG_TABLEGEN_TARGETS})
  endif()

  set_target_properties(${name} PROPERTIES FOLDER "lldb libraries")
endfunction(add_lldb_library)

function(add_lldb_executable name)
  cmake_parse_arguments(ARG
    "INCLUDE_IN_FRAMEWORK;GENERATE_INSTALL"
    ""
    "LINK_LIBS;LINK_COMPONENTS"
    ${ARGN}
    )

  list(APPEND LLVM_LINK_COMPONENTS ${ARG_LINK_COMPONENTS})
  add_llvm_executable(${name} ${ARG_UNPARSED_ARGUMENTS})

  target_link_libraries(${name} ${ARG_LINK_LIBS})
  set_target_properties(${name} PROPERTIES
    FOLDER "lldb executables")

  if(LLDB_BUILD_FRAMEWORK)
    if(ARG_INCLUDE_IN_FRAMEWORK)
      string(REGEX REPLACE "[^/]+" ".." _dots ${LLDB_FRAMEWORK_INSTALL_DIR})
      set_target_properties(${name} PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY $<TARGET_FILE_DIR:liblldb>/Resources
            BUILD_WITH_INSTALL_RPATH On
            INSTALL_RPATH "@loader_path/../../../../${_dots}/${LLDB_FRAMEWORK_INSTALL_DIR}")
      # For things inside the framework we don't need functional install targets
      # because CMake copies the resources and headers from the build directory.
      # But we still need this target to exist in order to use the
      # LLVM_DISTRIBUTION_COMPONENTS build option. We also need the
      # install-liblldb target to depend on this tool, so that it gets put into
      # the Resources directory before the framework is installed.
      if(ARG_GENERATE_INSTALL)
        add_custom_target(install-${name} DEPENDS ${name})
        add_dependencies(install-liblldb ${name})
      endif()
    else()
      set_target_properties(${name} PROPERTIES
            BUILD_WITH_INSTALL_RPATH On
            INSTALL_RPATH "@loader_path/../${LLDB_FRAMEWORK_INSTALL_DIR}")
    endif()
  endif()

  if(ARG_GENERATE_INSTALL AND NOT (ARG_INCLUDE_IN_FRAMEWORK AND LLDB_BUILD_FRAMEWORK ))
    install(TARGETS ${name}
          COMPONENT ${name}
          RUNTIME DESTINATION bin)
    if (NOT CMAKE_CONFIGURATION_TYPES)
      add_custom_target(install-${name}
                        DEPENDS ${name}
                        COMMAND "${CMAKE_COMMAND}"
                                -DCMAKE_INSTALL_COMPONENT=${name}
                                -P "${CMAKE_BINARY_DIR}/cmake_install.cmake")
    endif()
  else()
    if(ARG_GENERATE_INSTALL)
      install(TARGETS ${name}
            COMPONENT ${name}
            RUNTIME DESTINATION ${install_dir})
    endif()
  endif()

  if(ARG_INCLUDE_IN_FRAMEWORK AND LLDB_BUILD_FRAMEWORK)
    add_llvm_tool_symlink(${name} ${name} ALWAYS_GENERATE SKIP_INSTALL
                            OUTPUT_DIR ${LLVM_RUNTIME_OUTPUT_INTDIR})
  endif()
endfunction(add_lldb_executable)

function(add_lldb_tool name)
  add_lldb_executable(${name} GENERATE_INSTALL ${ARGN})
endfunction()

# Support appending linker flags to an existing target.
# This will preserve the existing linker flags on the
# target, if there are any.
function(lldb_append_link_flags target_name new_link_flags)
  # Retrieve existing linker flags.
  get_target_property(current_link_flags ${target_name} LINK_FLAGS)

  # If we had any linker flags, include them first in the new linker flags.
  if(current_link_flags)
    set(new_link_flags "${current_link_flags} ${new_link_flags}")
  endif()

  # Now set them onto the target.
  set_target_properties(${target_name} PROPERTIES LINK_FLAGS ${new_link_flags})
endfunction()
