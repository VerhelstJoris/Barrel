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
	vec4 data[];
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
    float BLADE_ROT_TO_CAMERA_BIAS_NEAR;
    float BLADE_ROT_TO_CAMERA_BIAS_FAR;
    float BLADE_ROT_TO_CAMERA_MIN_DIST;
	float MIN_BLADE_SCALE;

	float DIST_THRESH_CLOSE;
	float DIST_THRESH_MED;
	float DIST_THRESH_FAR;

	float WORLD_ORIGIN_X;
	float WORLD_ORIGIN_Z;
	float MASK_TEXELS_PER_M;
} FPARAMETERS;
		
layout(set = 0, binding =4, std430) restrict readonly buffer IParameters
{
	int MAX_BLADES_PER_GROUP;

	int HEIGHT_STRIDE;

    int SEGMENT_ID_OFFSET;

	int DISPATCH_WIDTH;	
	int WORLD_CELLS;
	int MASK_RES;
	int NUM_SEGMENTS;
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
        
float biLerp(float a, float b, float c, float d, float s, float t)
{
	float x = mix(a, b, t);
	float y = mix(c, d, t);
	return mix(x, y, s);
}

float get_height_at_segment_pos(vec2 segment_pos, float A, float B, float C, float D)
{
	// segment_pos is a value between [0 0] and [1 1]
	// A = [0 0]
	// B = [0 1]
	// C = [1 0]
	// D = [1 1]

	float XLerp1 = mix(A,B,segment_pos.x);
	float XLerp2 = mix(C,D,segment_pos.x);
	return mix(XLerp1,XLerp2,segment_pos.y);
}

// One global mask over the whole world, sampled from a world position rather
// than a chunk-local one. No slicing, no per-chunk texture.
float get_scale(vec2 world_pos)
{
	vec2 relative = world_pos - vec2(FPARAMETERS.WORLD_ORIGIN_X, FPARAMETERS.WORLD_ORIGIN_Z);
	ivec2 texel = ivec2(floor(relative * FPARAMETERS.MASK_TEXELS_PER_M));
	texel = clamp(texel, ivec2(0), imageSize(FOLIAGE_MASK) - ivec2(1));
	return imageLoad(FOLIAGE_MASK, texel).r;
}
		
float random2D(vec2 uv) {
    uv = fract(uv * 0.3183099 + vec2(0.71, 0.113));
    uv *= 17.0;
    return fract(uv.x * uv.y * (uv.x + uv.y));
}

float closest_if_between(float val, float low, float high)
{
	if (val > low && val < high)
	{
		return val < ((high - low) / 2.0 + low) ? low : high;
	}
		
	return val;
}

float get_rot_biased_towards_player(vec2 blade_pos, float distance)
{
   float rand_angle = random2D(blade_pos) * 3.14159;    // RANGE [-PI, PI]
   vec2 target_dir = vec2(PLAYERDATA.X_POS - blade_pos.x, PLAYERDATA.Z_POS - blade_pos.y);

   float angle_towards_player = atan(target_dir.y, target_dir.x);   // range [-PI, PI]
   float angle_away_from_player = angle_towards_player + 3.14159;  // range [0, 2 * PI]

   //if our random angle is similar to the angle towards the player, angle it away a bit
   const float offset_alpha = smoothstep(FPARAMETERS.BLADE_ROT_TO_CAMERA_MIN_DIST, FPARAMETERS.BLADE_ROT_TO_CAMERA_MIN_DIST + 1.0, distance);
   const float offset = mix( FPARAMETERS.BLADE_ROT_TO_CAMERA_BIAS_NEAR, FPARAMETERS.BLADE_ROT_TO_CAMERA_BIAS_FAR, (distance / FPARAMETERS.DIST_THRESH_FAR)) * offset_alpha;
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

// Reads a world grid vertex, clamped so a segment on the world's far edge
// cannot walk off the end of the buffer when it fetches its +1 corners.
float height_at(int vx, int vz)
{
	int limit = IPARAMETERS.HEIGHT_STRIDE - 1;
	vx = clamp(vx, 0, limit);
	vz = clamp(vz, 0, limit);
	return HEIGHT_DATA.data[vx + vz * IPARAMETERS.HEIGHT_STRIDE];
}

int fill_world_segment(ivec2 segment_coord)
{
    float rows = FPARAMETERS.TARGET_DENSITY * FPARAMETERS.TERRAIN_VERTEX_SPACING;
    
    const float Offset = (1.0/FPARAMETERS.TARGET_DENSITY);
    
    int current_blade =0;

    // The segment's minimum corner in WORLD space. This is the line that was
    // wrong: it used to subtract half a chunk, because coordinates were
    // chunk-local and the chunk node sat at its own centre. Segment coords are
    // global now, so the only offset is the world's minimum corner.
    const float x_group_offset = FPARAMETERS.WORLD_ORIGIN_X + FPARAMETERS.TERRAIN_VERTEX_SPACING * segment_coord.x;
    const float z_group_offset = FPARAMETERS.WORLD_ORIGIN_Z + FPARAMETERS.TERRAIN_VERTEX_SPACING * segment_coord.y;

    float x,z, group_x, group_z, final_x, final_z, scale, random_rot_x, random_rot_y, random_rot_z;
    vec2 final_pos;

    // corners of this segment in the global height buffer
    const float height_A = height_at(segment_coord.x,     segment_coord.y);
    const float height_B = height_at(segment_coord.x + 1, segment_coord.y);
    const float height_C = height_at(segment_coord.x,     segment_coord.y + 1);
    const float height_D = height_at(segment_coord.x + 1, segment_coord.y + 1);

    float x_offset_rand, z_offset_rand;

    const int blades_per_group = int(rows * rows); // worst case
    const int group_id = int(gl_WorkGroupID.x * gl_NumWorkGroups.z) + int(gl_WorkGroupID.z);
    const int group_offset_vec4 = group_id * blades_per_group * 3;

    //calculate the dist between the player and this segment and see which should be skipped
    const float d =  length(vec2(PLAYERDATA.X_POS - x_group_offset, PLAYERDATA.Z_POS - z_group_offset));
    int skip_id = (d > FPARAMETERS.DIST_THRESH_CLOSE? 1 : 0)+ (d > FPARAMETERS.DIST_THRESH_MED? 1 : 0) + (d > FPARAMETERS.DIST_THRESH_FAR? 1 : 0);
        
    for(int row_ID = 0; row_ID < rows; row_ID++)
    {
        x = row_ID * Offset;
        for(int col_ID = 0; col_ID < rows; col_ID++)
        {
            int mask = 1;
            mask &= should_skip_grass_id(row_ID, col_ID, skip_id) ? 0 : 1;
                
            z = col_ID * Offset;
            x_offset_rand = (fract(random2D(vec2(z,x)) * FPARAMETERS.MAX_BLADE_RANDOM_OFFSET));
            group_x = mod(x + x_offset_rand, FPARAMETERS.TERRAIN_VERTEX_SPACING);
            final_x = group_x + x_group_offset;
            
            z_offset_rand = (fract(random2D(vec2(final_x,z)) * FPARAMETERS.MAX_BLADE_RANDOM_OFFSET));
            group_z = mod(z + z_offset_rand,FPARAMETERS.TERRAIN_VERTEX_SPACING);
            final_z = group_z + z_group_offset;
            
            final_pos = vec2(final_x, final_z);

            // sample the mask on the unjittered grid position, as before, so
            // the jitter cannot alias the mask edges
            vec2 mask_pos = final_pos - vec2(x_offset_rand, z_offset_rand);
            scale = get_scale(mask_pos);

            mask &= scale >= FPARAMETERS.MIN_BLADE_SCALE ? 1 : 0;

            random_rot_x = (random2D(final_pos + 1.1546461)  - 0.5) * 2.0 * FPARAMETERS.MAX_BLADE_TILT_RAD;
            random_rot_y = get_rot_biased_towards_player(final_pos, d);
            random_rot_z =  0;
                
            int base_index  = group_offset_vec4 + current_blade * 3;

            float sx = sin(random_rot_x);
            float cx = cos(random_rot_x);
    
            float sy = sin(random_rot_y);
            float cy = cos(random_rot_y);
                
            vec3 basisX = vec3(cy, 0.0, -sy) * scale;
            vec3 basisY = vec3(sx * sy, cx, sx * cy) * scale;
            vec3 basisZ = vec3(cx * sy, -sx, cx * cy) * scale;
    
            float posX = final_x;
            float posY = get_height_at_segment_pos( vec2(group_x, group_z) / FPARAMETERS.TERRAIN_VERTEX_SPACING, height_A, height_B, height_C, height_D);
            float posZ = final_z;
                
            // multiply by the mask    
            GRASS_TRANSFORMS.data[base_index + 0] = vec4(basisX, posX) * mask;
            GRASS_TRANSFORMS.data[base_index + 1] = vec4(basisY, posY) * mask;
            GRASS_TRANSFORMS.data[base_index + 2] = vec4(basisZ, posZ) * mask;
                
            current_blade += mask;
        }
    }    
        
    return current_blade;
}


// The code we want to execute in each invocation
void main()
{
    const int group_id_arr =  int(int(gl_WorkGroupID.x * gl_NumWorkGroups.z) + gl_WorkGroupID.z);
        
    if (group_id_arr >= IPARAMETERS.NUM_SEGMENTS)
    {
        BLADESPERGROUP.data[group_id_arr] = 0;
        return;
    }

    const int offset_group_id = (group_id_arr + IPARAMETERS.SEGMENT_ID_OFFSET) *2;
    const ivec2 segment_coord =  ivec2(SEGMENTSTODRAW.data[offset_group_id], SEGMENTSTODRAW.data[offset_group_id+1]);

    int workgroup_blades = fill_world_segment(segment_coord);

    BLADESPERGROUP.data[group_id_arr] = workgroup_blades;
}
