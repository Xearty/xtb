#version 330 core
out vec4 FragColor;

uniform vec4 color;

uniform float u_Time;

void main()
{
    FragColor = color * abs(sin(u_Time));
}
