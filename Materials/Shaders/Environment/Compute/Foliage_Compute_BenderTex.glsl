#[compute]
#version 450
#extension GL_NV_compute_shader_derivatives : enable

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;


layout(set = 0,binding = 0, rgba8) uniform restrict readonly image2D IN_FOLIAGE_BENDER;

layout(set = 0,binding = 1, rgba8) uniform restrict image2D OUT_FOLIAGE_BENDER;

//layout(set = 0,binding = 5, r8) uniform restrict readonly image2D FOLIAGE_MASK;
        
void main() 
{
    const int group_id_arr =  int((gl_WorkGroupID.x * gl_NumWorkGroups.x) + gl_WorkGroupID.z);

    const ivec2 mask_size = imageSize(IN_FOLIAGE_BENDER);
    const ivec2 amount_per_group = ivec2(floor(mask_size.x / gl_NumWorkGroups.x),floor(mask_size.y / gl_NumWorkGroups.y));
        
    const int x_start = int(amount_per_group.x * gl_WorkGroupID.x);    
    const int y_start = int(amount_per_group.y * gl_WorkGroupID.y);

    for(int x = x_start; x < x_start + amount_per_group.x; x++)
    {
        for(int y = y_start; y < y_start + amount_per_group.y; y++)
        {
           imageStore(OUT_FOLIAGE_BENDER, ivec2(x,y), max(imageLoad(IN_FOLIAGE_BENDER,ivec2(x,y)),imageLoad(OUT_FOLIAGE_BENDER,ivec2(x,y)) ));  
        }
    }    
}