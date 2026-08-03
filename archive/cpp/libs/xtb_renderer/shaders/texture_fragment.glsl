#version 330 core
out vec4 FragColor;

in vec2 texCoords;
in vec3 normal;
in vec3 position;

uniform sampler2D tex;
uniform vec3 u_LightPosition;
uniform vec3 u_LightColor;

void main()
{
    float ambientStrength = 0.1;
    vec3 ambient = ambientStrength * u_LightColor;

    vec3 lightDirection = normalize(u_LightPosition - position);
    vec3 norm = normalize(normal);

    float diffuseStrength = clamp(dot(norm, lightDirection), 0.0, 1.0);
    vec3 diffuse = diffuseStrength * u_LightColor;

    vec3 objColor = texture(tex, texCoords).xyz;
    vec3 shadedColor = (ambient + diffuse) * objColor;

    FragColor = vec4(shadedColor, 1.0);
}
