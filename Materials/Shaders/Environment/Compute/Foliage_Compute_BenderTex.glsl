#[compute]
#version 450
#extension GL_NV_compute_shader_derivatives : enable

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;


layout(set = 0,binding = 0, r32f) uniform restrict readonly image2D IN_FOLIAGE_BENDER;

layout(set = 0,binding = 1, r32f) uniform restrict image2D OUT_FOLIAGE_BENDER;

layout(set = 0, binding = 2, std430) restrict readonly buffer FParameters {
    float DECAY_RATE_PER_SECOND;
    float DELTA;
} FPARAMETERS;
        
void main() 
{
    const int group_id_arr =  int((gl_WorkGroupID.x * gl_NumWorkGroups.x) + gl_WorkGroupID.z);

    const ivec2 mask_size = imageSize(IN_FOLIAGE_BENDER);
    const ivec2 amount_per_group = ivec2(floor(mask_size.x / gl_NumWorkGroups.x),floor(mask_size.y / gl_NumWorkGroups.z));
        
    const int x_start = int(amount_per_group.x * gl_WorkGroupID.x);    
    const int y_start = int(amount_per_group.y * gl_WorkGroupID.z);

    const float ReduceAmount = FPARAMETERS.DECAY_RATE_PER_SECOND * FPARAMETERS.DELTA;    
        
    for(int x = x_start; x < x_start + amount_per_group.x; x++)
    {
        for(int y = y_start; y < y_start + amount_per_group.y; y++)
        {
            float current_val = imageLoad(OUT_FOLIAGE_BENDER,ivec2(x,y)).x;
            //fall of towards 0
            float reduced =  current_val - ReduceAmount;
            float newVal = max(imageLoad(IN_FOLIAGE_BENDER,ivec2(x,y)).x, reduced);
    
            imageStore(OUT_FOLIAGE_BENDER, ivec2(x,y), vec4(newVal));
        }
    }    
}