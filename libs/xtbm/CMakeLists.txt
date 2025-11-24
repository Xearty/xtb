add_library(xtbm xtbm.c)

target_include_directories(xtbm PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(xtbm PUBLIC m)
