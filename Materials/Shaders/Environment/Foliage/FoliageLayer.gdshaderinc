// The foliage ground layer that takes over where the geometry blades stop.
// Mirrors Grass.gdshader's distant_uniformity model with the same parameters
// and defaults, so the two converge on the same look at the frontier rather
// than meeting as a visible ring. Driven entirely by world XZ.
// The editor will flag errors opening this alone -- it is a fragment, not a shader.

#include "res://Materials/Shaders/Environment/Foliage/FoliageBend.gdshaderinc"

group_uniforms foliage_base;
// Match the blade shader's color_small.
uniform vec3 foliage_color_small : source_color = vec3(0.3, 0.6, 0.1);
// Match the blade shader's color_large.
uniform vec3 foliage_color_large : source_color = vec3(0.9, 0.9, 0.2);
// Matches the blade's base_ao before ao_far_flatten lifts it.
uniform float foliage_base_AO = 0.5f;
uniform float foliage_roughness = 0.4f;
uniform float foliage_specular = 0.15f;
uniform vec3 foliage_backlight : source_color = vec3(0.2);
group_uniforms;

group_uniforms foliage_patchiness;
// Match the blade shader's patch_noise or the two disagree on colour.
uniform sampler2D foliage_patch_noise : hint_default_white;
// Match the blade shader's patch_scale.
uniform float foliage_patch_scale = 5.0f;
group_uniforms;

group_uniforms foliage_distant_uniformity;
// Mirrors the blade shader's clump_min_distance; keep the two identical.
uniform float foliage_clump_min_distance = 8.0f;
// Mirrors the blade shader's clump_max_distance; keep the two identical.
uniform float foliage_clump_max_distance = 25.0f;
// Mirrors patch_scale_far_mult; without it the layer's patches are 4x too fine.
uniform float foliage_patch_scale_far_mult = 4.0f;
// Mirrors ao_far_flatten, lifting AO toward 1.0 as the blades' AO does.
uniform float foliage_ao_far_flatten = 1.0f;
// Mirrors clump_normal_flatten, fading normal variance out with distance.
uniform float foliage_normal_flatten_far = 1.0f;
group_uniforms;

group_uniforms foliage_wind;
uniform sampler2D foliage_wind_noise : hint_default_white;
uniform float foliage_wind_noise_scale = 10.0f;
uniform float foliage_wind_strength = 0.1f;
uniform vec2 foliage_wind_direction = vec2(1.0, 0.0);
// Defaults off: the blades carry wind as motion, never as albedo brightness.
uniform float foliage_wind_highlight_strength = 0.0f;
group_uniforms;

group_uniforms foliage_bend;
// Defaults off: the blades apply bending to AO only, never to albedo.
uniform float foliage_bend_darken_strength = 0.0f;
// Mirrors bend_AO_efect_mult, though the blade averages it over its own height.
uniform float foliage_bend_AO_effect_mult = 1.0f;
group_uniforms;

group_uniforms foliage_normal_variance;
// Can reuse the wind or patch noise at a tight scale.
uniform sampler2D foliage_normal_noise : hint_default_black;
// Small divisor means tight tiling, so high frequency.
uniform float foliage_normal_noise_scale = 0.15f;
// Only reaches full strength near the camera; flattened away with distance.
uniform float foliage_normal_variance_strength = 0.5f;
// Defaults to 0 because the plane shader overwrote its varied roughness, making this dead.
uniform float foliage_roughness_variance_strength = 0.0f;
group_uniforms;

group_uniforms foliage_coverage_settings;
// Where foliage is allowed; the same mask FoliageWorld gives the compute shader.
uniform sampler2D foliage_placement_mask : hint_default_white, filter_linear;
// World minimum corner, written by FoliageWorld.
uniform vec2 foliage_world_origin_xz = vec2(-1024.0, -1024.0);
// World side length in metres, written by FoliageWorld.
uniform float foliage_world_size_m = 2048.0f;
// XZ radius the blades actually reach, written every frame from the fill's frontier.
uniform float foliage_frontier_radius_m = 250.0f;
uniform float foliage_frontier_fade_m = 30.0f;
// Strength under the blades; raise to 1.0 to preview the layer up close.
uniform float foliage_under_blades = 0.0f;
group_uniforms;


