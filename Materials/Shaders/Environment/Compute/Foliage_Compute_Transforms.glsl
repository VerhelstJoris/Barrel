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

// array detailing how many grassblades are actually present in a specific         
layout(set = 0, binding = 2, std430) writeonly buffer BladeAmounts {
	int data[];
} BLADESPERGROUP;
		
layout(set = 0, binding = 3, std430) restrict readonly buffer FParameters {
	float TERRAIN_VERTEX_SPACING;

	float TARGET_DENSITY;
	float MAX_BLADE_RANDOM_OFFSET;
	float MAX_BLADE_TILT_RAD;

	float MIN_BLADE_SCALE;
		
	float DIST_THRESH_CLOSE;    
	float DIST_THRESH_MED;    
	float DIST_THRESH_FAR;    
} FPARAMETERS;
		
layout(set = 0, binding =4, std430) restrict readonly buffer IParameters
{
	int MAX_BLADES_PER_GROUP;
	int AMOUNT_OF_SEGMENTS_IN_CHUNK_PER_DIM;
} IPARAMETERS;

layout(set = 0,binding = 5, r8) uniform restrict readonly image2D FOLIAGE_MASK;
		
layout(set = 0, binding = 6, std430) restrict readonly buffer PlayerData
{
   float X_POS;     
   float Y_POS;     
   float Z_POS;
		
   float X_ROT;
   float Y_ROT;
   float Z_ROT;
} PLAYERDATA;
		
// array detailing which chunk segments should actually be drawn, size is double the amount of workgroups for [x,z] section coordintate      
layout(set = 0, binding = 7, std430) restrict readonly buffer SegmentsToDraw {
int data[];
} SEGMENTSTODRAW;
		
layout(set = 0,binding = 8) uniform sampler2D FOLIAGE_BENDER;

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
    //
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

float closest_if_between(float val, float low, float high)
{
	if (val > low && val < high)
	{
		return val < ((high - low) / 2.0 + low) ? low : high;
	}
		
	return val;
}
		
float get_rot_biased_towards_player(vec2 blade_pos)
{
   float rand_angle = random2D(blade_pos) * 3.14159;    // RANGE [-PI, PI]
   return rand_angle;     
   vec2 target_dir = vec2(PLAYERDATA.X_POS - blade_pos.x, PLAYERDATA.Z_POS - blade_pos.y);
		
   float angle_towards_player = atan(target_dir.y, target_dir.x);   // range [-PI, PI]
   float angle_away_from_player = angle_towards_player + 3.14159;  // range [0, 2 * PI]   
		
   //if our random angle is similar to the angle towards the player, angle it away a bit     
   const float offset = 0.5;
   rand_angle = closest_if_between(rand_angle,angle_towards_player - offset, angle_towards_player + offset);
   rand_angle = closest_if_between(rand_angle,angle_away_from_player - offset, angle_away_from_player + offset);
		
   return rand_angle;
}

bool should_skip_grass_id(int x_id ,int z_id, int dist_threshold_id)
{
   // layout id over small squares of 2X2 with following ID order
   //   3   1        
   //   0   2   
   // then skip the ID if it's smaller than the dist_threshold_id       
   return ((x_id %2) * 2) + ( (z_id %2) * (((1 - (x_id %2)) *4) -1)) < dist_threshold_id;
}
        

