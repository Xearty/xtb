cmake_minimum_required(VERSION 3.16)
project(xtb C)

option(XTB_BUILD_APPS "Build xtb applications/tests" ON)

add_subdirectory(libs)

if(XTB_BUILD_APPS)
    add_subdirectory(apps)
endif()
