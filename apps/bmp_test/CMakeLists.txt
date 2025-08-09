find_package(PkgConfig REQUIRED)
pkg_check_modules(RAYLIB REQUIRED raylib)

add_executable(bmp_test main.c)

target_include_directories(bmp_test
                           PRIVATE
			   ${CMAKE_CURRENT_SOURCE_DIR}
			   ${RAYLIB_INCLUDE_DIRS})
target_link_libraries(bmp_test PRIVATE xtb_bmp xtb_allocator xtbm xtb_os ${RAYLIB_LIBRARIES} m)
