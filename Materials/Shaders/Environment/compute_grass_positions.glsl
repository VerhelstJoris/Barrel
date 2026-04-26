#[compute]
#version 450
#extension GL_NV_compute_shader_derivatives : enable

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// the heightmap texture, used to sample the height
layout(binding = 0, set = 0, rgba32f) uniform restrict readonly image2D HEIGHTMAP_TEXTURE;

// the terrain heights at specific pixels of the terrain height texture, to be interpolated for individual positions
layout(set = 0, binding = 0, std430) writeonly buffer HeightPositions {
float data[];
}
HEIGHT_DATA;        
        
// multimesh data buffer allowing us to directly edit the amount of instances from the compute shader
layout(set = 0, binding = 1, std430) writeonly buffer Transforms {
    float data[];
}
GRASS_TRANSFORMS;

// multimesh command buffer allowing us to directly edit the amount of instances from the compute shader
layout(std430,set = 0, binding = 2) restrict writeonly buffer CommandBuffer { int data[]; } COMMAND_BUFFER;

layout(set = 0, binding = 3, std430) restrict buffer Parameters {
    float TERRAIN_VERTEX_SPACING;
    float TERRAIN_HEIGHT;

    float TARGET_DENSITY;
    float MAX_BLADE_RANDOM_OFFSET;
    float MAX_BLADE_TILT_RAD;    
} PARAMETERS;
        
float get_height(vec2 pos)
{
   return 0.0;
}
        
float get_scale(vec2 pos)
{
   return 1.0;
}
        
float random2D(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}
        
mat3 rot_z(float angle) {
    float s = sin(angle);
    float c = cos(angle);

    return mat3(
    c, s, 0.0,
    -s, c, 0.0,
    0.0, 0.0, 1.0);
}

mat3 rot_y(float angle) 
{
    float s = sin(angle);
    float c = cos(angle);

    return mat3(
    c, 0.0, -s,
    0.0, 1.0, 0.0,
    s, 0.0, c);
}        
        
mat3 rot_x(float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    
    return mat3(
    1.0, 0.0, 0.0,
    0.0, c, s,
    0.0, -s, c);
}
        
// The code we want to execute in each invocation
void main() 
{
    float rows = PARAMETERS.TARGET_DENSITY * PARAMETERS.TERRAIN_VERTEX_SPACING;    

    const float Offset = (1.0/PARAMETERS.TARGET_DENSITY);
        
    int current_blade =0;
    int id_offset =0;
            
    float x_group_offset = PARAMETERS.TERRAIN_VERTEX_SPACING * gl_WorkGroupID.x;
    float z_group_offset = PARAMETERS.TERRAIN_VERTEX_SPACING * gl_WorkGroupID.z;
        
    float x,z, final_x, final_z, scale, random_rot_x, random_rot_y;
    vec2 final_pos;
    mat3 rot_scale_matrix;

    const int total_work_groups = int(gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z);
    const int group_offset = int((gl_WorkGroupID.x * gl_NumWorkGroups.x * rows * rows) + (gl_WorkGroupID.z * rows * rows) ) * 12;
            
    for(int row_ID = 0; row_ID < rows; row_ID++)
    {
        x = row_ID * Offset;
        for(int col_ID = 0; col_ID < rows; col_ID++)
        {
            z = col_ID * Offset;
            final_x = x + (fract(random2D(vec2(z,x)) * PARAMETERS.MAX_BLADE_RANDOM_OFFSET)) + x_group_offset;
            final_z = z + (fract(random2D(vec2(final_x,z)) * PARAMETERS.MAX_BLADE_RANDOM_OFFSET)) + z_group_offset;
    
            final_pos = vec2(final_x, final_z);
            scale = get_scale(final_pos);
            random_rot_x = (random2D(final_pos + 1.1546461)  - 0.5) * 2.0 * PARAMETERS.MAX_BLADE_TILT_RAD;
            random_rot_y = random2D(final_pos) * 3.14159;
            rot_scale_matrix = mat3(scale) * rot_x(random_rot_x) * rot_y(random_rot_y);
    
            id_offset = int( group_offset + (current_blade * 12) );
    
            // fill in the transforms    
            GRASS_TRANSFORMS.data[0 + id_offset]= rot_scale_matrix[0][0];
            GRASS_TRANSFORMS.data[1 + id_offset]= rot_scale_matrix[0][1];
            GRASS_TRANSFORMS.data[2 + id_offset]= rot_scale_matrix[0][2];
    
            GRASS_TRANSFORMS.data[3 + id_offset]= final_x ;     // X-POS
    
            GRASS_TRANSFORMS.data[4 + id_offset]= rot_scale_matrix[1][0];
            GRASS_TRANSFORMS.data[5 + id_offset]= rot_scale_matrix[1][1];
            GRASS_TRANSFORMS.data[6 + id_offset]= rot_scale_matrix[1][2];
    
            GRASS_TRANSFORMS.data[7 + id_offset]= get_height(final_pos);   // Y-POS
    
            GRASS_TRANSFORMS.data[8 + id_offset]=  rot_scale_matrix[2][0];
            GRASS_TRANSFORMS.data[9 + id_offset]=  rot_scale_matrix[2][1];
            GRASS_TRANSFORMS.data[10 + id_offset]= rot_scale_matrix[2][2];
    
            GRASS_TRANSFORMS.data[11 + id_offset]= final_z;     // Z-POS
    
            current_blade++;
        }
    }
        
    COMMAND_BUFFER.data[1] = int(total_work_groups * current_blade);
}