// The blade shader's clump_factor, recomputed here so both converge together.
float foliage_clump_factor(float cam_dist_xz)
{
	return smoothstep(foliage_clump_min_distance, foliage_clump_max_distance, cam_dist_xz);
}


// 0 where blades cover the ground, ramping to full past the frontier, always 0
// outside the placement mask. cam_dist_xz must be XZ, matching the fill's ring radius.
float foliage_coverage(vec3 world_pos, float cam_dist_xz)
{
	vec2 mask_uv = (world_pos.xz - foliage_world_origin_xz) / foliage_world_size_m;
	if (mask_uv.x < 0.0 || mask_uv.y < 0.0 || mask_uv.x > 1.0 || mask_uv.y > 1.0)
	{
		return 0.0;
	}
	float mask = texture(foliage_placement_mask, mask_uv).r;

	float ramp = smoothstep(foliage_frontier_radius_m - foliage_frontier_fade_m,
			foliage_frontier_radius_m, cam_dist_xz);

	return mask * mix(foliage_under_blades, 1.0, ramp);
}


// Blends the foliage look into what the surface already produced. All values in
// WORLD space; coverage of 0 leaves everything untouched.
void apply_foliage_layer(vec3 world_pos, float cam_dist_xz, float coverage,
		inout vec3 albedo, inout vec3 world_normal,
		inout float roughness, inout float specular, inout float ao,
		inout vec3 backlight)
{
	if (coverage <= 0.0)
	{
		return;
	}

	float clump = foliage_clump_factor(cam_dist_xz);

	// Patches coarsen with distance exactly as the blades' do.
	float patch_scale = foliage_patch_scale * mix(1.0, foliage_patch_scale_far_mult, clump);
	float patch_factor = texture(foliage_patch_noise, world_pos.xz / patch_scale).r;
	vec3 layer_albedo = mix(foliage_color_small, foliage_color_large, patch_factor);

	// Off by default; the blades express wind as motion, not brightness.
	if (foliage_wind_highlight_strength > 0.0)
	{
		vec2 wind_uv = world_pos.xz / foliage_wind_noise_scale - TIME * foliage_wind_direction * foliage_wind_strength;
		float wind_val = texture(foliage_wind_noise, wind_uv).r;
		layer_albedo *= mix(1.0 - foliage_wind_highlight_strength,
				1.0 + foliage_wind_highlight_strength, wind_val);
	}

	// World-anchored accumulator, shared with the blade shaders.
	float bend_mask = sample_bend(world_pos.xz);
	layer_albedo = mix(layer_albedo, layer_albedo * (1.0 - foliage_bend_darken_strength), bend_mask);

	// Variance fades out with distance, as the blades flatten toward straight up.
	float variance = foliage_normal_variance_strength * (1.0 - clump * foliage_normal_flatten_far);
	vec2 n_uv = world_pos.xz / foliage_normal_noise_scale;
	float nx = texture(foliage_normal_noise, n_uv).r * 2.0 - 1.0;
	float nz = texture(foliage_normal_noise, n_uv + vec2(0.37, 0.61)).r * 2.0 - 1.0;
	// World space, unlike the plane shader which perturbed the view-space NORMAL and swam as the camera turned.
	vec3 layer_normal = normalize(world_normal + vec3(nx, 0.0, nz) * variance);

	// AO lifts toward 1.0 with distance, matching the blades' ao_far_flatten.
	float flattened_base_ao = mix(foliage_base_AO, 1.0, clump * foliage_ao_far_flatten);
	float layer_ao = clamp(flattened_base_ao - bend_mask * foliage_bend_AO_effect_mult, 0.0, 1.0);
	float layer_rough = clamp(foliage_roughness + nx * foliage_roughness_variance_strength, 0.0, 1.0);

	albedo = mix(albedo, layer_albedo, coverage);
	world_normal = normalize(mix(world_normal, layer_normal, coverage));
	roughness = mix(roughness, layer_rough, coverage);
	specular = mix(specular, foliage_specular, coverage);
	ao = mix(ao, layer_ao, coverage);
	backlight = mix(backlight, foliage_backlight, coverage);
}
