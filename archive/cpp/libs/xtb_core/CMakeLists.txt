add_library(xtb_core src/core.cpp)

target_include_directories(xtb_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(xtb_core PUBLIC xtb_ansi backtrace)
