shader_type particles;
// position is integrated here rather than by the engine, because the height snap and the push out both need the final say on where a particle ends up
render_mode disable_velocity, disable_force;

group_uniforms Field;
// signed distance to the nearest obstacle in red, and terrain height in green once the bake packs it
uniform sampler2D sdf_map : filter_linear, repeat_disable;
// world XZ of the baked region's corner, straight from the bake's companion json
uniform vec2 sdf_origin = vec2(0.0);
// world size of the baked region in metres, which together with the origin maps world XZ onto uv
uniform vec2 sdf_size = vec2(512.0);
// how much faster a streak past the edge of the bake fades, as a multiple of the normal rate, 0 lets it carry on unaffected
uniform float outside_fade_rate = 3.0;

group_uniforms Wind;
// global wind heading on the XZ plane, needs to be non zero since everything normalises it
uniform vec2 wind_direction = vec2(1.0, 0.0);
// metres per second, held constant so steering bends the path rather than slowing it
uniform float wind_speed = 4.0;
// speed multiplier at birth, which lays down trail history faster so a fresh streak reaches full length sooner
uniform float unroll_speed_scale = 1.0;
// seconds the boost eases away over, pushed from trail_lifetime so it is spent exactly when the trail is full
uniform float unroll_time = 1.5;
// distance from a surface at which deflection starts, and the band the lookahead treats as crowded
uniform float deflect_radius = 12.0;
// how much being deflected ages a streak early, wearing it thinner the more geometry it has fought past
uniform float deflect_drag = 0.0;
// how much being deflected pulls the fade down right now, recovering once the streak is running straight again
uniform float deflect_fade = 0.0;
// metres from any surface over which a streak fades out entirely, the direct answer to ribbons clipping into geometry
uniform float surface_fade = 0.0;
// how fast a streak turns toward its steered heading, giving the flow some mass instead of snapping
uniform float turn_rate = 4.0;
// clearance left when a particle is pushed back out of an obstacle, raise toward half the ribbon width
uniform float skin = 0.25;

group_uniforms Spawning;
// an annulus around the emitter, so streaks appear no nearer than the inner radius and no further than the outer
uniform float spawn_radius = 120.0;
uniform float spawn_inner_radius = 0.0;
// shifts the whole ring upwind so streaks sweep toward the emitter rather than materialising all round it, in multiples of the radius
uniform float spawn_upwind_bias = 0.0;
// biases the ring toward its upwind side without moving it, 0 spreads evenly and 1 uses only the upwind half
uniform float spawn_upwind_weight = 0.0;
// half extents of the old spawn box, used instead of the ring when either axis is above zero
uniform vec2 spawn_extent = vec2(0.0);

group_uniforms Height;
// read the ride surface from the field's green channel instead of sitting flat at the emitter's height
uniform bool use_height_channel = false;
// how far above the ground a streak rides
uniform float height_offset = 0.75;
// radius the ground is averaged over, so a streak follows the shape of the land rather than every bump in it
uniform float height_smooth_radius = 0.0;
// samples the ground this far along the direction of travel, so a streak starts climbing before it reaches a rise, negative trails instead
uniform float height_lead_distance = 0.0;
// distance a streak takes to catch up to the ground beneath it, 0 sticks to it exactly
uniform float height_follow_distance = 0.0;

group_uniforms Stalling;
// time constant of the lagging anchor, which sets the distance the progress check measures against
uniform float stall_window = 0.5;
// fraction of expected travel a streak must actually cover, below which it counts as stuck
uniform float stall_threshold = 0.35;
// seconds of continuous stalling to fade from full width to nothing, and to recover from it
uniform float fizzle_time = 0.6;
// seconds a faded streak stays alive at zero width so its trail rolls off, set from trail_lifetime
uniform float tail_hold = 1.5;

group_uniforms Lookahead;
// how far ahead the probe follows the steered path, which is how much warning a streak gets
uniform float lookahead_time = 0.8;
// steps the probe is split into, more of them tracking the curve more faithfully for more samples
uniform int lookahead_steps = 3;
// how hard an approach pulls the fade down, under 0.5 it can only slow recovery rather than fade
uniform float lookahead_closing = 0.6;

group_uniforms Sway;
// peak angle the wind is rotated by, controlling how sharply a streak snakes
uniform float sway_degrees = 12.0;
// oscillations per second, which at constant speed fixes the wavelength at wind_speed over this
uniform float sway_frequency = 0.4;

