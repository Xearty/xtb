find_package(PkgConfig REQUIRED)
pkg_check_modules(GLFW3 IMPORTED_TARGET glfw3)

add_library(xtb_window window.cpp)

target_include_directories(xtb_window PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(xtb_window PUBLIC xtb_core PkgConfig::GLFW3)

