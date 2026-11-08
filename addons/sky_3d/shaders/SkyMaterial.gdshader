// Copyright (c) 2023-2025 Cory Petkovsek and Contributors
// Copyright (c) 2021 J. Cuellar

shader_type sky;

const float SKY_GRAIN_STRENGTH = 0.003;
const float DITHER_LEVELS = 1276.0;
const int CUMULUS_PUFF_COUNT = 7;
const float CUMULUS_PLANET_RADIUS = 40.0; // in cloud base heights, sets how far away the horizon clouds sit
const float CUMULUS_CELL_SIZE = 2.8; // spacing of possible clouds in cloud base heights at size 1
const float CUMULUS_WIND_SCALE = 2.0; // cloud base heights travelled per unit of cumulus_position

group_uniforms general;
uniform bool sky_visible = true;
uniform vec2 color_correction = vec2(0.0, 1.0);
uniform vec4 ground_color: source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float horizon_offset = 0.0;

group_uniforms atmosphere;
uniform float atm_darkness = 0.5;
uniform float atm_sun_intensity = 18.0;
uniform vec4 atm_day_tint: source_color = vec4(0.808, 0.91, 1.0, 1.0);
uniform vec4 atm_horizon_light_tint: source_color = vec4(0.98, 0.635, 0.463, 1.0);
uniform vec4 atm_horizon_night_tint: source_color = vec4(0.98, 0.635, 0.463, 1.0);
uniform vec4 atm_night_tint: source_color = vec4(0.041, 0.049, 0.061, 0.245);
uniform vec3 atm_level_params = vec3(1.0, 0.0, 0.0);
uniform float atm_thickness = 0.7;
uniform vec3 atm_beta_ray = vec3(0.00001, 0.00001, 0.00003);
uniform vec3 atm_beta_mie = vec3(0.00000003038); // Mie * turbidity * 0.000434

group_uniforms sun_disk;
uniform vec4 sun_light_color: source_color = vec4(1.0);
uniform vec4 sun_disk_color: source_color = vec4(0.996, 0.541, 0.14, 1.0);
uniform float sun_disk_intensity = 2.0;
uniform float sun_disk_size = 0.015;

group_uniforms sun_mie;
uniform vec4 atm_sun_mie_tint: source_color = vec4(1.0);
uniform float atm_sun_mie_intensity = 1.0;
uniform vec3 atm_sun_partial_mie_phase = vec3(0.36, 1.64, 1.6);

group_uniforms moon;
uniform vec4 moon_color: source_color = vec4(1.0);
uniform sampler2D moon_texture: source_color, repeat_disable; // set by SkyDome.gd, not sampled by this shader yet
uniform float moon_size = 0.07;

group_uniforms moon_mie;
uniform vec4 atm_moon_mie_tint: source_color = vec4(0.137, 0.184, 0.292, 1.0);
uniform float atm_moon_mie_intensity = 0.17152;
uniform vec3 atm_moon_partial_mie_phase = vec3(0.36, 1.64, 1.6);

group_uniforms star_map;
uniform vec4 starmap_color: source_color = vec4(0.71, 0.71, 0.71, 0.855);
uniform sampler2D starmap_texture: source_color;
uniform bool starmap_flip_u = false;
uniform bool starmap_flip_v = false;
uniform vec3 starmap_alignment = vec3(2.68288, -0.25891, 0.40101); // galactic-coordinate star maps usually fit (2.6555, -0.23935, 0.4505)
uniform float star_rotation_offset = 9.38899;
uniform float star_rotation = 0.0; // earth rotation
uniform float star_tilt = 0.0; // observer latitude tilt in radians, 90° - latitude

group_uniforms star_field;
uniform vec4 star_field_color: source_color = vec4(1.0);
uniform sampler2D star_field_texture: source_color;
uniform float star_scintillation = 0.75;
uniform float star_scintillation_speed = 0.01;
uniform sampler2D noise_tex: source_color;

group_uniforms clouds;
uniform vec4 clouds_night_color: source_color = vec4(0.09, 0.094, 0.129, 1.0);
uniform vec2 cloud_direction = vec2(0.0, -1.0); // Sky3D's _cloud_direction, set by SkyDome.gd

group_uniforms cirrus_clouds;
uniform bool cirrus_visible = true;
uniform float cirrus_intensity = 2.0;
uniform float cirrus_coverage = 0.5;
uniform float cirrus_thickness = 10.0;
uniform float cirrus_absorption = 2.0;
uniform float cirrus_sky_tint_fade = 0.5;
uniform float cirrus_size = 1.0;
uniform vec2 cirrus_uv = vec2(0.16, 0.11);
uniform vec2 cirrus_position1 = vec2(0.0);
uniform vec2 cirrus_position2 = vec2(0.0);
uniform sampler2D cirrus_texture : repeat_enable;
uniform float cirrus_evolution_speed = 0.001;
uniform float cirrus_coverage_variation = 0.1;
uniform float cirrus_wind_stretch : hint_range(1.0, 4.0) = 1.5;
uniform float cirrus_warp_strength = 0.1;
uniform float cirrus_warp_follow : hint_range(0.0, 1.0) = 0.6;

group_uniforms cumulus_clouds;
uniform bool cumulus_visible = true;
uniform float cumulus_intensity = 1.0;
uniform float cumulus_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cumulus_size = 1.0; // cloud scale, spacing between clouds scales with it
uniform vec2 cumulus_position = vec2(0.0); // accumulated wind offset, set by SkyDome.gd
uniform float cumulus_sky_tint_fade = 0.0;
uniform vec3 cumulus_partial_mie_phase = vec3(0.95756, 1.04244, 0.412);
uniform float cumulus_mie_intensity = 1.0;

