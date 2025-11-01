add_library(xtb_allocator allocator.c)

target_include_directories(xtb_allocator PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(xtb_allocator PRIVATE xtb_core)
