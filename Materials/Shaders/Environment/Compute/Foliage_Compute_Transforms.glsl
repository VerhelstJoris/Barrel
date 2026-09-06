#[compute]
#version 450
#extension GL_NV_compute_shader_derivatives: enable

layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// the terrain heights at specific pixels of the terrain height texture, to be interpolated for individual positions
layout (set = 0, binding = 0, std430) readonly buffer HeightPositions {
	float data[];
}
HEIGHT_DATA;

// multimesh data buffer allowing us to directly edit the amount of instances from the compute shader
layout (set = 0, binding = 1, std430) writeonly buffer Transforms {
	vec4 data[];
}
GRASS_TRANSFORMS;

// array detailing how many grassblades are actually present in a specific         
layout (set = 0, binding = 2, std430) writeonly buffer BladeAmounts {
	int data[];
} BLADESPERGROUP;
		
layout (set = 0, binding = 3, std430) restrict readonly buffer FParameters {
	float TERRAIN_VERTEX_SPACING;
	
	float TARGET_DENSITY;
	float MAX_BLADE_RANDOM_OFFSET;
	float MAX_BLADE_TILT_RAD;

	float MIN_BLADE_SCALE;
	
	float DIST_THRESH_CLOSE;
	float DIST_THRESH_MED;
	float DIST_THRESH_FAR;
	
	float WORLD_ORIGIN_X;
	float WORLD_ORIGIN_Z;
	float MASK_TEXELS_PER_M;
	
	float LOD_SKIP_FADE_M;
	float FRONTIER_FADE_M;
} FPARAMETERS;

layout (set = 0, binding = 4, std430) restrict readonly buffer IParameters
{
	int MAX_BLADES_PER_GROUP;
	
	int HEIGHT_STRIDE;
	
	int SEGMENT_ID_OFFSET;
	
	int DISPATCH_WIDTH;
	int WORLD_CELLS;
	int MASK_RES;
	int NUM_SEGMENTS;
} IPARAMETERS;

layout (set = 0, binding = 5, r8) uniform restrict readonly image2D FOLIAGE_MASK;

layout (set = 0, binding = 6, std430) restrict readonly buffer PlayerData
{
	float X_POS;
	float Y_POS;
	float Z_POS;
	
	float X_ROT;
	float Y_ROT;
	float Z_ROT;
	
	float FRONTIER_RADIUS;
} PLAYERDATA;


// Priority-ordered list of the segments to draw, one int per segment: the global cell x in the low 16 bits and z in the high 16. 
layout (set = 0, binding = 7, std430) restrict readonly buffer SegmentsToDraw {
	int data[];
} SEGMENTSTODRAW;

const float TAU = 6.28318530718;

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
	
	float XLerp1 = mix(A, B, segment_pos.x);
	float XLerp2 = mix(C, D, segment_pos.x);
	return mix(XLerp1, XLerp2, segment_pos.y);
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
		