group_uniforms cumulus_clouds.shape;
uniform float cumulus_roundness : hint_range(0.0, 1.0) = 0.6;
uniform float cumulus_flat_base : hint_range(0.0, 1.0) = 0.25;
uniform float cumulus_puff_blend : hint_range(0.0, 1.0) = 0.3;
uniform float cumulus_puff_flatness : hint_range(0.0, 1.0) = 0.3; // squashes puffs into wider, flatter domes
uniform float cumulus_irregularity : hint_range(0.0, 1.0) = 0.5; // breaks each cloud into lopsided, clumpy masses instead of one round blob
uniform float cumulus_edge_softness : hint_range(0.0, 8.0) = 1.0; // outline width in pixels

group_uniforms cumulus_clouds.wind;
uniform float cumulus_wind_stretch : hint_range(1.0, 3.0) = 1.4;
uniform float cumulus_wind_slant : hint_range(0.0, 1.5) = 0.5;
uniform float cumulus_wind_erosion : hint_range(-1.0, 1.0) = 0.5; // positive streams the tail downwind ahead of the cloud, negative trails it behind

group_uniforms cumulus_clouds.motion;
uniform float cumulus_deform_amount : hint_range(0.0, 1.0) = 0.4;
uniform float cumulus_deform_speed = 0.05;
uniform float cumulus_lifetime = 600.0; // seconds for one grow and fade cycle, 0 keeps every cloud

group_uniforms cumulus_clouds.variation;
uniform float cumulus_size_variation : hint_range(0.0, 1.0) = 0.6; // skewed towards many smaller clouds and the odd large one
uniform float cumulus_shape_variation : hint_range(0.0, 1.0) = 0.6; // per-cloud lumpiness, puff count and puff size spread
uniform float cumulus_aspect_variation : hint_range(0.0, 1.0) = 0.5; // stretches some clouds along their own random direction
uniform float cumulus_height_variation : hint_range(0.0, 1.0) = 0.5; // mixes flat clouds with taller towering ones
uniform float cumulus_small_cloud_coverage : hint_range(0.0, 1.0) = 0.5; // second layer of smaller clouds on a finer grid, filling the gaps between the large ones
uniform float cumulus_small_cloud_scale : hint_range(0.15, 0.8) = 0.4; // size and spacing of that layer relative to cumulus_size

group_uniforms cumulus_clouds.colour;
uniform vec4 cumulus_shadow_color : source_color = vec4(0.66, 0.7, 0.82, 1.0); // tint for clouds on the side of the sky facing away from the sun
uniform float cumulus_away_shade : hint_range(0.0, 1.0) = 0.5; // how far clouds away from the sun shift towards the shadow colour
uniform float cumulus_sun_glow : hint_range(0.0, 2.0) = 0.5; // extra brightness for clouds close to the sun
uniform float cumulus_sun_glow_spread : hint_range(0.0, 1.0) = 0.4; // how far across the sky the sun glow reaches
uniform float cumulus_horizon_fade : hint_range(0.0, 1.0) = 0.5; // how much clouds near the horizon blend into the sky behind them
uniform float cumulus_horizon_fade_height : hint_range(0.05, 1.0) = 0.35; // view height above the horizon where that blend ends

group_uniforms overlays;
uniform bool show_azimuthal_grid = false;
uniform vec4 azimuthal_grid_color : source_color = vec4(0.871, 0.722, 0.529, 1.0);
uniform float azimuthal_grid_rotation_offset = 0.03;
uniform bool show_equatorial_grid = false;
uniform vec4 equatorial_grid_color : source_color = vec4(0.0, 0.75, 1.0, 1.0);
uniform float equatorial_grid_rotation_offset = 0.03;

group_uniforms transform_matrices;
uniform mat3 moon_matrix; // set by SkyDome.gd, not used by this shader yet

#include "Common.gdshaderinc"

// Helpers
//------------------------------------------------------------------------------

mat3 _create_rotation_matrix(vec3 euler_angles) {
	float cos_x = cos(euler_angles.x), sin_x = sin(euler_angles.x);
	float cos_y = cos(euler_angles.y), sin_y = sin(euler_angles.y);
	float cos_z = cos(euler_angles.z), sin_z = sin(euler_angles.z);
	mat3 rotation_x = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos_x, -sin_x), vec3(0.0, sin_x, cos_x));
	mat3 rotation_y = mat3(vec3(cos_y, 0.0, sin_y), vec3(0.0, 1.0, 0.0), vec3(-sin_y, 0.0, cos_y));
	mat3 rotation_z = mat3(vec3(cos_z, -sin_z, 0.0), vec3(sin_z, cos_z, 0.0), vec3(0.0, 0.0, 1.0));
	return rotation_z * rotation_y * rotation_x;
}

vec2 _calc_equirect_uv(vec3 sky_dir) {
	float flip_u_sign = starmap_flip_u ? -1.0 : 1.0;
	float flip_v_sign = starmap_flip_v ? -1.0 : 1.0;
	float equirect_u = flip_u_sign * ((atan(sky_dir.y, sky_dir.x) + PI) * INV_TAU);
	float equirect_v = -flip_v_sign * (acos(sky_dir.z) * INV_PI);
	return vec2(equirect_u, equirect_v);
}

