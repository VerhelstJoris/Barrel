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

//wind related
group_uniforms wind_movement;
uniform sampler2D wind_noise;
uniform float blade_bend_mult = 0.5f;
uniform float wind_strength = 0.3f;
// Scroll speed, split out of wind_strength which was doing both jobs.
uniform float wind_speed = 0.6f;
// Metres per noise tile; was hardcoded at 10.0.
uniform float wind_noise_scale = 10.0f;
uniform vec2 wind_direction = vec2(1.0, 0.0);
varying float current_wind_bend;
uniform float wind_ao_affect = 0.1f;
// How hard the travelling gust bends a blade, on top of the continuous wind.
uniform float gust_bend_strength = 0.35f;
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
// The blade's own Y scale, read straight off the model matrix. The compute
// shader fades this toward 0 at the fill frontier, and a flattened blade is
// where the backlight term turns into a dark fringe.
varying float blade_height_scale;
// Height scale below which backlight is faded out. Only affects blades already
// collapsing into the ground layer.
uniform float backlight_min_height_scale = 0.35f;
group_uniforms;

// distant clump uniformity — at range, blades share more with their
// neighbors than they do up close: patches of color grow larger (patch
// noise sampled at a coarser scale), wind sways in sync (sampled from a
// shared grid cell), and normals flatten out. Reduces per-blade noise to
// better match distant plane-based grass, without changing anything close
// to the camera.
group_uniforms distant_uniformity;
uniform bool enable_clump_uniformity = true;
uniform float clump_size_m = 1.0f;
uniform float dist_jitter_amount = 4.0f;
varying float clump_factor_v;
group_uniforms;

float hash21(vec2 p)
{
	return fract(sin(dot(p, vec2(127.12, 311.7))) * 43758.545663);
}

void vertex()
{
	// calculate the distance of this blade to the camera — needed by both
	// the LOD divide below and clump uniformity further down
	vec3 world_camera = (INV_VIEW_MATRIX * vec4(vec3(0.0), 1.0)).xyz;
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = distance(world_position.xyz, world_camera);

	// jitter distance per-blade so the transition band isn't a perfect
	// circle around the camera — very obvious as concentric rings when
	// viewed from above otherwise
	float dist_jitter = (hash21(NODE_POSITION_WORLD.xz) - 0.5) * 2.0 * dist_jitter_amount;
	float clump_factor = enable_clump_uniformity ? foliage_clump_factor(dist + dist_jitter) : 0.0;
	clump_factor_v = clump_factor;
	vec2 clump_pos_xz = floor(NODE_POSITION_WORLD.xz / clump_size_m) * clump_size_m + clump_size_m * 0.5;
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

	vec2 wind_sample_pos = mix(NODE_POSITION_WORLD.xz, clump_pos_xz, clump_factor);
	vec2 wind_position = wind_sample_pos / max(wind_noise_scale, 0.001);
  	wind_position -= TIME * wind_direction * wind_speed;

  	current_wind_bend = texture(wind_noise, wind_position).x * 2.0 - 1.0;

	current_wind_bend *= wind_strength;
	// Added before the height scaling, so the gust leans the blade exactly as the
	// base wind does and feeds the wind AO term further down for free.
	// Sampled at the true blade position, NOT wind_sample_pos. That one is
	// snapped to the clump grid so neighbouring blades sway together in the
	// continuous wind -- but the gust is already coherent over hundreds of
	// metres, so quantising it only turns a smooth crest into clump-sized steps.
	current_wind_bend += foliage_gust(NODE_POSITION_WORLD.xz) * gust_bend_strength;
	current_wind_bend *= uv_bottom_to_top * 2.0;

	mat4 inv_model = inverse(MODEL_MATRIX);
  	vec2 local_direction = (inv_model * vec4(wind_direction.x, 0.0, wind_direction.y, 0.0)).xz;

	float uv_strength = pow(uv_bottom_to_top, 2.0);

	// grass bender from the world-anchored accumulator. Sampled at the blade ROOT rather than per vertex, so the whole blade leans as one -- same as
	float raw_bend_mask = sample_bend(NODE_POSITION_WORLD.xz);
	bending_mask_strength = raw_bend_mask * uv_strength;
	
	vec3 object_forward = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	VERTEX.xz += object_forward.xz * bending_mask_strength * bending_mask_strength_horizontal;
	VERTEX.y -= bending_mask_strength * bending_mask_strength_vertical;

  	VERTEX.xz += (current_wind_bend * local_direction) * (1.0- raw_bend_mask);
	VERTEX.xz += blade_bend_mult * uv_strength * (1.0- raw_bend_mask);	// bend the blade in the direction this is positioned in
	
	// patchiness grows coarser with distance — bigger, more pronounced patches of color instead of finer per-blade variation
	patch_factor = foliage_patch_factor(NODE_POSITION_WORLD.xz, clump_factor);
	VERTEX *= mix(size_small, size_large, patch_factor);

	// push the whole blade toward the up-facing tip normal as distance grows,
	NORMAL = mix(NORMAL, vec3(0.0, 1.0, 0.0), max(uv_bottom_to_top, clump_factor * foliage_normal_flatten_far));

	// Column 1 of the model matrix is the blade's up axis, so its length is the
	// height scale the compute shader assigned.
	blade_height_scale = length(MODEL_MATRIX[1].xyz);
}

void fragment() {
	if (!FRONT_FACING)
	{
		NORMAL = -NORMAL;
	}
	
	float base_ao = uv_bottom_to_top - (current_wind_bend * wind_ao_affect);
	float bend_ao = bending_mask_strength * bend_AO_efect_mult;
	float flattened_base_ao = mix(base_ao, 1.0, clump_factor_v * foliage_ao_far_flatten);
	AO = clamp(flattened_base_ao - bend_ao, 0.0, 1.0);
	AO_LIGHT_AFFECT = 1.0;

	ALBEDO = mix(foliage_color_small, foliage_color_large, patch_factor);
	
	BACKLIGHT = foliage_backlight * smoothstep(0.0, backlight_min_height_scale, blade_height_scale);

	// Per-blade normals make specular sparkle once blades are sub-pixel, and
	// flattening normals toward vertical means the whole field peaks at once when
	// viewed from above. Fade the highlight out and broaden what is left.
	ROUGHNESS = mix(foliage_roughness, 1.0, clump_factor_v * foliage_roughness_far_flatten);
	SPECULAR = mix(foliage_specular, 0.0, clump_factor_v * foliage_specular_far_flatten);
}