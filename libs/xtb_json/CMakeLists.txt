add_library(xtb_json json.c)

target_include_directories(xtb_json PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(xtb_json PUBLIC xtb_core xtb_os xtb_ansi)