// layout id over small squares of 2X2 with following ID order
//   3   1
//   0   2
// A blade is skipped once the distance threshold id exceeds its own, so id 0 drops first and id 3 never drops. 
int grass_id_2x2(int x_id, int z_id)
{
	return ((x_id % 2) * 2) + ((z_id % 2) * (((1 - (x_id % 2)) * 4) - 1));
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
	const int blade_limit = max(IPARAMETERS.MAX_BLADES_PER_GROUP, 1);
	
	int density_rows = int(ceil(FPARAMETERS.TARGET_DENSITY * FPARAMETERS.TERRAIN_VERTEX_SPACING));
	
	int capacity_rows = int(floor(sqrt(float(blade_limit))));
	if (capacity_rows * capacity_rows > blade_limit)
	{
		capacity_rows -= 1;
	}
	
	// rows <= capacity_rows, so rows*rows <= slot_limit. The shader cannot ask for
	// more slots than exist no matter what the CPU sends.
	const int rows = clamp(density_rows, 1, max(capacity_rows, 1));
	const int blades_this_segment = rows * rows;
	
	const float cell_size = FPARAMETERS.TERRAIN_VERTEX_SPACING / float(rows);
	
	// Jitter stays in METRES as before, but capped at one cell so a blade can never leave its own cell. T
	const float max_offset = min(FPARAMETERS.MAX_BLADE_RANDOM_OFFSET, cell_size);
	
	int current_blade = 0;
	
	// The segment's minimum corner in WORLD space
	const float x_group_offset = FPARAMETERS.WORLD_ORIGIN_X + FPARAMETERS.TERRAIN_VERTEX_SPACING * segment_coord.x;
	const float z_group_offset = FPARAMETERS.WORLD_ORIGIN_Z + FPARAMETERS.TERRAIN_VERTEX_SPACING * segment_coord.y;
	
	float group_x, group_z, final_x, final_z, scale, random_rot_x, random_rot_y, random_rot_z;
	vec2 final_pos;
	
	// corners of this segment in the global height buffer
	const float height_A = height_at(segment_coord.x, segment_coord.y);
	const float height_B = height_at(segment_coord.x + 1, segment_coord.y);
	const float height_C = height_at(segment_coord.x, segment_coord.y + 1);
	const float height_D = height_at(segment_coord.x + 1, segment_coord.y + 1);
	
	const int group_id = int(gl_WorkGroupID.x * gl_NumWorkGroups.z) + int(gl_WorkGroupID.z);
	const int group_offset_vec4 = group_id * blade_limit * 3;
	
	const vec2 player_xz = vec2(PLAYERDATA.X_POS, PLAYERDATA.Z_POS);
	
	// Cheap reject for the whole segment. 
	const vec2 to_cam = player_xz - vec2(x_group_offset, z_group_offset);
	const float d_ring_corner = max(abs(to_cam.x), abs(to_cam.y));
	const int frontier_visible = (d_ring_corner - FPARAMETERS.TERRAIN_VERTEX_SPACING) < PLAYERDATA.FRONTIER_RADIUS ? 1 : 0;
	
	for (int row_ID = 0; row_ID < rows; row_ID++)
	{
		for (int col_ID = 0; col_ID < rows; col_ID++)
		{
			int mask = frontier_visible;
			
			const vec2 cell_world = vec2(
			x_group_offset + (float(row_ID) + 0.5) * cell_size,
			z_group_offset + (float(col_ID) + 0.5) * cell_size);
			
			group_x = (float(row_ID) + 0.5) * cell_size
			+ (random2D(cell_world) - 0.5) * max_offset;
			group_z = (float(col_ID) + 0.5) * cell_size
			+ (random2D(cell_world + vec2(17.31, 5.77)) - 0.5) * max_offset;
			
			final_x = group_x + x_group_offset;
			final_z = group_z + z_group_offset;
			
			final_pos = vec2(final_x, final_z);
			
			// Distance to THIS BLADE, not to the segment
			const float blade_dist = length(final_pos - player_xz);
			
			// Per-blade frontier fade, for the same reason. d_ring is Chebyshev
			// because the fill walks square rings, so a segment on the diagonal
			// sits up to sqrt(2) further out than the frontier radius.
			const float d_ring = max(abs(final_x - PLAYERDATA.X_POS), abs(final_z - PLAYERDATA.Z_POS));
			const float frontier_fade = clamp(
				(PLAYERDATA.FRONTIER_RADIUS - d_ring) / max(FPARAMETERS.FRONTIER_FADE_M, 0.001), 0.0, 1.0);
			mask &= frontier_fade > 0.02 ? 1 : 0;
			

			const int blade_id = grass_id_2x2(segment_coord.x * rows + row_ID,
			                                  segment_coord.y * rows + col_ID);
			const float blade_dist_dithered = blade_dist + (random2D(final_pos * 3.71) - 0.5) * FPARAMETERS.LOD_SKIP_FADE_M;
			const int skip_id = (blade_dist_dithered > FPARAMETERS.DIST_THRESH_CLOSE ? 1 : 0)
			+ (blade_dist_dithered > FPARAMETERS.DIST_THRESH_MED ? 1 : 0)
			+ (blade_dist_dithered > FPARAMETERS.DIST_THRESH_FAR ? 1 : 0);
			mask &= blade_id < skip_id ? 0 : 1;
			
			// The threshold that will remove THIS blade, so it can shrink into its own removal rather than vanishing at full size.
			const float death_dist = blade_id == 0 ? FPARAMETERS.DIST_THRESH_CLOSE : blade_id == 1 ? FPARAMETERS.DIST_THRESH_MED : blade_id == 2 ? FPARAMETERS.DIST_THRESH_FAR : FPARAMETERS.DIST_THRESH_FAR * 1000.0;
			const float lod_fade = clamp((death_dist - blade_dist_dithered) / max(FPARAMETERS.LOD_SKIP_FADE_M, 0.001), 0.0, 1.0);
			
			// sample the mask on the unjittered cell centre, so the jitter cannot alias the mask edges
			scale = get_scale(cell_world);
			
			mask &= scale >= FPARAMETERS.MIN_BLADE_SCALE ? 1 : 0;
			
			scale *= lod_fade * frontier_fade;
			
			random_rot_x = (random2D(final_pos + 1.1546461) - 0.5) * 2.0 * FPARAMETERS.MAX_BLADE_TILT_RAD;
			random_rot_y = random2D(final_pos) * TAU;
			random_rot_z = 0;
			
			int base_index = group_offset_vec4 + current_blade * 3;
			
			float sx = sin(random_rot_x);
			float cx = cos(random_rot_x);
			
			float sy = sin(random_rot_y);
			float cy = cos(random_rot_y);
			
			vec3 basisX = vec3(cy, 0.0, -sy) * scale;
			vec3 basisY = vec3(sx * sy, cx, sx * cy) * scale;
			vec3 basisZ = vec3(cx * sy, -sx, cx * cy) * scale;
			
			float posX = final_x;
			float posY = get_height_at_segment_pos(vec2(group_x, group_z) / FPARAMETERS.TERRAIN_VERTEX_SPACING, height_A, height_B, height_C, height_D);
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
	const int group_id_arr = int(int(gl_WorkGroupID.x * gl_NumWorkGroups.z) + gl_WorkGroupID.z);
	
	if (group_id_arr >= IPARAMETERS.NUM_SEGMENTS)
	{
		BLADESPERGROUP.data[group_id_arr] = 0;
		return;
	}
	
	// One packed int per segment. Mask the high half as well: >> on a signed int is
	const int packed_coord = SEGMENTSTODRAW.data[group_id_arr + IPARAMETERS.SEGMENT_ID_OFFSET];
	const ivec2 segment_coord = ivec2(packed_coord & 0xFFFF, (packed_coord >> 16) & 0xFFFF);
	
	int workgroup_blades = fill_world_segment(segment_coord);
	
	BLADESPERGROUP.data[group_id_arr] = workgroup_blades;
}
