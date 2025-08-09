add_library(xtb_da da.c)

target_include_directories(xtb_da PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
targeT_link_libraries(xtb_da PRIVATE xtb_core)
