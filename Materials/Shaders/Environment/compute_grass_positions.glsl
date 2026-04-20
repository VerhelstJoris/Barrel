#[compute]
#version 450
#extension GL_NV_compute_shader_derivatives : enable

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// the heightmap texture, used to sample the height
layout(binding = 0, set = 0, rgba32f) uniform restrict readonly image2D HEIGHTMAP_TEXTURE;

// multimesh data buffer allowing us to directly edit the amount of instances from the compute shader
layout(set = 0, binding = 1, std430) restrict buffer Transforms {
    float data[];
}
GRASS_TRANSFORMS;

// multimesh command buffer allowing us to directly edit the amount of instances from the compute shader
layout(std430,set = 0, binding = 2) restrict buffer CommandBuffer { int data[]; } COMMAND_BUFFER;

layout(set = 0, binding = 3, std430) restrict buffer Parameters {
    float TERRAIN_VERTEX_SPACING;
    float TERRAIN_HEIGHT;

    float TARGET_DENSITY;
    float MAX_BLADE_RANDOM_OFFSET;
} PARAMETERS;

//Color Terrain3DData::get_pixel(const MapType p_map_type, const Vector3 &p_global_position) const {
//	if (p_map_type < 0 || p_map_type >= TYPE_MAX) {
//		LOG(ERROR, "Specified map type out of range");
//		return COLOR_NAN;
//	}
//	Vector2i region_loc = get_region_location(p_global_position);
//	const Terrain3DRegion *region = get_region_ptr(region_loc);
//	if (!region) {
//		return COLOR_NAN;
//	}
//	if (region->is_deleted()) {
//		return COLOR_NAN;
//	}
//	Vector2i global_offset = region_loc * _region_size;
//	Vector3 descaled_pos = p_global_position / _vertex_spacing;
//	Vector2i img_pos = Vector2i(descaled_pos.x - global_offset.x, descaled_pos.z - global_offset.y);
//	img_pos = img_pos.clamp(V2I_ZERO, V2I(_region_size - 1));
//	Image *map = region->get_map_ptr(p_map_type);
//	if (map) {
//		return map->get_pixelv(img_pos);
//	} else {
//		return COLOR_NAN;
//	}
//}

//real_t Terrain3DData::get_height(const Vector3 &p_global_position) const {
//	Vector3 pos = p_global_position;
//	const real_t &step = _vertex_spacing;
//	pos.y = 0.f;
//	// Round to nearest vertex
//	Vector3 pos_round = pos.snapped(Vector3(step, 0.f, step));
//	// If requested position is close to a vertex, return its height
//	if ((pos - pos_round).length_squared() < 0.0001f) {
//		return get_pixel(TYPE_HEIGHT, pos).r;
//	} else {
//		// Otherwise, bilinearly interpolate 4 surrounding vertices
//		Vector3 pos00 = Vector3(floor(pos.x / step) * step, 0.f, floor(pos.z / step) * step);
//		real_t ht00 = get_pixel(TYPE_HEIGHT, pos00).r;
//		Vector3 pos01 = pos00 + Vector3(0.f, 0.f, step);
//		real_t ht01 = get_pixel(TYPE_HEIGHT, pos01).r;
//		Vector3 pos10 = pos00 + Vector3(step, 0.f, 0.f);
//		real_t ht10 = get_pixel(TYPE_HEIGHT, pos10).r;
//		Vector3 pos11 = pos00 + Vector3(step, 0.f, step);
//		real_t ht11 = get_pixel(TYPE_HEIGHT, pos11).r;
//		return bilerp(ht00, ht01, ht10, ht11, pos00, pos11, pos);
//	}
//}

float get_height(vec2 pos)
{
   return 0.0;
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
    float Rows = sqrt(PARAMETERS.TARGET_DENSITY);    

    const float Offset = (1.0/Rows);
    int current_blade = 0;

    for(int row_ID = 0; row_ID < Rows; row_ID++)
    {
        float x = row_ID * Offset;
        for(int col_ID = 0; col_ID < Rows; col_ID++)
        {
            float z = col_ID * Offset;
            float final_x = fract(x + random2D(vec2(z,x)) * PARAMETERS.MAX_BLADE_RANDOM_OFFSET); 
            float final_z = fract(z + random2D(vec2(final_x,z)) * PARAMETERS.MAX_BLADE_RANDOM_OFFSET); 
                    
            vec2 final_pos = vec2(final_x, final_z);
            float scale =  1.0;
            float random_rot = random2D(final_pos);
            int id_offset = current_blade * 12;
                
            highp mat3 rot_scale_matrix = mat3(scale) * rot_y(random_rot);
                
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

    COMMAND_BUFFER.data[1] = current_blade;
}