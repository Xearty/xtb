find_package(PkgConfig REQUIRED)
pkg_check_modules(ASSIMP IMPORTED_TARGET assimp)

add_executable(window_test main.cpp)

target_link_libraries(window_test PRIVATE xtb_window xtb_ogl xtb_renderer xtbm xtb_noise PkgConfig::ASSIMP)
