project(cpp_bindings_test CXX)

add_executable(cpp_bindings_test main.cpp)
target_link_libraries(cpp_bindings_test PRIVATE xtb_core xtb_core_cpp)

