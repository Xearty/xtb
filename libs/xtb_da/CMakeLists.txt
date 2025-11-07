add_library(xtb_da da.c)

target_include_directories(xtb_da PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(xtb_da PUBLIC xtb_core)
