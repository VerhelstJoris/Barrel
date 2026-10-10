shader_type spatial;
render_mode cull_disabled;

// Shared with the terrain layer so the two cannot read the accumulator, or run
// the wave, differently.
#include "res://Materials/Shaders/Environment/Foliage/FoliageBend.gdshaderinc"
#include "res://Materials/Shaders/Environment/Foliage/FoliageAppearance.gdshaderinc"
#include "res://Materials/Shaders/Environment/Foliage/FoliageGust.gdshaderinc"

uniform float size_small = 0.2f;
uniform float size_large = 0.6f;

//patchiness
group_uniforms patchiness;
varying float patch_factor;
group_uniforms;

// Tier 1: noise crawling across the world, shared between neighbouring blades.
group_uniforms wind_movement;
uniform sampler2D wind_noise;
uniform float blade_bend_mult = 0.5f;
uniform float wind_strength = 0.3f;
// Scroll speed, split out of wind_strength which was doing both jobs.
uniform float wind_speed = 0.6f;
// Metres per noise tile; was hardcoded at 10.0.
uniform float wind_noise_scale = 10.0f;
// Constant lean downwind, so near-zero noise still leaves the blade bent rather than upright.
uniform float wind_bias = 0.0f;
// How far the noise may swing UPWIND; 1 is the old symmetric sway, 0 means it can only ever add to the lean.
uniform float wind_sway_symmetry : hint_range(0.0, 1.0) = 1.0f;
uniform vec2 wind_direction = vec2(1.0, 0.0);
varying float current_wind_bend;
uniform float wind_ao_affect = 0.1f;
// How hard the travelling gust bends a blade, on top of the continuous wind.
uniform float gust_bend_strength = 0.35f;
// Drop applied as a vertex swings sideways; 1 keeps the blade's length exactly, 0 lets it stretch as it used to.
uniform float wind_bend_shorten : hint_range(0.0, 1.5) = 1.0f;
group_uniforms;

group_uniforms wind_flutter;
// Sideways travel at the tip, in the same units as the macro bend.
uniform float flutter_strength = 0.08f;
// Oscillations per second; past roughly 10 it aliases into a buzz at 60 fps.
uniform float flutter_speed = 6.0f;
// Spread of per blade rates around flutter_speed, so the field does not beat as one.
uniform float flutter_speed_variation : hint_range(0.0, 0.9) = 0.25f;
// Higher confines the motion to the tip; 1 makes the whole blade shimmy.
uniform float flutter_tip_falloff = 3.0f;
// How much flutter rides the macro bend; 0 leaves it fully independent of the wind.
uniform float flutter_wind_coupling : hint_range(0.0, 1.0) = 0.5f;
// Its own distance ramp, deliberately not the clump band, which runs much further out.
uniform float flutter_fade_start = 10.0f;
uniform float flutter_fade_end = 25.0f;
group_uniforms;

// LOD related
group_uniforms LOD_division;
uniform bool enable_LOD_divide = true;
varying float uv_bottom_to_top;
uniform float min_lod_distance = 8.0f;
uniform float max_lod_distance = 12.0f;
group_uniforms;

// shaping related
group_uniforms shaping;
uniform bool enable_blade_shaping = true;
uniform sampler2D grass_curve_shape;
uniform float curve_width_shape_mult = 1.0f;
group_uniforms;

group_uniforms bend_mask_related;
uniform float bending_mask_strength_horizontal = 2.0f;
uniform float bending_mask_strength_vertical = 2.0f;
uniform float bend_AO_efect_mult = 1.0f;
varying float bending_mask_strength;
// The blade's own Y scale from the model matrix; the compute shader fades it toward 0 at the fill frontier.
varying float blade_height_scale;
// Height scale below which backlight is faded out, so flattened blades lose their dark fringe.
uniform float backlight_min_height_scale = 0.35f;
group_uniforms;

group_uniforms distant_uniformity;
uniform bool enable_clump_uniformity = true;
// Base cell size in metres, near the camera. Cells grow from here in powers of
// two so a clump holds a roughly constant size on screen.
uniform float clump_size_m = 1.0f;
// Ceiling on that growth.
uniform float clump_size_max_m = 8.0f;
// Metres of camera distance per doubling of the cell size.
uniform float clump_size_ref_dist = 12.0f;
uniform float dist_jitter_amount = 4.0f;
varying float clump_factor_v;
group_uniforms;

group_uniforms billboarding;
uniform float billboard_amount : hint_range(0.0, 1.0) = 0.8f;
// anything before this distance will not be affected
uniform float billboard_min_distance = 8.0f;
// full billboard amount past this distnance
uniform float billboard_max_distance = 20.0f;
group_uniforms;


