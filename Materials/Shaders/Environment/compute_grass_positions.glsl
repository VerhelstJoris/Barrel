#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

// the heightmap texture, used to sample the height
layout(binding = 0, set = 0, rgba32f) uniform restrict readonly image2D HEIGHTMAP_TEXTURE;


real_t Terrain3DData::get_height(const Vector3 &p_global_position) const {
	Vector3 pos = p_global_position;
	const real_t &step = _vertex_spacing;
	pos.y = 0.f;
	// Round to nearest vertex
	Vector3 pos_round = pos.snapped(Vector3(step, 0.f, step));
	// If requested position is close to a vertex, return its height
	if ((pos - pos_round).length_squared() < 0.0001f) {
		return get_pixel(TYPE_HEIGHT, pos).r;
	} else {
		// Otherwise, bilinearly interpolate 4 surrounding vertices
		Vector3 pos00 = Vector3(floor(pos.x / step) * step, 0.f, floor(pos.z / step) * step);
		real_t ht00 = get_pixel(TYPE_HEIGHT, pos00).r;
		Vector3 pos01 = pos00 + Vector3(0.f, 0.f, step);
		real_t ht01 = get_pixel(TYPE_HEIGHT, pos01).r;
		Vector3 pos10 = pos00 + Vector3(step, 0.f, 0.f);
		real_t ht10 = get_pixel(TYPE_HEIGHT, pos10).r;
		Vector3 pos11 = pos00 + Vector3(step, 0.f, step);
		real_t ht11 = get_pixel(TYPE_HEIGHT, pos11).r;
		return bilerp(ht00, ht01, ht10, ht11, pos00, pos11, pos);
	}
}

// The code we want to execute in each invocation
void main() 
{
}