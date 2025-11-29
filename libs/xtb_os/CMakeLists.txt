add_library(xtb_os os.cpp)

target_include_directories(xtb_os PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(xtb_os PRIVATE xtb_core)
