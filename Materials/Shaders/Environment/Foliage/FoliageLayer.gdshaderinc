// The foliage ground layer that takes over where the geometry blades stop.
// Shares its whole appearance block with Grass.gdshader via
// FoliageAppearance.gdshaderinc, so the two cannot drift apart. Driven entirely
// by world XZ.
// The editor will flag errors opening this alone -- it is a fragment, not a shader.

#include "res://Materials/Shaders/Environment/Foliage/FoliageBend.gdshaderinc"
#include "res://Materials/Shaders/Environment/Foliage/FoliageAppearance.gdshaderinc"
#include "res://Materials/Shaders/Environment/Foliage/FoliageGust.gdshaderinc"

group_uniforms foliage_wind;
uniform sampler2D foliage_wind_noise : hint_default_white;
uniform float foliage_wind_noise_scale = 10.0f;
uniform float foliage_wind_strength = 0.1f;
uniform vec2 foliage_wind_direction = vec2(1.0, 0.0);
// Defaults off: the blades carry wind as motion, never as albedo brightness.
uniform float foliage_wind_highlight_strength = 0.0f;
// Metres the sample position drifts with the wind. World space and view
// independent -- scaling this by camera distance shears the pattern into arcs
// centred on the camera, which is what a "swirl" around the player is.
uniform float foliage_wind_warp_m = 0.5f;
// Gust size multiplier at distance; without it gusts go sub-pixel and vanish.
uniform float foliage_wind_scale_far_mult = 4.0f;
// Extra metres of drift at the gust crest, on top of the continuous wind.
uniform float foliage_gust_warp_m = 1.5f;
// How far the surface tilts into the wind at the crest; the layer's stand-in for blades leaning.
uniform float foliage_gust_normal_tilt = 0.35f;
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

