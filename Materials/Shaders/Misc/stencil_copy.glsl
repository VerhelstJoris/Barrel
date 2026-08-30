#[vertex]
#version 450 core
layout(location = 0) in vec3 vertex_attrib;

void main()
{
    gl_Position = vec4(vertex_attrib, 1.0);
}

#[fragment]
#version 450 core
layout (location = 0) out float frag_color;
layout (set = 0, binding = 0) uniform FrameData {
    vec2 resolution;
};

void main() {
    frag_color = 1.0;
}
