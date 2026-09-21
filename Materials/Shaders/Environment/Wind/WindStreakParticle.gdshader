shader_type particles;
// position is integrated here rather than by the engine, because the height snap and the push out both need the final say on where a particle ends up
render_mode disable_velocity, disable_force;

uniform sampler2D sdf_map : filter_linear, repeat_disable;
uniform vec2 sdf_origin = vec2(0.0);
uniform vec2 sdf_size = vec2(512.0);

uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_speed = 4.0;
uniform float deflect_radius = 12.0;
uniform float turn_rate = 4.0;
uniform float skin = 0.25;

uniform vec2 spawn_extent = vec2(40.0);
uniform float height_offset = 0.75;
uniform bool use_height_channel = false;
uniform bool debug_color = false;

uniform float stall_window = 0.5;
uniform float stall_threshold = 0.35;
uniform float fizzle_time = 0.6;
uniform float tail_hold = 1.5;

// integer hash so every particle gets stable, independent randoms from its emission number
uint hash_uint(uint x) {
	x = ((x >> 16u) ^ x) * 73244475u;
	x = ((x >> 16u) ^ x) * 73244475u;
	return (x >> 16u) ^ x;
}

float rand01(uint seed) {
	return float(hash_uint(seed) & 16777215u) / 16777216.0;
}

vec2 world_to_uv(vec2 xz) {
	return (xz - sdf_origin) / sdf_size;
}

// outside the baked region there is no data, so it reads as open air rather than letting clamped edge texels steer anything
float sdf_at(vec2 xz) {
	vec2 uv = world_to_uv(xz);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 1e6;
	}
	return textureLod(sdf_map, uv, 0.0).r;
}

// the gradient of a distance field points away from the nearest surface, which is the normal without ever storing one
vec2 sdf_normal(vec2 xz) {
	vec2 texel = sdf_size / vec2(textureSize(sdf_map, 0));
	vec2 gradient = vec2(
		sdf_at(xz + vec2(texel.x, 0.0)) - sdf_at(xz - vec2(texel.x, 0.0)),
		sdf_at(xz + vec2(0.0, texel.y)) - sdf_at(xz - vec2(0.0, texel.y)));
	float len = length(gradient);
	return len > 1e-5 ? gradient / len : vec2(0.0);
}

// strips the part of the wind heading into a surface, scaled by proximity, so flow slides along an obstacle instead of stopping at it
vec2 steer_direction(vec2 xz, float side) {
	vec2 wind = normalize(wind_direction);
	float d = sdf_at(xz);
	if (d >= deflect_radius) {
		return wind;
	}

	vec2 n = sdf_normal(xz);
	if (dot(n, n) < 1e-8) {
		return wind;
	}

	vec2 v = wind - n * min(0.0, dot(wind, n)) * (1.0 - smoothstep(0.0, deflect_radius, d));

	// a dead head on approach cancels to zero, so each particle's side decides which way round it goes
	if (length(v) < 1e-3) {
		v = vec2(-n.y, n.x) * side;
	}
	return normalize(v);
}

// steering keeps particles out most of the time, this guarantees it when a single step jumps a thin wall
vec2 push_out(vec2 xz) {
	float d = sdf_at(xz);
	if (d >= 0.0) {
		return xz;
	}
	return xz + sdf_normal(xz) * (-d + skin);
}

float ground_height(vec2 xz, float emitter_height) {
	if (use_height_channel) {
		return textureLod(sdf_map, clamp(world_to_uv(xz), 0.0, 1.0), 0.0).g + height_offset;
	}
	return emitter_height + height_offset;
}

// trail meshes are built along local Y, so Y has to follow the travel direction or the ribbon collapses edge on
mat3 trail_basis(vec2 velocity) {
	vec2 flat_dir = length(velocity) > 1e-4 ? velocity : wind_direction;
	vec3 forward = normalize(vec3(flat_dir.x, 0.0, flat_dir.y));
	vec3 side = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
	return mat3(side, forward, cross(side, forward));
}

void start() {
	uint seed = hash_uint(NUMBER + RANDOM_SEED);
	vec2 wind = normalize(wind_direction) * wind_speed;

	if (RESTART_POSITION) {
		vec2 r = vec2(rand01(seed), rand01(seed + 1u)) * 2.0 - 1.0;
		vec2 xz = push_out(EMISSION_TRANSFORM[3].xz + r * spawn_extent);
		mat3 basis = trail_basis(wind);
		TRANSFORM = mat4(vec4(basis[0], 0.0), vec4(basis[1], 0.0), vec4(basis[2], 0.0),
			vec4(xz.x, ground_height(xz, EMISSION_TRANSFORM[3].y), xz.y, 1.0));
	}

	if (RESTART_VELOCITY) {
		VELOCITY = vec3(wind.x, 0.0, wind.y);
	}

	if (RESTART_CUSTOM) {
		CUSTOM.x = rand01(seed + 2u) > 0.5 ? 1.0 : -1.0;
		// one window of travel upwind is exactly where the anchor settles for straight motion, so a fresh particle does not read as stalled
		CUSTOM.yz = TRANSFORM[3].xz - normalize(wind_direction) * wind_speed * stall_window;
		CUSTOM.w = 1.0;
	}
}

void process() {
	vec2 xz = TRANSFORM[3].xz;
	vec2 target = steer_direction(xz, CUSTOM.x) * wind_speed;

	// easing toward the steered direction gives the flow some mass, so it overshoots an obstacle slightly instead of snapping back
	vec2 velocity = mix(VELOCITY.xz, target, 1.0 - exp(-turn_rate * DELTA));
	velocity = length(velocity) > 1e-4 ? normalize(velocity) * wind_speed : target;

	xz = push_out(xz + velocity * DELTA);

	// the anchor lags one window behind, so straight travel keeps it a full window away while vibrating in a pocket lets it catch up
	CUSTOM.yz = mix(CUSTOM.yz, xz, 1.0 - exp(-DELTA / max(stall_window, 1e-3)));
	float efficiency = distance(xz, CUSTOM.yz) / max(wind_speed * stall_window, 1e-3);
	bool stalled = efficiency < stall_threshold;

	float fade_step = DELTA / max(fizzle_time, 1e-3);
	if (CUSTOM.w > 0.0) {
		CUSTOM.w = min(CUSTOM.w + (stalled ? -fade_step : fade_step), 1.0);
	} else {
		// once fully faded there is no recovery, it only waits long enough for its trail history to roll off rather than popping
		CUSTOM.w -= fade_step;
	}

	if (CUSTOM.w <= -tail_hold / max(fizzle_time, 1e-3)) {
		ACTIVE = false;
	}

	float fade = clamp(CUSTOM.w, 0.0, 1.0);

	// only the width axes shrink, since trail length comes from position history and scaling Y would distort each section
	mat3 basis = trail_basis(velocity);
	TRANSFORM[0].xyz = basis[0] * fade;
	TRANSFORM[1].xyz = basis[1];
	TRANSFORM[2].xyz = basis[2] * fade;
	TRANSFORM[3].xyz = vec3(xz.x, ground_height(xz, EMISSION_TRANSFORM[3].y), xz.y);
	VELOCITY = vec3(velocity.x, 0.0, velocity.y);

	if (debug_color) {
		vec3 tint = sdf_at(xz) < deflect_radius ? vec3(1.0, 0.35, 0.2) : vec3(1.0);
		COLOR = vec4(stalled ? vec3(0.7, 0.3, 1.0) : tint, fade);
	} else {
		COLOR.a = fade;
	}
}
