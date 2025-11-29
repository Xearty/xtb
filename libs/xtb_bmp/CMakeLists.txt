add_library(xtb_bmp bmp.cpp)

target_include_directories(xtb_bmp PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(xtb_bmp PUBLIC xtb_core)
