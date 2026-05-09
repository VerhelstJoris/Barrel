#[compute]
#version 450
#extension GL_NV_compute_shader_derivatives : enable

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
        
// the terrain heights at specific pixels of the terrain height texture, to be interpolated for individual positions
layout(set = 0, binding = 0, std430) readonly buffer HeightPositions {
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

    float MIN_BLADE_SCALE;

} PARAMETERS;


layout(set = 0,binding = 4, rgba32f) uniform restrict readonly image2D FOLIAGE_MASK;

float biLerp(float a, float b, float c, float d, float s, float t)
{
    float x = mix(a, b, t);
    float y = mix(c, d, t);
    return mix(x, y, s);
}        
        
float get_height_at_chunk_pos(vec2 chunk_pos, float A, float B, float C, float D)
{
    // Chunk pos is a value between [0 0] and [1 1]   
    // A = [0 0]
    // B = [0 1]
    // C = [1 0]
    // D = [1 1]
            
    float XLerp1 = mix(A,B,chunk_pos.x);
    float XLerp2 = mix(C,D,chunk_pos.x);    
    return mix(XLerp1,XLerp2,chunk_pos.y);
}
        
float get_scale(vec2 chunk_pos, ivec2 image_size, float max_size)
{
    vec2 normalized_final_pos = chunk_pos / max_size;
    ivec2 image_pos = ivec2(normalized_final_pos * image_size);
    return imageLoad(FOLIAGE_MASK, image_pos).r;    
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
        
    vec2 half_offset = vec2(PARAMETERS.TERRAIN_VERTEX_SPACING * gl_NumWorkGroups.x * 0.5, PARAMETERS.TERRAIN_VERTEX_SPACING * gl_NumWorkGroups.z * 0.5);
    float x_group_offset = PARAMETERS.TERRAIN_VERTEX_SPACING * gl_WorkGroupID.x - half_offset.x;
    float z_group_offset = PARAMETERS.TERRAIN_VERTEX_SPACING * gl_WorkGroupID.z - half_offset.y;
        
        
    float x,z, group_x, group_z, final_x, final_z, scale, random_rot_x, random_rot_y;
    vec2 final_pos;
    mat3 rot_scale_matrix;
            
    float height_A, height_B, height_C, height_D;
    height_A = HEIGHT_DATA.data[gl_WorkGroupID.x * (gl_NumWorkGroups.x +1) + gl_WorkGroupID.z];
    height_B = HEIGHT_DATA.data[(gl_WorkGroupID.x +1) * (gl_NumWorkGroups.x +1) + gl_WorkGroupID.z];
    height_C = HEIGHT_DATA.data[gl_WorkGroupID.x * (gl_NumWorkGroups.x +1) + (gl_WorkGroupID.z +1)];
    height_D = HEIGHT_DATA.data[(gl_WorkGroupID.x +1) * (gl_NumWorkGroups.x +1) + (gl_WorkGroupID.z +1)];

    ivec2 mask_size = imageSize(FOLIAGE_MASK);
    float max_length = gl_NumWorkGroups.x * PARAMETERS.TERRAIN_VERTEX_SPACING;    
    float x_offset_rand, z_offset_rand;    
        
    const int total_work_groups = int(gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z);
    const int group_offset = int((gl_WorkGroupID.x * gl_NumWorkGroups.x * rows * rows) + (gl_WorkGroupID.z * rows * rows) ) * 12;
            
    for(int row_ID = 0; row_ID < rows; row_ID++)
    {
        x = row_ID * Offset;
        for(int col_ID = 0; col_ID < rows; col_ID++)
        {
            z = col_ID * Offset;
            x_offset_rand = (fract(random2D(vec2(z,x)) * PARAMETERS.MAX_BLADE_RANDOM_OFFSET));   
            group_x = mod(x + x_offset_rand, PARAMETERS.TERRAIN_VERTEX_SPACING);
            final_x = group_x + x_group_offset;
                    
            z_offset_rand = (fract(random2D(vec2(final_x,z)) * PARAMETERS.MAX_BLADE_RANDOM_OFFSET));
            group_z = mod(z + z_offset_rand,PARAMETERS.TERRAIN_VERTEX_SPACING);
            final_z = group_z + z_group_offset;
    
            final_pos = vec2(final_x, final_z);
            scale = get_scale(final_pos + half_offset - vec2(x_offset_rand, z_offset_rand), mask_size, max_length);
                
            if(scale < PARAMETERS.MIN_BLADE_SCALE)
            {
                continue;
            }
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
    
            GRASS_TRANSFORMS.data[7 + id_offset]= get_height_at_chunk_pos(vec2(group_x, group_z) / PARAMETERS.TERRAIN_VERTEX_SPACING, height_A, height_B, height_C, height_D);   // Y-POS
    
            GRASS_TRANSFORMS.data[8 + id_offset]=  rot_scale_matrix[2][0];
            GRASS_TRANSFORMS.data[9 + id_offset]=  rot_scale_matrix[2][1];
            GRASS_TRANSFORMS.data[10 + id_offset]= rot_scale_matrix[2][2];
    
            GRASS_TRANSFORMS.data[11 + id_offset]= final_z;     // Z-POS
    
            current_blade++;
        }
    }
        
    COMMAND_BUFFER.data[1] = int(total_work_groups * current_blade);
}