float _calc_disk_mask(vec3 view_dir, vec3 disk_dir, float disk_size) {
	return 1.0 - step(disk_size, length(view_dir - disk_dir));
}

// moon intersection courtesy of Kelvin van Hoorn: https://kelvinvanhoorn.com/2024/12/07/skybox-tutorial-godot/
float _simple_sphere_intersect(vec3 ray_dir, vec3 sphere_pos, float sphere_radius) {
	vec3 origin_offset = -sphere_pos;
	float projected_dist = dot(origin_offset, ray_dir);
	float constant_term = dot(origin_offset, origin_offset) - sphere_radius * sphere_radius;
	float discriminant = projected_dist * projected_dist - constant_term;
	float hit_valid = step(0.0, discriminant);
	return mix(-1.0, -projected_dist - sqrt(max(discriminant, 0.0)), hit_valid);
}

// Atmosphere
//------------------------------------------------------------------------------

vec3 _calc_atmospheric_scatter(float rayleigh_depth, float mie_depth, vec2 light_cos_angles, vec3 angle_mult, float horizon_night_blend) {
	vec3 beta_rayleigh = atm_beta_ray * atm_thickness;
	vec3 extinction = clamp_rgb_to_unit(exp(-(beta_rayleigh * rayleigh_depth + atm_beta_mie * mie_depth)));
	float extinction_blend = mix(clamp_to_unit(atm_thickness * 0.5), 1.0, angle_mult.x);
	vec3 final_extinction = mix(1.0 - extinction, (1.0 - extinction) * extinction, extinction_blend);

	vec3 rayleigh_term = beta_rayleigh * calc_rayleigh_phase(light_cos_angles.x);
	vec3 mie_term = atm_beta_mie * calc_mie_phase(light_cos_angles.x, atm_sun_partial_mie_phase) * atm_sun_mie_intensity * atm_sun_mie_tint.rgb;
	vec3 phase_ratio = (rayleigh_term + mie_term) / (beta_rayleigh + atm_beta_mie);
	vec3 day_scatter = atm_sun_intensity * phase_ratio * final_extinction * atm_day_tint.rgb * angle_mult.y;
	day_scatter = mix(day_scatter, day_scatter * (1.0 - extinction), atm_darkness);

	vec3 horizon_tint = mix(atm_horizon_light_tint.rgb, atm_horizon_night_tint.rgb, horizon_night_blend);
	vec3 light_tint = mix(atm_day_tint.rgb, horizon_tint, angle_mult.x);
	vec3 night_scatter = (1.0 - extinction) * atm_night_tint.rgb;
	night_scatter += calc_mie_phase(light_cos_angles.y, atm_moon_partial_mie_phase) * atm_moon_mie_tint.rgb * atm_moon_mie_intensity * 0.005;
	return day_scatter * light_tint + night_scatter;
}

// Cirrus clouds
//------------------------------------------------------------------------------

// compresses the along-wind axis so shapes elongate in their travel direction
vec2 _stretch_along_wind(vec2 layer_uv, vec2 wind_axis, float stretch_amount) {
	return layer_uv - wind_axis * (dot(layer_uv, wind_axis) * (1.0 - 1.0 / stretch_amount));
}

// two decorrelated layers drift apart sideways so their sum keeps morphing
float _sample_cirrus_noise(vec2 sky_coords, vec2 wind_axis, float warp_shift) {
	vec2 base_uv = sky_coords * cirrus_uv - wind_axis * warp_shift;
	vec2 evolve_shift = vec2(-wind_axis.y, wind_axis.x) * (TIME * cirrus_evolution_speed * 0.5);
	vec2 first_layer_uv = _stretch_along_wind(base_uv + cirrus_position1 - evolve_shift, wind_axis, cirrus_wind_stretch);
	vec2 second_layer_uv = _stretch_along_wind(base_uv + cirrus_position2 + evolve_shift + vec2(0.37, 0.61), wind_axis, cirrus_wind_stretch);
	float first_layer = textureLod(cirrus_texture, first_layer_uv, 0.0).r;
	float second_layer = textureLod(cirrus_texture, second_layer_uv, 0.0).r;
	// restores the contrast lost by averaging two uncorrelated layers
	return 0.5 + ((first_layer + second_layer) * 0.5 - 0.5) * 1.41421356;
}

vec4 _render_cirrus_clouds(vec3 view_dir) {
	vec2 sky_coords = view_dir.xz / view_dir.y * cirrus_size;
	// slow field the clouds drift through, deforming them and shifting coverage as they pass
	float drift_field = textureLod(cirrus_texture, (sky_coords * cirrus_uv + cirrus_position1 * cirrus_warp_follow) * 0.35, 0.0).r - 0.5;
	float local_coverage = clamp_to_unit(cirrus_coverage + drift_field * cirrus_coverage_variation);
	float cirrus_noise = _sample_cirrus_noise(sky_coords, cloud_direction, drift_field * cirrus_warp_strength);
	float density = clamp_to_unit(cirrus_noise - (1.0 - local_coverage));
	float light_transmit = clamp_to_unit(exp(-cirrus_absorption * density));
	float cloud_alpha = smoothstep(0.1, 0.2, density) * cirrus_thickness;
	return vec4(vec3(density * light_transmit) * cirrus_intensity, cloud_alpha);
}

// Cumulus clouds
//------------------------------------------------------------------------------

