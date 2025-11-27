cmake_minimum_required(VERSION 3.16)
project(xtb C)

option(XTB_BUILD_APPS "Build xtb applications/tests" ON)
option(XTB_BUILD_CPP "Build the cpp bindings" ON)

add_compile_options(
    -Wall
    # -Wextra
    -Werror
)

if (CMAKE_C_COMPILER_ID STREQUAL "GNU" AND CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_compile_options(
        -Og
        -ggdb
        -fno-omit-frame-pointer
    )
endif()

add_subdirectory(libs)

if(XTB_BUILD_APPS)
    add_subdirectory(apps)
endif()

if(XTB_BUILD_CPP)
    add_subdirectory(bindings/cpp)
endif()
