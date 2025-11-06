add_library(xtb_core_cpp core.cpp)

target_include_directories(xtb_core_cpp PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(xtb_core_cpp PUBLIC xtb_core)

target_compile_features(xtb_core_cpp PUBLIC cxx_std_11)