uint _hash_uint(uint hash_input) {
	uint hash_state = hash_input * 747796405u + 2891336453u;
	uint hash_word = ((hash_state >> ((hash_state >> 28u) + 4u)) ^ hash_state) * 277803737u;
	return (hash_word >> 22u) ^ hash_word;
}

// splits one hash into three 10-bit random values in 0-1
vec3 _unpack_random(uint hash_value) {
	return vec3(uvec3(hash_value, hash_value >> 10u, hash_value >> 20u) & uvec3(1023u)) / 1023.0;
}

// distance along the view ray to the curved layer at an altitude above the viewer, in cloud base heights
float _shell_distance(vec3 view_dir, float altitude) {
	float planet_term = CUMULUS_PLANET_RADIUS * view_dir.y;
	float shell_radius = CUMULUS_PLANET_RADIUS + altitude;
	return -planet_term + sqrt(planet_term * planet_term + shell_radius * shell_radius - CUMULUS_PLANET_RADIUS * CUMULUS_PLANET_RADIUS);
}

// height of the curved layer above the viewer at a horizontal map position
float _shell_height(vec2 map_pos, float altitude) {
	float shell_radius = CUMULUS_PLANET_RADIUS + altitude;
	return sqrt(max(shell_radius * shell_radius - dot(map_pos, map_pos), 0.0)) - CUMULUS_PLANET_RADIUS;
}

// squashes a vector along the wind and vertically, so a sphere test in that space hits ellipsoids stretched with the wind and flattened
vec3 _squash_puff_space(vec3 source_vector, vec3 wind_axis, float stretch_amount, float height_scale) {
	vec3 squashed_vector = source_vector - wind_axis * (dot(source_vector, wind_axis) * (1.0 - 1.0 / stretch_amount));
	squashed_vector.y /= height_scale;
	return squashed_vector;
}

float _smooth_max(float first_value, float second_value, float blend_width) {
	float blend_overlap = max(blend_width - abs(first_value - second_value), 0.0) / max(blend_width, 1e-5);
	return max(first_value, second_value) + blend_overlap * blend_overlap * blend_width * 0.25;
}

