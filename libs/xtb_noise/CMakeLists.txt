add_library(xtb_noise noise.cpp)

target_include_directories(xtb_noise PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(xtb_noise PRIVATE xtb_core xtbm)
