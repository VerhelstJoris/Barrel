#[compute]
#version 450
#extension GL_NV_compute_shader_derivatives: enable

layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// densely packed        
layout (set = 0, binding = 0, std430) writeonly buffer OutputTransforms {
vec4 data[];
}
OUT_TRANSFORMS;

// there's empty space here 
// MAKE SURE THIS IS THE SAME BINDING AS IN THE COMPUTE GRASS BINDING
layout (set = 0, binding = 1, std430) readonly buffer InputTransforms {
vec4 data[];
}
IN_TRANSFORMS;

// array detailing how many grassblades are actually present in a specific         
layout (set = 0, binding = 2, std430) readonly buffer BladeAmounts {
int data[];
} BLADESPERGROUP;


// multimesh command buffer that determines how many instances there are
layout (std430, set = 0, binding = 3) restrict writeonly buffer CommandBuffer
{ int data[];
} COMMAND_BUFFER;

layout (set = 0, binding = 4, std430) restrict readonly buffer IParameters
{
    int MAX_BLADES_PER_GROUP;
    int AMOUNT_OF_SEGMENTS_IN_CHUNK_PER_DIM;
            
    int SEGMENT_ID_OFFSET;
} IPARAMETERS;
        
void assign_blade_count()
{
int total_blades = 0;
const int num = int(gl_NumWorkGroups.x * gl_NumWorkGroups.z);
for (int index = 0; index < num; index++)
{
total_blades = total_blades + BLADESPERGROUP.data[index];
}

COMMAND_BUFFER.data[1] = total_blades;
}


void main()
{
    const int group_id_arr = int(int(gl_WorkGroupID.x * gl_NumWorkGroups.z) + gl_WorkGroupID.z);


    const int blades_in_group = BLADESPERGROUP.data[group_id_arr];
    int write_offset = 0;
    const int read_offset = IPARAMETERS.MAX_BLADES_PER_GROUP * group_id_arr * 3;
    for (int index = 0; index < group_id_arr; index++)
    {
        write_offset = write_offset + (BLADESPERGROUP.data[index] * 3);
    }
    
    for (int copy_id = 0; copy_id < blades_in_group * 3; copy_id++)
    {
        OUT_TRANSFORMS.data[write_offset + copy_id] = IN_TRANSFORMS.data[read_offset + copy_id];
    }

    if (group_id_arr == 0)
    {
        assign_blade_count();
    }
}