// traces one cloud's puffs, merging them into the running outline field
void _trace_cumulus_cloud(ivec2 cell_id, vec3 view_dir, vec3 wind_axis, vec2 wind_shift, float cloud_scale, uint layer_seed, float layer_coverage, inout float cloud_field) {
	uint cell_hash = _hash_uint(uint(cell_id.x) * 1597334677u ^ uint(cell_id.y) * 3812015801u ^ layer_seed);
	float life_phase = 0.5;
	uint life_cycle = 0u;
	if (cumulus_lifetime > 0.0) {
		float life_position = TIME / cumulus_lifetime + float(cell_hash & 1023u) / 1023.0;
		life_phase = fract(life_position);
		life_cycle = uint(life_position);
	}
	uint cloud_hash = _hash_uint(cell_hash ^ (life_cycle * 2654435761u));
	vec3 cloud_random = _unpack_random(cloud_hash);
	// grows from nothing and fades back out over each life cycle so clouds never pop
	float growth = smoothstep(0.0, 0.2, life_phase) * (1.0 - smoothstep(0.7, 1.0, life_phase));
	if (cloud_random.x >= layer_coverage || growth <= 0.0) {
		return;
	}

	vec2 cloud_map = (vec2(cell_id) + 0.5 + (cloud_random.yz - 0.5) * 0.4) * CUMULUS_CELL_SIZE * cloud_scale - wind_shift;
	vec3 cloud_base = vec3(cloud_map.x, _shell_height(cloud_map, 1.0), cloud_map.y);
	// cheap early rejection against the largest reach any cloud is allowed, before working out its shape
	vec3 coarse_center = cloud_base + vec3(0.0, 0.36 * cloud_scale, 0.0);
	float coarse_radius = (1.65 * CUMULUS_CELL_SIZE + 0.66) * cloud_scale;
	float coarse_projection = dot(coarse_center, view_dir);
	if (dot(coarse_center, coarse_center) - coarse_projection * coarse_projection > coarse_radius * coarse_radius) {
		return;
	}
	vec3 variation_random = _unpack_random(_hash_uint(cloud_hash ^ 2246822519u));
	vec3 layout_random = _unpack_random(_hash_uint(cloud_hash ^ 3266489917u));
	float size_factor = mix(1.0 - 0.7 * cumulus_size_variation, 1.0 + 0.7 * cumulus_size_variation, pow(variation_random.x, 1.5));
	float local_roundness = clamp(cumulus_roundness + (variation_random.y - 0.5) * 1.6 * cumulus_shape_variation, 0.0, 1.0);
	int active_puffs = CUMULUS_PUFF_COUNT - int(floor(variation_random.z * 4.99 * cumulus_shape_variation));
	float aspect_stretch = 1.0 + 0.9 * cumulus_aspect_variation * layout_random.x;
	float tower_scale = mix(1.0 - 0.6 * cumulus_height_variation, 1.0 + 4.0 * cumulus_height_variation, layout_random.z * layout_random.z);
	float spread_factor = mix(1.7, 1.0, local_roundness);
	float erosion = abs(cumulus_wind_erosion);
	vec2 erosion_axis = wind_axis.xz * (cumulus_wind_erosion < 0.0 ? -1.0 : 1.0);

	vec3 shape_random = _unpack_random(_hash_uint(cloud_hash ^ 668265263u));
	vec2 heavy_side = vec2(cos(shape_random.x * TAU), sin(shape_random.x * TAU));
	// a second, smaller mass attached to the main one, so irregular clouds read as several clumps rather than one blob
	vec2 side_mass_offset = vec2(cos(shape_random.y * TAU), sin(shape_random.y * TAU)) * (0.8 + 0.4 * shape_random.z) * cumulus_irregularity;

	// farthest reach of any puff in core radii, covering layout, irregularity, tail, wobble, stretch and slant
	float reach_factor = spread_factor * (aspect_stretch * (1.0 + 2.0 * erosion) * (1.0 + 1.25 * cumulus_irregularity) + 0.25 * cumulus_deform_amount)
		+ 1.35 * (1.0 + 0.35 * cumulus_irregularity) * (1.0 + (cumulus_wind_stretch - 1.0) * (1.0 + erosion))
		+ (1.35 + 0.3 * tower_scale + 0.35 * cumulus_irregularity) * cumulus_wind_slant + 0.5;
	// shrinks a cloud that would reach past the cell search, rather than letting the search cut it off
	float core_radius = min(0.42 * cloud_scale * size_factor * growth, 1.65 * CUMULUS_CELL_SIZE * cloud_scale / reach_factor);
	float puff_spread = core_radius * spread_factor;

	// skips the puffs when the ray passes outside a sphere bounding the whole cloud and its outline falloff
	vec3 bound_center = cloud_base + vec3(0.0, core_radius, 0.0);
	float bound_radius = core_radius * reach_factor + 0.3 * cloud_scale;
	float bound_projection = dot(bound_center, view_dir);
	if (dot(bound_center, bound_center) - bound_projection * bound_projection > bound_radius * bound_radius) {
		return;
	}
	vec2 aspect_axis = vec2(cos(layout_random.y * TAU), sin(layout_random.y * TAU));
	float puff_height_scale = 1.0 - 0.5 * cumulus_puff_flatness;

	float base_distance = cloud_base.y / max(view_dir.y, 0.001);
	float blend_width = cumulus_puff_blend * core_radius * 0.5 * (1.0 + 0.6 * cumulus_irregularity);
	float wobble_time = TIME * cumulus_deform_speed;
	vec2 wind_flat = wind_axis.xz;
	vec2 golden_step = vec2(cos(2.39996), sin(2.39996));
	vec2 puff_heading = vec2(cos(cloud_random.y * TAU), sin(cloud_random.y * TAU));
	for (int puff_index = 0; puff_index < CUMULUS_PUFF_COUNT; puff_index++) {
		if (puff_index >= active_puffs) {
			break;
		}
		vec3 puff_random = _unpack_random(_hash_uint(cloud_hash + uint(puff_index) * 2654435769u));
		vec3 irregular_random = _unpack_random(_hash_uint(cloud_hash ^ (uint(puff_index) * 1274126177u + 97u)));
		// sunflower layout spreads the puffs evenly around the big central one, fewer puffs giving bigger separate lobes
		float ring_fraction = sqrt(float(puff_index) / float(max(active_puffs - 1, 1)));
		vec2 puff_offset = puff_heading * ring_fraction * puff_spread * mix(0.75, 1.0, puff_random.x);
		puff_heading = vec2(puff_heading.x * golden_step.x - puff_heading.y * golden_step.y, puff_heading.x * golden_step.y + puff_heading.y * golden_step.x);
		// irregularity strings some puffs out towards the side mass, keeping it attached, and scatters the rest off the tidy round layout
		float side_mass_member = step(irregular_random.z, 0.4) * step(0.5, float(puff_index));
		float side_mass_reach = mix(0.5, 1.0, fract(irregular_random.x * 7.31));
		puff_offset = mix(puff_offset, puff_offset * mix(1.0, 0.6, cumulus_irregularity) + side_mass_offset * puff_spread * side_mass_reach, side_mass_member);
		puff_offset += (irregular_random.xy - 0.5) * puff_spread * 0.6 * cumulus_irregularity;
		// stretches the layout along the cloud's own random axis so some clouds form longer rows of puffs
		puff_offset += aspect_axis * (dot(puff_offset, aspect_axis) * (aspect_stretch - 1.0));
		// slowly drifts and swells each puff so the cloud keeps reshaping
		puff_offset += vec2(sin(wobble_time + puff_random.x * TAU), sin(wobble_time * 0.83 + puff_random.y * TAU)) * puff_spread * 0.25 * cumulus_deform_amount;
		float puff_size_spread = 0.15 + 0.35 * cumulus_shape_variation;
		float puff_radius = core_radius * mix(1.0, mix(0.55, 0.8, local_roundness), ring_fraction) * mix(1.0 - puff_size_spread, 1.0 + puff_size_spread, puff_random.y);
		puff_radius *= 1.0 + 0.15 * cumulus_deform_amount * sin(wobble_time * 1.27 + puff_random.z * TAU);
		// makes one side of the cloud heavier so its mass is lopsided rather than centred
		puff_radius *= 1.0 + 0.35 * cumulus_irregularity * clamp(dot(puff_offset, heavy_side) / max(puff_spread, 1e-4), -1.0, 1.0);

		// erosion packs the mass into a blunt upwind head and drags the downwind puffs into a smaller, lower, longer tail
		float wind_along = dot(puff_offset, erosion_axis) - puff_spread * 0.3 * erosion;
		vec2 wind_across = puff_offset - erosion_axis * dot(puff_offset, erosion_axis);
		float tail_fraction = clamp(wind_along / max(puff_spread, 1e-4), 0.0, 1.0);
		wind_along *= wind_along > 0.0 ? 1.0 + 2.0 * erosion : 1.0 - 0.4 * erosion;
		wind_across *= 1.0 - 0.4 * erosion * tail_fraction;
		puff_radius *= (1.0 - 0.55 * erosion * tail_fraction) * (1.0 + 0.2 * erosion * clamp(-wind_along / max(puff_spread, 1e-4), 0.0, 1.0));
		// stacks puffs at varied heights, tallest in the middle, so the top outline breaks into separate domes
		float puff_height = (puff_radius * (1.0 - cumulus_flat_base) + ((1.0 - ring_fraction) * 0.3 * tower_scale + puff_random.z * 0.35 * (1.0 + cumulus_irregularity)) * core_radius * (1.0 - 0.6 * erosion * tail_fraction)) * puff_height_scale;
		// leans higher puffs downwind like a cloud sheared by stronger wind aloft
		vec2 puff_flat = erosion_axis * wind_along + wind_across + wind_flat * (puff_height * cumulus_wind_slant);
		vec3 puff_center = cloud_base + vec3(puff_flat.x, puff_height, puff_flat.y);
		float puff_stretch = 1.0 + (cumulus_wind_stretch - 1.0) * (1.0 + erosion * tail_fraction);

		vec3 squashed_origin = _squash_puff_space(-puff_center, wind_axis, puff_stretch, puff_height_scale);
		vec3 squashed_dir = _squash_puff_space(view_dir, wind_axis, puff_stretch, puff_height_scale);
		float dir_length_sq = dot(squashed_dir, squashed_dir);
		float half_b = dot(squashed_origin, squashed_dir);
		float discriminant = half_b * half_b - dir_length_sq * (dot(squashed_origin, squashed_origin) - puff_radius * puff_radius);
		float exit_distance = (-half_b + sqrt(max(discriminant, 0.0))) / dir_length_sq;
		// distance inside the puff outline, cut where the ray only passes below the flat cloud base
		float puff_field = min(discriminant / (dir_length_sq * 2.0 * max(puff_radius, 1e-4)), (exit_distance - base_distance) * view_dir.y);
		cloud_field = _smooth_max(cloud_field, puff_field, blend_width);
	}
}

