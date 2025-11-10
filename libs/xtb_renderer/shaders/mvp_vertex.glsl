#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec2 aTexCoords;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

out vec2 texCoords;
out vec3 position;
out vec3 localPosition;
out vec3 normal;

void main()
{
    vec4 worldCoords = model * vec4(aPos, 1.0);
    gl_Position = projection * view * worldCoords;
    texCoords = aTexCoords;

    position = vec3(worldCoords);
    localPosition = aPos;

    normal = inverse(transpose(mat3(model))) * aNormal;
}