group_uniforms Width;
// width multiplier over the particle's life, unassigned reads as a flat 1.0
uniform sampler2D width_over_life : hint_default_white, filter_linear, repeat_disable;
// how much width varies between streaks, as a fraction either side of the curve
uniform float width_variation = 0.35;
// fraction of life spent growing in from nothing, so nothing pops into view at birth
uniform float life_fade_in = 0.1;
// fraction of life spent shrinking away, which must cover trail_lifetime or the tail pops at death
uniform float life_fade_out = 0.2;

group_uniforms Debug;
// tint streaks by state, orange near a surface, cyan closing on one, purple stalled
uniform bool debug_color = false;
group_uniforms;

// integer hash so every particle gets stable, independent randoms from its emission number
uint hash_uint(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	return (x >> uint(16)) ^ x;
}

float rand01(uint seed) {
	return float(hash_uint(seed) & uint(16777215)) / 16777216.0;
}

// stage built-ins like NUMBER and LIFETIME are only visible inside start and process, so everything below takes them as parameters
float particle_random(uint seed_base, uint salt) {
	return rand01(hash_uint(seed_base + salt));
}

// a fresh streak has no history behind it, so it starts quick to lay some down and eases back to wind speed once it has
float unroll_scale(float age) {
	return mix(unroll_speed_scale, 1.0, smoothstep(0.0, max(unroll_time, 0.001), age));
}