// traces one layer of clouds, each layer on its own grid scaled to its cloud size so large and small clouds can share the sky
void _trace_cumulus_layer(vec3 view_dir, vec3 wind_axis, vec2 wind_shift, float cloud_scale, uint layer_seed, float layer_coverage, inout float cloud_field) {
	// looks up clouds around where the ray crosses the middle of the puff band
	vec2 lookup_map = view_dir.xz * _shell_distance(view_dir, 1.0 + 0.4 * cloud_scale);
	// searches the 4x4 cells nearest the lookup point, leaving at least one and a half cells of reach on every side
	vec2 cell_position = (lookup_map + wind_shift) / (CUMULUS_CELL_SIZE * cloud_scale);
	ivec2 window_start = ivec2(floor(cell_position - 0.5)) - ivec2(1);
	for (int cell_y = 0; cell_y < 4; cell_y++) {
		for (int cell_x = 0; cell_x < 4; cell_x++) {
			_trace_cumulus_cloud(window_start + ivec2(cell_x, cell_y), view_dir, wind_axis, wind_shift, cloud_scale, layer_seed, layer_coverage, cloud_field);
		}
	}
}

vec4 _render_cumulus_clouds(vec3 view_dir, vec3 sun_dir, vec3 scatter, vec3 cloud_tint) {
	float cloud_scale = max(cumulus_size, 0.05);
	// Sky3D's cloud_direction points against the visible travel, matching how cumulus_position accumulates
	vec2 travel_dir = -cloud_direction / max(length(cloud_direction), 1e-4);
	vec3 wind_axis = vec3(travel_dir.x, 0.0, travel_dir.y);
	vec2 wind_shift = cumulus_position * CUMULUS_WIND_SCALE;

	float cloud_field = -1e3;
	_trace_cumulus_layer(view_dir, wind_axis, wind_shift, cloud_scale, 0u, cumulus_coverage, cloud_field);
	float smallest_scale = cloud_scale;
	if (cumulus_small_cloud_coverage > 0.0) {
		smallest_scale = cloud_scale * cumulus_small_cloud_scale;
		_trace_cumulus_layer(view_dir, wind_axis, wind_shift, smallest_scale, 2654435761u, cumulus_small_cloud_coverage, cloud_field);
	}
	// floors empty sky within every layer's culling margin, so a culled cloud never leaves a jump that fwidth turns into a fringe
	cloud_field = max(cloud_field, -0.2 * smallest_scale);

	// keeps the outline a fixed number of pixels wide, so edges stay sharp at any distance without stair-stepping
	float field_per_pixel = max(fwidth(cloud_field), 1e-6);
	float cloud_alpha = clamp(0.5 + cloud_field / (field_per_pixel * max(cumulus_edge_softness, 1e-3)), 0.0, 1.0);

	// colour depends only on where the cloud sits in the sky, so overlapping and attached clouds always share one smooth gradient
	float day_light = smoothstep(-0.1, 0.05, sun_dir.y);
	float sun_cos = dot(view_dir, sun_dir);
	vec3 lit_color = cloud_tint * cumulus_intensity;
	float away_amount = (0.5 - 0.5 * sun_cos) * cumulus_away_shade * day_light;
	vec3 cloud_color = mix(lit_color, lit_color * cumulus_shadow_color.rgb, away_amount);
	cloud_color += lit_color * pow(max(sun_cos, 0.0), mix(48.0, 1.5, cumulus_sun_glow_spread)) * cumulus_sun_glow * day_light;

	// thin rim of forward-scattered sunlight along the outer outline when looking towards the sun
	float rim_closeness = 1.0 - smoothstep(0.0, 0.06 * cloud_scale, cloud_field);
	float rim_glow = calc_mie_phase(sun_cos, cumulus_partial_mie_phase) * 0.02 * cumulus_mie_intensity * max(sun_cos, 0.0) * day_light;
	cloud_color += lit_color * rim_closeness * rim_glow;

	// sinks clouds into the sky colour towards the horizon for aerial perspective
	float horizon_amount = (1.0 - smoothstep(0.0, cumulus_horizon_fade_height, view_dir.y)) * cumulus_horizon_fade;
	cloud_color = mix(cloud_color, scatter, horizon_amount);
	return vec4(cloud_color, cloud_alpha);
}