int fill_chunk_segment(ivec2 segment_local_coord)
{
    float rows = FPARAMETERS.TARGET_DENSITY * FPARAMETERS.TERRAIN_VERTEX_SPACING;
    
    const float Offset = (1.0/FPARAMETERS.TARGET_DENSITY);
    
    int current_blade =0;
    int id_offset =0;
    
    const float chunk_size_dim = FPARAMETERS.TERRAIN_VERTEX_SPACING * IPARAMETERS.AMOUNT_OF_SEGMENTS_IN_CHUNK_PER_DIM;    
    const float half_chunk_size_dim =chunk_size_dim * 0.5;
    const float x_group_offset = FPARAMETERS.TERRAIN_VERTEX_SPACING * segment_local_coord.x - half_chunk_size_dim;
    const float z_group_offset = FPARAMETERS.TERRAIN_VERTEX_SPACING * segment_local_coord.y - half_chunk_size_dim;
    const vec2 half_offset = vec2(half_chunk_size_dim, half_chunk_size_dim);

    float x,z, group_x, group_z, final_x, final_z, scale, random_rot_x, random_rot_y, random_rot_z;
    vec2 final_pos;
    mat3 rot_scale_matrix;
    
    const float height_A = HEIGHT_DATA.data[segment_local_coord.x * (IPARAMETERS.AMOUNT_OF_SEGMENTS_IN_CHUNK_PER_DIM.x +1) + segment_local_coord.y];
    const float height_B = HEIGHT_DATA.data[(segment_local_coord.x +1) * (IPARAMETERS.AMOUNT_OF_SEGMENTS_IN_CHUNK_PER_DIM.x +1) + segment_local_coord.y];
    const float height_C = HEIGHT_DATA.data[segment_local_coord.x * (IPARAMETERS.AMOUNT_OF_SEGMENTS_IN_CHUNK_PER_DIM.x +1) + (segment_local_coord.y +1)];
    const float height_D = HEIGHT_DATA.data[(segment_local_coord.x +1) * (IPARAMETERS.AMOUNT_OF_SEGMENTS_IN_CHUNK_PER_DIM.x +1) + (segment_local_coord.y +1)];
    
    const ivec2 mask_size = imageSize(FOLIAGE_MASK);
    const float max_length = gl_NumWorkGroups.x * FPARAMETERS.TERRAIN_VERTEX_SPACING;
    float x_offset_rand, z_offset_rand;
    
    const int total_work_groups = int(gl_NumWorkGroups.x * gl_NumWorkGroups.z);
    const int group_id_arr =  int(int(gl_WorkGroupID.x * gl_NumWorkGroups.x) + gl_WorkGroupID.z);
    
    const int group_offset = int((gl_WorkGroupID.x * gl_NumWorkGroups.x * rows * rows) + (gl_WorkGroupID.z * rows * rows) ) * 12;
        
    //calculate the dist between the player and this segment    
    const float distance_segment_player =  length(vec2(PLAYERDATA.X_POS - x_group_offset, PLAYERDATA.Z_POS - z_group_offset));
    int skip_id = 0;    
    if(distance_segment_player > FPARAMETERS.DIST_THRESH_CLOSE)
    {
        skip_id = 1;
        if(distance_segment_player > FPARAMETERS.DIST_THRESH_MED)
        {
            skip_id = 2;
            if (distance_segment_player > FPARAMETERS.DIST_THRESH_FAR)
            {
                skip_id = 3;
            }
        }
    }

        
    for(int row_ID = 0; row_ID < rows; row_ID++)
    {
        x = row_ID * Offset;
        for(int col_ID = 0; col_ID < rows; col_ID++)
        {
            if(should_skip_grass_id(row_ID, col_ID, skip_id))
            {
               continue;     
            }

            z = col_ID * Offset;
            x_offset_rand = (fract(random2D(vec2(z,x)) * FPARAMETERS.MAX_BLADE_RANDOM_OFFSET));
            group_x = mod(x + x_offset_rand, FPARAMETERS.TERRAIN_VERTEX_SPACING);
            final_x = group_x + x_group_offset;
            
            z_offset_rand = (fract(random2D(vec2(final_x,z)) * FPARAMETERS.MAX_BLADE_RANDOM_OFFSET));
            group_z = mod(z + z_offset_rand,FPARAMETERS.TERRAIN_VERTEX_SPACING);
            final_z = group_z + z_group_offset;
            
            final_pos = vec2(final_x, final_z);
            vec2 uv_pos = final_pos + half_offset - vec2(x_offset_rand, z_offset_rand);
            scale = get_scale(uv_pos, mask_size, chunk_size_dim);
                
            if(scale < FPARAMETERS.MIN_BLADE_SCALE)
            {
                continue;
            }
                
            //random_rot_x = (random2D(final_pos + 1.1546461)  - 0.5) * 2.0 * FPARAMETERS.MAX_BLADE_TILT_RAD;
            random_rot_y = get_rot_biased_towards_player(final_pos);

            vec2 normalized_final_pos = uv_pos / chunk_size_dim;
            normalized_final_pos.x = 1.0 - normalized_final_pos.x;    
            random_rot_x = texture(FOLIAGE_BENDER, normalized_final_pos).r * 1.45;    
            //random_rot_y = 0;        

            random_rot_z =  0;
                
            rot_scale_matrix = mat3(scale) * rot_x(random_rot_x) * rot_y(random_rot_y) * rot_z(random_rot_z);
            
            id_offset = int( group_offset + (current_blade * 12) );
            
            // fill in the transforms    
            GRASS_TRANSFORMS.data[0 + id_offset]= rot_scale_matrix[0][0];
            GRASS_TRANSFORMS.data[1 + id_offset]= rot_scale_matrix[0][1];
            GRASS_TRANSFORMS.data[2 + id_offset]= rot_scale_matrix[0][2];
            
            GRASS_TRANSFORMS.data[3 + id_offset]= final_x ;     // X-POS
            
            GRASS_TRANSFORMS.data[4 + id_offset]= rot_scale_matrix[1][0];
            GRASS_TRANSFORMS.data[5 + id_offset]= rot_scale_matrix[1][1];
            GRASS_TRANSFORMS.data[6 + id_offset]= rot_scale_matrix[1][2];
            
            GRASS_TRANSFORMS.data[7 + id_offset]= get_height_at_chunk_pos(vec2(group_x, group_z) / FPARAMETERS.TERRAIN_VERTEX_SPACING, height_A, height_B, height_C, height_D);   // Y-POS
            
            GRASS_TRANSFORMS.data[8 + id_offset]=  rot_scale_matrix[2][0];
            GRASS_TRANSFORMS.data[9 + id_offset]=  rot_scale_matrix[2][1];
            GRASS_TRANSFORMS.data[10 + id_offset]= rot_scale_matrix[2][2];
            
            GRASS_TRANSFORMS.data[11 + id_offset]= final_z;     // Z-POS
            
            current_blade++;
        }
    }    
        
    return current_blade;
}        
        
// The code we want to execute in each invocation
void main() 
{
    const int group_id_arr =  int(int(gl_WorkGroupID.x * gl_NumWorkGroups.x) + gl_WorkGroupID.z);
        
    int workgroup_blades =0;
    ivec2 segment_coord =  ivec2(SEGMENTSTODRAW.data[group_id_arr*2], SEGMENTSTODRAW.data[(group_id_arr*2)+1]);
        
    workgroup_blades = workgroup_blades + fill_chunk_segment(segment_coord);
        
    BLADESPERGROUP.data[group_id_arr] = workgroup_blades;
}
        
