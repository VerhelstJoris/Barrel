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

//the peak angle the wind direction is rotated by
uniform float sway_degrees = 12.0;
//oscillations per second
uniform float sway_frequency = 0.4;

uniform sampler2D width_over_life : hint_default_white, filter_linear, repeat_disable;
uniform float width_variation = 0.35;
uniform float life_fade_in = 0.1;
uniform float life_fade_out = 0.2;

// integer hash so every particle gets stable, independent randoms from its emission number
uint hash_uint(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	return (x >> uint(16)) ^ x;
}

float rand01(uint seed) {
	return float(hash_uint(seed) & uint(16777215)) / 16777216.0;
}

float particle_random(uint seed_base, uint salt) {
	return rand01(hash_uint(seed_base + salt));
}

vec2 rotate2(vec2 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

float sway_angle(float age, uint seed_base) {
	float frequency = sway_frequency * mix(0.6, 1.4, particle_random(seed_base, uint(17)));
	float phase = particle_random(seed_base, uint(53)) * TAU;
	float wave = sin(age * frequency * TAU + phase) * 0.7 + sin(age * frequency * 2.37 * TAU + phase * 1.3) * 0.3;
	return radians(sway_degrees) * wave;
}

float life_envelope(float age, float lifetime) {
	float t = clamp(age / max(lifetime, 0.001), 0.0, 1.0);
	return smoothstep(0.0, max(life_fade_in, 0.001), t) * (1.0 - smoothstep(1.0 - max(life_fade_out, 0.001), 1.0, t));
}

float life_shape(float age, float lifetime, uint seed_base) {
	float t = clamp(age / max(lifetime, 0.001), 0.0, 1.0);
	float variety = mix(1.0 - width_variation, 1.0 + width_variation, particle_random(seed_base, uint(89)));
	return textureLod(width_over_life, vec2(t, 0.5), 0.0).r * variety;
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
vec2 steer_direction(vec2 xz, vec2 base, float side) {
	float d = sdf_at(xz);
	if (d >= deflect_radius) {
		return base;
	}

	vec2 n = sdf_normal(xz);
	if (dot(n, n) < 0.00000001) {
		return base;
	}

	vec2 v = base - n * min(0.0, dot(base, n)) * (1.0 - smoothstep(0.0, deflect_radius, d));

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
		// born at zero width so the life envelope grows it in rather than it popping into view
		TRANSFORM = mat4(vec4(0.0), vec4(basis[1], 0.0), vec4(0.0),
			vec4(xz.x, ground_height(xz, EMISSION_TRANSFORM[3].y), xz.y, 1.0));
	}

	if (RESTART_VELOCITY) {
		VELOCITY = vec3(wind.x, 0.0, wind.y);
	}

	if (RESTART_CUSTOM) {
		CUSTOM.x = 0.0;
		// one window of travel upwind is exactly where the anchor settles for straight motion, so a fresh particle does not read as stalled
		CUSTOM.yz = TRANSFORM[3].xz - normalize(wind_direction) * wind_speed * stall_window;
		CUSTOM.w = 1.0;
	}
}

void process() {
	uint seed_base = NUMBER + RANDOM_SEED;
	CUSTOM.x += DELTA;
	float age = CUSTOM.x;
	float side = particle_random(seed_base, uint(131)) > 0.5 ? 1.0 : -1.0;

	// sway rotates the wind before steering, so the deflection rule still strips any part of it that would swing into a wall
	vec2 xz = TRANSFORM[3].xz;
	vec2 base = rotate2(normalize(wind_direction), sway_angle(age, seed_base));
	vec2 target = steer_direction(xz, base, side) * wind_speed;

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
	float visibility = fade * life_envelope(age, LIFETIME);
	float width = visibility * life_shape(age, LIFETIME, seed_base);

	// only the width axes scale, since trail length comes from position history and scaling Y would distort each section
	mat3 basis = trail_basis(velocity);
	TRANSFORM[0].xyz = basis[0] * width;
	TRANSFORM[1].xyz = basis[1];
	TRANSFORM[2].xyz = basis[2] * width;
	TRANSFORM[3].xyz = vec3(xz.x, ground_height(xz, EMISSION_TRANSFORM[3].y), xz.y);
	VELOCITY = vec3(velocity.x, 0.0, velocity.y);

	if (debug_color) {
		vec3 tint = sdf_at(xz) < deflect_radius ? vec3(1.0, 0.35, 0.2) : vec3(1.0);
		COLOR = vec4(stalled ? vec3(0.7, 0.3, 1.0) : tint, visibility);
	} else {
		COLOR.a = visibility;
	}
}