// Sky
//------------------------------------------------------------------------------

vec3 _render_sky(vec3 view_dir, vec3 sun_dir, vec3 moon_dir, out float cloud_coverage) {
	cloud_coverage = 0.0;
	vec4 angle_mult = vec4(
		clamp_to_unit(1.0 - sun_dir.y),
		clamp_to_unit(sun_dir.y + 0.45),
		clamp_to_unit(-sun_dir.y + 0.30),
		clamp_to_unit(-sun_dir.y + 0.60));

	vec2 light_cos_angles = vec2(dot(sun_dir, view_dir), dot(moon_dir, view_dir));
	vec3 sky_dir = view_dir - vec3(0.0, horizon_offset, 0.0);
	float rayleigh_depth;
	float mie_depth;
	calc_simple_optical_depth(sky_dir.y + atm_level_params.z, rayleigh_depth, mie_depth, atm_level_params.xy);

	// fades stars and clouds out towards the horizon for a sense of depth
	float horizon_blend = clamp_to_unit((sky_dir.y - 0.03) * 3.0);
	float horizon_color_blend = 1.0 - max(dot(sun_dir, sky_dir), 0.0);
	vec3 scatter = _calc_atmospheric_scatter(rayleigh_depth, mie_depth, light_cos_angles, angle_mult.xyz, horizon_color_blend);
	vec3 sky_color = scatter;

	vec3 sun_disk = _calc_disk_mask(sky_dir, sun_dir, sun_disk_size) * sun_disk_color.rgb * scatter * sun_disk_intensity;

	float moon_hit = _simple_sphere_intersect(sky_dir, moon_dir, moon_size);
	float moon_mask = moon_hit > (-1.0 + sqrt(moon_size)) ? 1.0 : 0.0;
	vec3 moon_normal = normalize(sky_dir * moon_hit - moon_dir);
	float moon_lit = clamp_to_unit(dot(moon_normal, sun_dir));
	vec3 moon_surface = moon_mask * moon_lit * 2.0 * moon_color.rgb;
	float sky_behind_moon = 1.0 - moon_mask;

	mat3 tilt_matrix = _create_rotation_matrix(vec3(star_tilt, 0.0, 0.0));
	mat3 earth_rotation = _create_rotation_matrix(vec3(0.0, star_rotation + star_rotation_offset, 0.0));
	mat3 starmap_matrix = _create_rotation_matrix(starmap_alignment);
	vec2 deep_space_uv = _calc_equirect_uv(normalize(starmap_matrix * earth_rotation * tilt_matrix * sky_dir));

	vec3 deep_space = textureLod(starmap_texture, deep_space_uv, 0.0).rgb * starmap_color.rgb;
	deep_space = adjust_contrast(deep_space, starmap_color.a) * sky_behind_moon + moon_surface;
	float star_scint = textureLod(noise_tex, deep_space_uv + TIME * star_scintillation_speed, 0.0).r;
	star_scint = mix(1.0, star_scint * 1.5, star_scintillation);
	vec3 star_field = textureLod(star_field_texture, deep_space_uv, 0.0).rgb * star_field_color.rgb;
	star_field = clamp_rgb_to_unit(mix(star_field, star_field * star_scint, star_scintillation));
	deep_space += star_field * sky_behind_moon;
	sky_color += sun_disk + deep_space * angle_mult.z * horizon_blend;

	vec3 cloud_tint = mix(sun_light_color.rgb, clouds_night_color.rgb, angle_mult.w);
	if (horizon_blend > 0.0) {
		if (cirrus_visible) {
			vec4 cirrus_clouds = _render_cirrus_clouds(view_dir);
			float cirrus_alpha = clamp_to_unit(cirrus_clouds.a) * horizon_blend;
			vec3 cirrus_color = cirrus_clouds.rgb * cloud_tint * cirrus_intensity + scatter * cirrus_sky_tint_fade;
			sky_color = mix(sky_color, cirrus_color, cirrus_alpha);
			cloud_coverage = cirrus_alpha;
		}
		if (cumulus_visible) {
			vec4 cumulus_clouds = _render_cumulus_clouds(view_dir, sun_dir, scatter, cloud_tint);
			float cumulus_alpha = cumulus_clouds.a * horizon_blend;
			vec3 cumulus_color = cumulus_clouds.rgb + scatter * cumulus_sky_tint_fade;
			sky_color = mix(sky_color, cumulus_color, cumulus_alpha);
			cloud_coverage = 1.0 - (1.0 - cloud_coverage) * (1.0 - cumulus_alpha);
		}
	}

	sky_color = mix(sky_color, ground_color.rgb * scatter, clamp_to_unit((-sky_dir.y - atm_level_params.z) * 100.0));
	return apply_photo_tonemap(sky_color, color_correction.y, color_correction.x);
}