vec2 rotate2(vec2 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// two sines at a non integer ratio stop the wobble reading as a metronome, and running off age gives every streak a wavelength of speed over frequency
float sway_angle(float age, uint seed_base) {
	float frequency = sway_frequency * mix(0.6, 1.4, particle_random(seed_base, uint(17)));
	float phase = particle_random(seed_base, uint(53)) * TAU;
	float wave = sin(age * frequency * TAU + phase) * 0.7 + sin(age * frequency * 2.37 * TAU + phase * 1.3) * 0.3;
	return radians(sway_degrees) * wave;
}

// growing in from nothing and shrinking back out stops either end of a life popping, and the fade out has to span the trail so the tail is gone before it dies
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

bool inside_region(vec2 xz) {
	vec2 uv = world_to_uv(xz);
	return uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
}

// outside the baked region there is no data, so it reads as open air rather than letting clamped edge texels steer anything
float sdf_at(vec2 xz) {
	if (!inside_region(xz)) {
		return 1000000.0;
	}

	return textureLod(sdf_map, world_to_uv(xz), 0.0).r;
}

// the gradient of a distance field points away from the nearest surface, which is the normal without ever storing one
vec2 sdf_normal(vec2 xz) {
	vec2 texel = sdf_size / vec2(textureSize(sdf_map, 0));
	vec2 gradient = vec2(
		sdf_at(xz + vec2(texel.x, 0.0)) - sdf_at(xz - vec2(texel.x, 0.0)),
		sdf_at(xz + vec2(0.0, texel.y)) - sdf_at(xz - vec2(0.0, texel.y)));
	float len = length(gradient);
	return len > 0.00001 ? gradient / len : vec2(0.0);
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
	if (length(v) < 0.001) {
		v = vec2(-n.y, n.x) * side;
	}
	return normalize(v);
}

// stepping the probe forward and re-steering at each one follows roughly the path the particle will take, so a streak that would curve clear is not mistaken for one about to hit
// side is passed in so a probe reaching a head on stall resolves the same way the particle itself would
float closing_ahead(vec2 xz, vec2 velocity, vec2 base, float side, float speed) {
	if (lookahead_time <= 0.0 || lookahead_steps <= 0) {
		return 0.0;
	}

	float step_time = lookahead_time / float(lookahead_steps);
	float here = sdf_at(xz);
	float worst = 0.0;

	vec2 probe = xz;
	vec2 heading = velocity;

	for (int i = 0; i < lookahead_steps; i++) {
		probe += heading * step_time;
		heading = steer_direction(probe, base, side) * speed;

		// the closest approach anywhere along the path matters, not just wherever the last step happened to land
		float travelled = float(i + 1) * step_time * speed;
		float closing = clamp((here - sdf_at(probe)) / max(travelled, 0.001), 0.0, 1.0);
		float crowding = 1.0 - smoothstep(0.0, max(deflect_radius, 0.001), sdf_at(probe));
		worst = max(worst, closing * crowding);
	}

	return worst;
}

// steering keeps particles out most of the time, this guarantees it when a single step jumps a thin wall
vec2 push_out(vec2 xz) {
	float d = sdf_at(xz);
	if (d >= 0.0) {
		return xz;
	}
	return xz + sdf_normal(xz) * (-d + skin);
}

float height_at(vec2 xz) {
	return textureLod(sdf_map, clamp(world_to_uv(xz), 0.0, 1.0), 0.0).g;
}

// air rides the shape of the land rather than every bump in it, so the ground is averaged over a footprint instead of point sampled
float smoothed_height(vec2 xz) {
	if (height_smooth_radius <= 0.0) {
		return height_at(xz);
	}

	vec2 step_x = vec2(height_smooth_radius, 0.0);
	vec2 step_y = vec2(0.0, height_smooth_radius);
	return (height_at(xz)
		+ height_at(xz + step_x) + height_at(xz - step_x)
		+ height_at(xz + step_y) + height_at(xz - step_y)) * 0.2;
}

// leading the sample along the heading makes a streak start climbing before it reaches a rise, which is what stops it hugging every slope face
float ground_height(vec2 xz, vec2 heading, float emitter_height, float current_y) {
	if (!use_height_channel) {
		return emitter_height + height_offset;
	}

	// past the edge of the bake there is no ground to read, so a streak holds the height it left with instead of snapping onto a clamped edge texel
	if (!inside_region(xz)) {
		return current_y;
	}

	return smoothed_height(xz + heading * height_lead_distance) + height_offset;
}

// easing toward the ground rather than snapping to it gives the vertical motion the same inertia the heading already has
float settled_height(float current_y, float target_y, float speed, float delta) {
	if (!use_height_channel || height_follow_distance <= 0.0) {
		return target_y;
	}

	return mix(current_y, target_y, 1.0 - exp(-(speed / height_follow_distance) * delta));
}

// a ring rather than a box, because the emitter is usually the camera and view distance is a radius, not a square
// the upwind weight skews where on the ring a streak lands, the bias slides the whole ring, and the two compose
vec2 spawn_offset(uint seed, vec2 wind_dir) {
	if (spawn_extent.x > 0.0 || spawn_extent.y > 0.0) {
		return (vec2(rand01(seed), rand01(seed + uint(1))) * 2.0 - 1.0) * spawn_extent;
	}

	float angle = rand01(seed) * TAU;
	if (spawn_upwind_weight > 0.0) {
		// pulling the angle toward the upwind heading crowds the ring on that side while still covering all of it
		float upwind = atan(-wind_dir.y, -wind_dir.x);
		float offset = (rand01(seed) * 2.0 - 1.0) * PI;
		angle = upwind + offset * mix(1.0, 0.5, clamp(spawn_upwind_weight, 0.0, 1.0));
	}

	// the square root keeps the area per unit radius even, otherwise everything piles into the middle
	float span = max(spawn_radius - spawn_inner_radius, 0.0);
	float radius = spawn_inner_radius + span * sqrt(rand01(seed + uint(2)));

	return vec2(cos(angle), sin(angle)) * radius - wind_dir * spawn_radius * spawn_upwind_bias;
}

// trail meshes are built along local Y, so Y has to follow the travel direction or the ribbon collapses edge on
mat3 trail_basis(vec2 velocity) {
	vec2 flat_dir = length(velocity) > 0.0001 ? velocity : wind_direction;
	vec3 forward = normalize(vec3(flat_dir.x, 0.0, flat_dir.y));
	vec3 side = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
	return mat3(side, forward, cross(side, forward));
}

void start() {
	uint seed = hash_uint(NUMBER + RANDOM_SEED);
	vec2 wind = normalize(wind_direction) * wind_speed * unroll_speed_scale;

	if (RESTART_POSITION) {
		vec2 xz = push_out(EMISSION_TRANSFORM[3].xz + spawn_offset(seed, normalize(wind_direction)));
		mat3 basis = trail_basis(wind);
		// born at zero width so the life envelope grows it in rather than it popping into view
		TRANSFORM = mat4(vec4(0.0), vec4(basis[1], 0.0), vec4(0.0),
			vec4(xz.x, ground_height(xz, normalize(wind_direction), EMISSION_TRANSFORM[3].y, EMISSION_TRANSFORM[3].y + height_offset), xz.y, 1.0));
	}

	if (RESTART_VELOCITY) {
		VELOCITY = vec3(wind.x, 0.0, wind.y);
	}

	if (RESTART_CUSTOM) {
		CUSTOM.x = 0.0;
		// one window of travel upwind is exactly where the anchor settles for straight motion, so a fresh particle does not read as stalled
		CUSTOM.yz = TRANSFORM[3].xz - normalize(wind_direction) * wind_speed * unroll_speed_scale * stall_window;
		CUSTOM.w = 1.0;
	}
}

void process() {
	uint seed_base = NUMBER + RANDOM_SEED;
	CUSTOM.x += DELTA;
	float age = CUSTOM.x;
	float side = particle_random(seed_base, uint(131)) > 0.5 ? 1.0 : -1.0;
	float speed = wind_speed * unroll_scale(age);

	// sway rotates the wind before steering, so the deflection rule still strips any part of it that would swing into a wall
	vec2 xz = TRANSFORM[3].xz;
	vec2 base = rotate2(normalize(wind_direction), sway_angle(age, seed_base));
	vec2 steered = steer_direction(xz, base, side);
	vec2 target = steered * speed;

	// how far the geometry turned the streak off its intended heading, zero running straight and one fully reversed
	float deflection = clamp((1.0 - dot(base, steered)) * 0.5, 0.0, 1.0);
	CUSTOM.x += DELTA * deflection * deflect_drag;

	// easing toward the steered direction gives the flow some mass, so it overshoots an obstacle slightly instead of snapping back
	vec2 velocity = mix(VELOCITY.xz, target, 1.0 - exp(-turn_rate * DELTA));
	velocity = length(velocity) > 0.0001 ? normalize(velocity) * speed : target;

	xz = push_out(xz + velocity * DELTA);

	// the anchor lags one window behind, so straight travel keeps it a full window away while vibrating in a pocket lets it catch up
	CUSTOM.yz = mix(CUSTOM.yz, xz, 1.0 - exp(-DELTA / max(stall_window, 0.001)));
	float efficiency = distance(xz, CUSTOM.yz) / max(speed * stall_window, 0.001);
	bool stalled = efficiency < stall_threshold;

	// the probe only pulls the fade down while it is closing, and lets it climb again the moment it is not, so a streak that slips past widens back out
	float closing = closing_ahead(xz, velocity, base, side, speed) * lookahead_closing;
	float pressure = clamp(closing + deflection * deflect_fade, 0.0, 1.0);

	float fade_step = DELTA / max(fizzle_time, 0.001);
	if (CUSTOM.w > 0.0) {
		float direction = stalled ? -1.0 : 1.0 - 2.0 * pressure;
		// nothing out there steers, deflects or grounds a streak, so it clears out rather than drifting on blind
		if (outside_fade_rate > 0.0 && !inside_region(xz)) {
			direction = -outside_fade_rate;
		}
		CUSTOM.w = min(CUSTOM.w + direction * fade_step, 1.0);
	} else {
		// once fully faded there is no recovery, it only waits long enough for its trail history to roll off rather than popping
		CUSTOM.w -= fade_step;
	}

	if (CUSTOM.w <= -tail_hold / max(fizzle_time, 0.001)) {
		ACTIVE = false;
	}

	float fade = clamp(CUSTOM.w, 0.0, 1.0);
	float visibility = fade * life_envelope(age, LIFETIME);

	// a ribbon has width and its trail is drawn as chords between history samples, so both can reach into geometry the centre line cleared
	float distance_now = sdf_at(xz);
	if (surface_fade > 0.0) {
		visibility *= smoothstep(0.0, surface_fade, distance_now);
	}

	float width = visibility * life_shape(age, LIFETIME, seed_base);

	// only the width axes scale, since trail length comes from position history and scaling Y would distort each section
	mat3 basis = trail_basis(velocity);
	TRANSFORM[0].xyz = basis[0] * width;
	TRANSFORM[1].xyz = basis[1];
	TRANSFORM[2].xyz = basis[2] * width;
	float target_y = ground_height(xz, normalize(velocity), EMISSION_TRANSFORM[3].y, TRANSFORM[3].y);
	TRANSFORM[3].xyz = vec3(xz.x, settled_height(TRANSFORM[3].y, target_y, speed, DELTA), xz.y);
	VELOCITY = vec3(velocity.x, 0.0, velocity.y);

	if (debug_color) {
		vec3 tint = distance_now < deflect_radius ? vec3(1.0, 0.35, 0.2) : vec3(1.0);
		if (closing > 0.0) {
			tint = mix(tint, vec3(0.2, 0.9, 0.9), clamp(closing / max(lookahead_closing, 0.001), 0.0, 1.0));
		}
		COLOR = vec4(stalled ? vec3(0.7, 0.3, 1.0) : tint, visibility);
	} else {
		COLOR.a = visibility;
	}
}
