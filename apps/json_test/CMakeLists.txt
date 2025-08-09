find_package(PkgConfig REQUIRED)
pkg_check_modules(READLINE IMPORTED_TARGET readline)

add_executable(json_test main.c)

target_link_libraries(json_test PRIVATE xtb_json xtb_ansi xtb_allocator xtb_core PkgConfig::READLINE)