// Overlays
//------------------------------------------------------------------------------

vec4 _create_axis_angle_quat(vec3 rotation_axis, float rotation_angle) {
	return vec4(rotation_axis * sin(rotation_angle * 0.5), cos(rotation_angle * 0.5));
}

vec3 _rotate_vector_by_quat(vec3 source_vector, vec4 rotation_quat) {
	vec3 twice_cross = 2.0 * cross(rotation_quat.xyz, source_vector);
	return source_vector + rotation_quat.w * twice_cross + cross(rotation_quat.xyz, twice_cross);
}

// aligns the grid's z axis with the target pole, then spins it around that pole
vec3 _align_and_rotate_vector(vec3 sky_dir, vec3 target_dir, float rotation_angle) {
	vec3 grid_axis = vec3(0.0, 0.0, 1.0);
	target_dir = normalize(target_dir);
	vec3 align_axis = cross(grid_axis, target_dir);
	float align_angle = acos(dot(grid_axis, target_dir));
	float align_valid = step(0.0001, length(align_axis));
	align_axis = normalize(align_axis);
	vec4 align_quat = _create_axis_angle_quat(align_axis, align_angle);
	sky_dir = mix(sky_dir, _rotate_vector_by_quat(sky_dir, align_quat), align_valid);
	vec4 spin_quat = _create_axis_angle_quat(grid_axis, rotation_angle);
	return mix(sky_dir, _rotate_vector_by_quat(sky_dir, spin_quat), align_valid);
}

void _render_grid(vec3 sky_dir, vec3 pole_dir, float rotation_angle, vec4 line_color, float grid_spacing, float line_thickness, inout vec3 sky_color) {
	float spacing = max(grid_spacing, 0.001);
	float thickness = max(line_thickness, 0.0001);
	sky_dir = _align_and_rotate_vector(sky_dir, pole_dir, rotation_angle);

	float theta = acos(sky_dir.z);
	float circle_thickness = max(thickness, fwidth(theta));
	float circle_line = 1.0 - smoothstep(0.0, circle_thickness * 1.5, abs(mod(theta, spacing) - circle_thickness * 0.5));
	circle_line *= clamp_to_unit(thickness / circle_thickness);
	float north_pole = 1.0 - smoothstep(0.0, circle_thickness, theta);
	float south_pole = 1.0 - smoothstep(0.0, circle_thickness, abs(theta - PI));
	circle_line = max(circle_line, max(north_pole, south_pole));
	// darkens latitude lines towards the poles where they bunch up
	circle_line *= clamp(sin(theta), 0.2, 1.0);

	float phi = atan(sky_dir.y, sky_dir.x);
	float radial_thickness = max(thickness, fwidth(phi));
	float radial_line = 1.0 - smoothstep(0.0, radial_thickness * 1.5, abs(mod(phi + PI, spacing) - radial_thickness));
	radial_line *= clamp_to_unit(thickness / radial_thickness);

	sky_color += line_color.rgb * line_color.a * max(radial_line, circle_line);
}

// Dither and grain
//------------------------------------------------------------------------------

float _interleaved_gradient_noise(vec2 pixel_pos) {
	return fract(52.9829189 * fract(0.06711056 * pixel_pos.x + 0.00583715 * pixel_pos.y));
}

float _sky_grain(vec2 pixel_pos) {
	vec2 grain_seed = vec2(35.9898 * (sin(TIME) + 0.5), 15.002 * (cos(TIME) + 0.5));
	return (fract(sin(dot(pixel_pos, grain_seed)) * 43758.5453) - 0.5) * 2.0;
}

void sky() {
	vec3 sky_color = vec3(0.0);
	if (sky_visible) {
		float cloud_coverage;
		sky_color = _render_sky(EYEDIR, LIGHT0_DIRECTION, LIGHT1_DIRECTION, cloud_coverage);
		float dither_offset = (_interleaved_gradient_noise(FRAGCOORD.xy) - 0.5) / (DITHER_LEVELS - 1.0);
		vec3 dithered_color = sky_color + dither_offset + _sky_grain(FRAGCOORD.xy) * SKY_GRAIN_STRENGTH;
		// skips dither and grain where clouds cover the sky
		sky_color = clamp(mix(dithered_color, sky_color, smoothstep(0.05, 0.3, cloud_coverage)), 0.0, 1.0);
	}

	float grid_thickness = 0.0002;
	float grid_spacing = 0.261799; // 15 degrees
	vec3 zenith_dir = vec3(0.0, 1.0, 0.0);
	if (show_azimuthal_grid) {
		_render_grid(EYEDIR, zenith_dir, azimuthal_grid_rotation_offset, azimuthal_grid_color, grid_spacing, grid_thickness, sky_color);
	}
	if (show_equatorial_grid) {
		vec3 celestial_pole = _create_rotation_matrix(vec3(star_tilt, 0.0, 0.0)) * zenith_dir;
		float grid_rotation = star_rotation + star_rotation_offset + equatorial_grid_rotation_offset;
		_render_grid(EYEDIR, celestial_pole, grid_rotation, equatorial_grid_color, grid_spacing, grid_thickness, sky_color);
	}

	COLOR = sky_color;
}