group_uniforms foliage_blade_detail;
// High-frequency noise standing in for individual blades. Assign a fine noise
// with mipmaps ON -- mip filtering is what fades this out with distance, and it
// does so exactly where individual blades stop being resolvable.
uniform sampler2D foliage_blade_noise : hint_default_white;
// Metres per tile. Around a blade width, so 0.2-0.4.
uniform float foliage_blade_noise_scale = 0.3f;
// Albedo modulation. 0 disables the colour half.
uniform float foliage_blade_contrast = 0.12f;
// Normal perturbation, which is what actually reads as separate blades.
uniform float foliage_blade_normal_strength = 0.3f;
// Stretch along the wind direction, so it combs into streaks rather than static.
uniform float foliage_blade_anisotropy = 3.0f;
// How far the detail lags behind the coverage ramp. 1 matches coverage exactly,
uniform float foliage_blade_detail_falloff = 2.0f;
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

	// How much everything coarsens with distance; shared by patches and gusts so
	// a displacement stays the same fraction of a feature at any range.
	float coarsen = foliage_coarsen(clump);

	// Gusts coarsen too. A 10 m cell is a fraction of a pixel at 250 m and
	// averages away, so no amount of amplitude would make it visible.
	float wind_scale = foliage_wind_noise_scale * mix(1.0, foliage_wind_scale_far_mult, clump);
	vec2 wind_uv = world_pos.xz / wind_scale - TIME * foliage_wind_direction * foliage_wind_strength;
	float wind_val = texture(foliage_wind_noise, wind_uv).r;

	// The travelling wave, in phase with the blade shader's copy.
	float gust = foliage_gust(world_pos.xz );

	// Drift where we sample rather than how bright it is: the patches undulate
	// instead of pulsing in place, which is what reads as movement.
	//
	// PURELY WORLD SPACE. Nothing here may depend on camera distance: the
	// displacement direction is constant, so a magnitude that varies with
	// distance shears the texture along arcs of constant radius and draws
	// rings around the player that swim as the camera moves. Far-field
	// visibility has to come from lighting instead -- see the gust normal tilt
	// below and foliage_wind_highlight_strength, both of which are view
	// independent.
	vec2 sample_xz = world_pos.xz + foliage_wind_direction
			* ((wind_val - 0.5) * 2.0 * foliage_wind_warp_m
				+ gust * foliage_gust_warp_m);

	// Shared with the blades, so both coarsen identically.
	float patch_factor = foliage_patch_factor(sample_xz, clump);
	vec3 layer_albedo = mix(foliage_color_small, foliage_color_large, patch_factor);

	// Off by default; the blades express wind as motion, not brightness.
	if (foliage_wind_highlight_strength > 0.0)
	{
		layer_albedo *= mix(1.0 - foliage_wind_highlight_strength,
				1.0 + foliage_wind_highlight_strength, wind_val);
	}

	// World-anchored accumulator, shared with the blade shaders.
	float bend_mask = sample_bend(world_pos.xz);
	layer_albedo = mix(layer_albedo, layer_albedo * (1.0 - foliage_bend_darken_strength), bend_mask);

	// Variance fades out with distance, as the blades flatten toward straight up.
	float variance = foliage_normal_variance_strength * (1.0 - clump * foliage_normal_flatten_far);
	vec2 n_uv = sample_xz / foliage_normal_noise_scale;
	float nx = texture(foliage_normal_noise, n_uv).r * 2.0 - 1.0;
	float nz = texture(foliage_normal_noise, n_uv + vec2(0.37, 0.61)).r * 2.0 - 1.0;
	// World space, unlike the plane shader which perturbed the view-space NORMAL and swam as the camera turned.
	// The gust tilts the surface into the wind, standing in for blades leaning over.
	vec3 gust_tilt = vec3(foliage_wind_direction.x, 0.0, foliage_wind_direction.y)
			* gust * foliage_gust_normal_tilt;
	// Blade-scale detail. Stretched along the wind so it reads as blades combed
	// over rather than isotropic static, and sampled from sample_xz so it sways
	// with the warp instead of sitting still under it.
	//
	// No distance term anywhere: texture() mipmaps this away on its own as the
	// footprint grows, which is both free and safe. A distance-driven strength
	// would be another radial function of camera position, and that is exactly
	// what drew the rings around the player last time.
	vec2 blade_dir = normalize(foliage_wind_direction);
	vec2 blade_perp = vec2(-blade_dir.y, blade_dir.x);
	vec2 blade_uv = vec2(dot(sample_xz, blade_dir) / max(foliage_blade_anisotropy, 0.001),
			dot(sample_xz, blade_perp)) / max(foliage_blade_noise_scale, 0.001);
	float blade_n = texture(foliage_blade_noise, blade_uv).r * 2.0 - 1.0;

	blade_n *= pow(coverage, max(foliage_blade_detail_falloff, 0.001));

	layer_albedo *= 1.0 + blade_n * foliage_blade_contrast;

	// Tilt across the comb direction, so neighbouring streaks catch the light
	// differently the way real blades leaning apart would.
	vec3 blade_tilt = vec3(blade_perp.x, 0.0, blade_perp.y) * blade_n * foliage_blade_normal_strength;

	vec3 layer_normal = normalize(world_normal + vec3(nx, 0.0, nz) * variance + gust_tilt + blade_tilt);

	// AO lifts toward 1.0 with distance, matching the blades' ao_far_flatten.
	// The bend term fades with it, or a trail stays fully dark against ground
	// that has flattened out all around it.
	float ao_flatten = clump * foliage_ao_far_flatten;
	float flattened_base_ao = mix(foliage_base_AO, 1.0, ao_flatten);
	float layer_ao = clamp(flattened_base_ao
			- bend_mask * foliage_bend_AO_effect_mult * (1.0 - ao_flatten), 0.0, 1.0);
	float layer_rough = clamp(mix(foliage_roughness + nx * foliage_roughness_variance_strength,
			1.0, clump * foliage_roughness_far_flatten), 0.0, 1.0);
	float layer_spec = mix(foliage_specular, 0.0, clump * foliage_specular_far_flatten);

	albedo = mix(albedo, layer_albedo, coverage);
	world_normal = normalize(mix(world_normal, layer_normal, coverage));
	roughness = mix(roughness, layer_rough, coverage);
	specular = mix(specular, layer_spec, coverage);
	ao = mix(ao, layer_ao, coverage);
	backlight = mix(backlight, foliage_backlight, coverage);
}
