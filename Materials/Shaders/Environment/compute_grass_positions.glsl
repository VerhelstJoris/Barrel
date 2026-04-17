#[compute]
#version 450
#extension GL_NV_compute_shader_derivatives : enable

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// the heightmap texture, used to sample the height
//layout(binding = 0, set = 0, rgba32f) uniform restrict readonly image2D HEIGHTMAP_TEXTURE;
//layout(binding = 1, set = 0, float) uniform restrict readonly float VERTEX_SPACING;

//layout(std430, binding = 0) restrict buffer CommandBuffer { int data[]; } COMMAND_BUFFER;


// output position array
layout(set = 0, binding = 0, std430) restrict buffer Positions {
    float data[];
}
OutPositions;

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

// The code we want to execute in each invocation
void main() 
{
   // point to start trying with
	//var packedArr : PackedFloat32Array = PackedFloat32Array([0.027,0.0,1.0,2.331,0.0,1.0,0.0,0.0,-1.0,0.0,0.027,-3.764])

    //OUTPUTGRASSPOSITIONS.data[12] = float[12](0.027,0.0,1.0,2.331,0.0,1.0,0.0,0.0,-1.0,0.0,0.027,-3.764);
   OutPositions.data[0]= 0.027;
   OutPositions.data[1]= 0.0;
   OutPositions.data[2]= 1.0;
   OutPositions.data[3]= 2.231;
   OutPositions.data[4]= 0.0;
   OutPositions.data[5]= 1.0;
   OutPositions.data[6]= 0.0;
   OutPositions.data[7]= 0.0;
   OutPositions.data[8]= -1.0;
   OutPositions.data[9]= 0.0;
   OutPositions.data[10]= 0.027;
   OutPositions.data[11]= -3.764;

}