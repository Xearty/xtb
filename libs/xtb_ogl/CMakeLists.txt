add_library(xtb_ogl ogl.cpp)

target_link_libraries(xtb_ogl PUBLIC xtb_os xtb_core)
target_include_directories(xtb_ogl PUBLIC glad/include)

