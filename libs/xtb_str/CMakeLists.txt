add_library(xtb_str str.c)

target_include_directories(xtb_str PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(xtb_str PRIVATE xtb_core)
