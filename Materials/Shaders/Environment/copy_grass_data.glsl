#[compute]
#version 450
#extension GL_NV_compute_shader_derivatives : enable

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
        
        
// densely packed        
layout(set = 0, binding = 0, std430) writeonly buffer DenseTransforms {
float data[];
}
OUT_TRANSFORMS;

// there's empty space here 
// MAKE SURE THIS IS THE SAME BINDING AS IN THE COMPUTE GRASS BINDING
layout(set = 0, binding = 1, std430) readonly buffer SparseTransforms {
float data[];
}
IN_TRANSFORMS;        

layout(std430,set = 0, binding = 2) restrict writeonly buffer CommandBuffer { int data[]; } COMMAND_BUFFER_AMOUNT;


void main() 
{
   //DenseTransforms.data = SparseTransforms.data;
}