// Integer hash. A sin/fract hash quantises badly once world coordinates reach
// the thousands, banding rather than scattering. This works on the bit pattern
// instead, and is fed cell indices, which are small integers, so it is exact.
uint hash_uint(uint x)
{
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float hash_cell(vec2 cell)
{
	ivec2 cell_index = ivec2(floor(cell));
	return float(hash_uint(uint(cell_index.x) ^ hash_uint(uint(cell_index.y)))) * (1.0 / 4294967296.0);
}


void vertex()
{
	// ---- per-instance basics -------------------------------------------------
	// Distance is measured to the BLADE, not to the transformed vertex.
	vec3 world_camera = (INV_VIEW_MATRIX * vec4(vec3(0.0), 1.0)).xyz;
	vec3 blade_origin = MODEL_MATRIX[3].xyz;
	float dist = distance(blade_origin, world_camera);

	// ---- clump ---------------------------------------------------------------
	// Cell size grows with distance so a clump holds a roughly constant size on screen
	float clump_steps = clamp(dist / max(clump_size_ref_dist, 0.001),
			1.0, max(clump_size_max_m / max(clump_size_m, 0.001), 1.0));
	float clump_size = clump_size_m * exp2(floor(log2(clump_steps)));

	vec2 clump_cell = floor(blade_origin.xz / clump_size);
	vec2 clump_pos_xz = (clump_cell + 0.5) * clump_size;

	// Jitter the transition distance per CELL, not per blade.
	float dist_jitter = (hash_cell(clump_cell) - 0.5) * 2.0 * dist_jitter_amount;
	float clump_dist = distance(vec3(clump_pos_xz.x, blade_origin.y, clump_pos_xz.y), world_camera);
	float clump_factor = enable_clump_uniformity ? foliage_clump_factor(clump_dist + dist_jitter) : 0.0;
	clump_factor_v = clump_factor;

	// ---- patch ---------------------------------------------------------------
	vec2 patch_pos = mix(blade_origin.xz, clump_pos_xz, clump_factor);
	patch_factor = foliage_patch_factor(patch_pos, clump_factor);
	float blade_size = mix(size_small, size_large, patch_factor);

	if(enable_LOD_divide)
	{
		uv_bottom_to_top = 1.0 - UV.y;
		float floored_uv = 1.0 - floor(uv_bottom_to_top +0.1);
		float rounded = 1.0 - round(UV.y);
		float mask = (1.0 - step(UV.y, 0.1)) * step(UV.y, 0.9);

		//we want to lerp towards 0.5
		float lerp_alpha = smoothstep(min_lod_distance,max_lod_distance, dist) * mask;
		VERTEX.y = mix(VERTEX.y, 0.5, lerp_alpha);
		UV.y = mix(UV.y, 0.5, lerp_alpha);
	}

	uv_bottom_to_top = 1.0 - UV.y;

	if(enable_blade_shaping)
	{
		// min value is to fix a small wrap-around issue with the curve where the bottom verts can seemingly be affected by the very end
		float curve_val = texture(grass_curve_shape,  vec2(max(uv_bottom_to_top,0.01),0) ).x;
		VERTEX.x = curve_val * sign(VERTEX.x) * curve_width_shape_mult;
	}

	//turn blade towards camera based on overall world position of the entire blade
	float billboard_alpha = smoothstep(billboard_min_distance, billboard_max_distance, dist);

	vec2 blade_facing = MODEL_MATRIX[2].xz;
	vec2 camera_facing = (world_camera - blade_origin).xz;
	float blade_facing_len = length(blade_facing);
	float camera_facing_len = length(camera_facing);
	if (blade_facing_len > 0.0001 && camera_facing_len > 0.0001)
	{
		blade_facing /= blade_facing_len;
		camera_facing /= camera_facing_len;
		float yaw_sine = blade_facing.x * camera_facing.y - blade_facing.y * camera_facing.x;
		float yaw_cosine = dot(blade_facing, camera_facing);

		// Double angle respects the two sided quad, so it cannot flip at the antipode.
		float turn_angle = -billboard_amount * billboard_alpha * yaw_sine * yaw_cosine;
		float turn_cosine = cos(turn_angle);
		float turn_sine = sin(turn_angle);
		VERTEX.xz = vec2(turn_cosine * VERTEX.x + turn_sine * VERTEX.z,
				-turn_sine * VERTEX.x + turn_cosine * VERTEX.z);
	}

	// ---- tier 1: macro bend ---------------------------------------------------
	// Noise crawling across the world, clump snapped so neighbouring blades lean together.
	vec2 wind_sample_pos = mix(blade_origin.xz, clump_pos_xz, clump_factor);
	vec2 wind_position = wind_sample_pos / max(wind_noise_scale, 0.001);
	wind_position -= TIME * wind_direction * wind_speed;

	float wind_noise_value = texture(wind_noise, wind_position).x;
	// Remaps the output range instead of clamping it, so no band of blades collapses onto one shared lean.
	float wind_noise_shaped = mix(-wind_sway_symmetry, 1.0, wind_noise_value);
	// Noise swings around the bias rather than around upright, so the guaranteed minimum lean is bias - symmetry * strength.
	float macro_bend = wind_bias + wind_noise_shaped * wind_strength;
	// Gust added AFTER the bias so its rebound lobe can still pull a blade back past the resting lean.
	// Read at the TRUE blade position; it is coherent over hundreds of metres, so clump snapping would only step a smooth crest.
	macro_bend += foliage_gust(blade_origin.xz) * gust_bend_strength;

	// Only the macro tier feeds the varying, so the fragment AO never sees flutter flicker.
	current_wind_bend = macro_bend * uv_bottom_to_top * 2.0;

	// ---- tier 2: per blade flutter --------------------------------------------
	// Phase and rate come from the blade's own world position, so no two neighbours move together.
	float flutter_phase = hash_cell(blade_origin.xz * 97.0) * 6.2831853;
	float flutter_rate = flutter_speed * mix(1.0 - flutter_speed_variation, 1.0 + flutter_speed_variation,
			hash_cell(blade_origin.xz * 131.0 + 17.0));
	// Optionally rides the macro bend so blades settle in a lull; 0 keeps it running regardless.
	float flutter_envelope = mix(1.0, abs(macro_bend), flutter_wind_coupling);
	// Gone before blades go sub pixel, where per blade motion is only noise.
	flutter_envelope *= 1.0 - smoothstep(flutter_fade_start, flutter_fade_end, dist);
	float flutter_offset = sin(TIME * flutter_rate + flutter_phase) * flutter_envelope
			* flutter_strength * pow(uv_bottom_to_top, max(flutter_tip_falloff, 0.001));

	mat4 inv_model = inverse(MODEL_MATRIX);
  	vec2 local_direction = (inv_model * vec4(wind_direction.x, 0.0, wind_direction.y, 0.0)).xz;
	// Across the wind, so flutter reads as blades twisting past each other rather than the lean jittering.
	vec2 local_across_wind = vec2(-local_direction.y, local_direction.x);

	float uv_strength = pow(uv_bottom_to_top, 2.0);

	// grass bender from the world-anchored accumulator. Sampled at the blade ROOT rather than per vertex, so the whole blade leans as one -- same as
	float raw_bend_mask = sample_bend(blade_origin.xz);
	bending_mask_strength = raw_bend_mask * uv_strength;

	// Swing radius for the arc drop below, read before anything displaces this vertex.
	float vertex_rest_height = max(VERTEX.y, 0.0);

	vec3 object_forward = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	VERTEX.xz += object_forward.xz * bending_mask_strength * bending_mask_strength_horizontal;
	VERTEX.y -= bending_mask_strength * bending_mask_strength_vertical;

	// Both tiers suppressed by the bend mask: a flattened blade neither leans nor flutters.
	vec2 wind_push = (current_wind_bend * local_direction + flutter_offset * local_across_wind) * (1.0- raw_bend_mask);
	wind_push += vec2(blade_bend_mult * uv_strength * (1.0- raw_bend_mask));	// bend the blade in the direction this is positioned in
  	VERTEX.xz += wind_push;

	// A blade cannot stretch, so swinging a vertex sideways has to drop it; without this the silhouette grows with the wind.
	float wind_push_distance = length(wind_push);
	float swung_height = sqrt(max(vertex_rest_height * vertex_rest_height - wind_push_distance * wind_push_distance, 0.0));
	VERTEX.y -= (vertex_rest_height - swung_height) * wind_bend_shorten;

	VERTEX *= blade_size;

	// push the whole blade toward the up-facing tip normal as distance grows,
	NORMAL = mix(NORMAL, vec3(0.0, 1.0, 0.0), max(uv_bottom_to_top, clump_factor * foliage_normal_flatten_far));

	// Column 1 of the model matrix is the blade's up axis, so its length is the height scale the compute shader assigned.
	blade_height_scale = length(MODEL_MATRIX[1].xyz);
}

void fragment() {
	if (!FRONT_FACING)
	{
		NORMAL = -NORMAL;
	}

	float base_ao = uv_bottom_to_top - (current_wind_bend * wind_ao_affect);
	float bend_ao = bending_mask_strength * bend_AO_efect_mult;
	float flattened_base_ao = mix(base_ao, foliage_ao_far_target, clump_factor_v * foliage_ao_far_flatten);
	AO = clamp(flattened_base_ao - bend_ao, 0.0, 1.0);
	AO_LIGHT_AFFECT = 1.0;

	ALBEDO = mix(foliage_color_small, foliage_color_large, patch_factor);

	BACKLIGHT = foliage_backlight * smoothstep(0.0, backlight_min_height_scale, blade_height_scale);

	ROUGHNESS = mix(foliage_roughness, 1.0, clump_factor_v * foliage_roughness_far_flatten);
	SPECULAR = mix(foliage_specular, 0.0, clump_factor_v * foliage_specular_far_flatten);
}
