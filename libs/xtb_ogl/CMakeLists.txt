add_library(xtb_ogl ogl.c)

set(SHADERS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/shaders)
set(SHADERS_GENERATED_HEADER ${CMAKE_CURRENT_SOURCE_DIR}/generated/baked_shaders_generated.h)

add_executable(shader_baker tools/shader_baker.c)
target_link_libraries(shader_baker PRIVATE xtb_core xtb_os)

add_custom_command(
    OUTPUT ${SHADERS_GENERATED_HEADER}
    COMMAND shader_baker ${SHADERS_DIR} ${SHADERS_GENERATED_HEADER}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    DEPENDS shader_baker
    DEPENDS ${SHADERS_DIR}
    COMMENT "Baking shaders into header"
)
add_custom_target(bake_shaders DEPENDS ${SHADERS_GENERATED_HEADER})
add_dependencies(xtb_ogl bake_shaders)

target_link_libraries(xtb_ogl PUBLIC xtb_os xtb_core)
target_include_directories(xtb_ogl PUBLIC glad/include)

