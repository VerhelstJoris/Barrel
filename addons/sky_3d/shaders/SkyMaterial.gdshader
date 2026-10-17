// Copyright (c) 2023-2025 Cory Petkovsek and Contributors
// Copyright (c) 2021 J. Cuellar

shader_type sky;

const float SKY_GRAIN_STRENGTH = 0.003;
const float DITHER_LEVELS = 1276.0;
const int CUMULUS_STEP = 6;

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
uniform float cumulus_intensity = 0.6;
uniform float cumulus_coverage = 0.55;
uniform float cumulus_thickness = 0.0243;
uniform float cumulus_detail_amount : hint_range(0.0, 1.0) = 0.4;
uniform float cumulus_absorption = 2.0;
uniform float cumulus_noise_freq = 2.7;
uniform float cumulus_sky_tint_fade = 0.0;
uniform float cumulus_size = 0.5;
uniform vec2 cumulus_position = vec2(0.0);
uniform sampler2D cumulus_texture : filter_linear, repeat_enable;
uniform vec3 cumulus_partial_mie_phase = vec3(0.95756, 1.04244, 0.412);
uniform float cumulus_mie_intensity = 1.0;
uniform float cumulus_evolution_speed = 0.005;
uniform float cumulus_detail_evolution = 1.6;
uniform float cumulus_coverage_variation = 0.15;
uniform float cumulus_wind_stretch : hint_range(1.0, 4.0) = 1.5;
uniform float cumulus_warp_strength = 0.3;
uniform float cumulus_warp_follow : hint_range(0.0, 1.0) = 0.6;

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

bool _ray_sphere_intersect(float sphere_radius, vec3 ray_origin, vec3 ray_dir, out float hit_distance, out vec3 hit_position) {
	ray_origin += vec3(0.0, 450.0, 0.0);
	float dir_length_sq = dot(ray_dir, ray_dir);
	float linear_term = 2.0 * dot(ray_origin, ray_dir);
	float constant_term = dot(ray_origin, ray_origin) - sphere_radius * sphere_radius;
	float discriminant = linear_term * linear_term - 4.0 * dir_length_sq * constant_term;
	float hit_valid = step(0.0, discriminant);
	float discriminant_root = sqrt(max(discriminant, 0.0));
	float far_hit = 0.5 * (-linear_term + discriminant_root);
	float near_hit = 0.5 * (-linear_term - discriminant_root);
	hit_distance = mix(near_hit, far_hit, step(near_hit, far_hit) * step(0.0, far_hit));
	hit_distance = mix(0.0, hit_distance, step(0.0, hit_distance) * hit_valid);
	hit_position = mix(vec3(0.0), ray_origin + hit_distance * ray_dir, step(0.0, hit_distance) * hit_valid);
	return bool(step(0.0, hit_distance) * hit_valid);
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

// filters in float precision since hardware bilinear weights are only 8-bit and step visibly under heavy magnification
float _sample_cumulus_smooth(vec2 sample_uv, vec2 texture_res) {
	vec2 texel_pos = sample_uv * texture_res - 0.5;
	vec2 base_texel = floor(texel_pos);
	vec2 texel_fract = texel_pos - base_texel;
	texel_fract = texel_fract * texel_fract * (3.0 - 2.0 * texel_fract);
	vec4 texel_quad = textureGather(cumulus_texture, (base_texel + 1.0) / texture_res);
	float row_low = mix(texel_quad.w, texel_quad.z, texel_fract.x);
	float row_high = mix(texel_quad.x, texel_quad.y, texel_fract.x);
	return mix(row_low, row_high, texel_fract.y);
}

float _sample_cumulus_noise(vec3 noise_pos) {
	vec3 slice_pos = noise_pos * 0.01;
	slice_pos.z *= 512.0;
	vec2 slice_offset = vec2(0.317, 0.123);
	vec2 texture_res = vec2(textureSize(cumulus_texture, 0));
	float slice_index = floor(slice_pos.z);
	// wraps the per-slice offsets into 0-1 so uvs keep their precision as cumulus_position grows
	float slice_low = _sample_cumulus_smooth(slice_pos.xy + fract(slice_offset * slice_index), texture_res);
	float slice_high = _sample_cumulus_smooth(slice_pos.xy + fract(slice_offset * (slice_index + 1.0)), texture_res);
	return mix(slice_low, slice_high, smoothstep(0.0, 1.0, fract(slice_pos.z)));
}

// each octave scrolls through the vertical noise axis so shapes morph, finer octaves faster
float _calc_cumulus_fbm_evolving(vec3 noise_pos, float lacunarity, float evolve_amount) {
	vec3 octave_pos = noise_pos;
	vec3 octave_evolve = vec3(0.0, evolve_amount, 0.0);
	float base_density = 0.51749673 * _sample_cumulus_noise(octave_pos + octave_evolve);
	octave_pos *= lacunarity;
	octave_evolve *= cumulus_detail_evolution;
	float detail_density = 0.25584929 * _sample_cumulus_noise(octave_pos + octave_evolve);
	octave_pos *= lacunarity;
	octave_evolve *= cumulus_detail_evolution;
	detail_density += 0.12527603 * _sample_cumulus_noise(octave_pos + octave_evolve);
	octave_pos *= lacunarity;
	octave_evolve *= cumulus_detail_evolution;
	detail_density += 0.06255931 * _sample_cumulus_noise(octave_pos + octave_evolve);
	// fades the detail octaves and rescales so overall density and coverage stay comparable
	return (base_density + detail_density * cumulus_detail_amount) * 0.96118136 / (0.51749673 + 0.44368463 * cumulus_detail_amount);
}

float _sample_cumulus_shape(vec3 layer_pos, vec3 wind_offset, vec3 travel_axis) {
	vec3 noise_pos = layer_pos * 0.0212242 - wind_offset;
	// compresses the along-travel axis so shapes elongate in the travel direction
	noise_pos -= travel_axis * (dot(noise_pos, travel_axis) * (1.0 - 1.0 / cumulus_wind_stretch));
	return 2.0 * _calc_cumulus_fbm_evolving(noise_pos, cumulus_noise_freq, TIME * cumulus_evolution_speed);
}

float _calc_cumulus_density(float shape_noise, float layer_height, float local_coverage) {
	float coverage_ramp = smoothstep(0.0, (1.0 - local_coverage) * 3.5 + layer_height, shape_noise);
	return clamp_to_unit((shape_noise * coverage_ramp - (1.0 - coverage_ramp)) / coverage_ramp);
}

vec4 _render_cumulus_clouds(vec3 view_dir, float moon_scatter_mult, vec3 sun_dir, vec3 moon_dir) {
	float hit_distance;
	vec3 shell_hit;
	if (!_ray_sphere_intersect(500.0, vec3(0.0), view_dir, hit_distance, shell_hit)) {
		return vec4(0.0);
	}
	vec3 wind_offset = -vec3(cumulus_position.x, 0.0, cumulus_position.y);
	vec3 travel_axis = -vec3(cloud_direction.x, 0.0, cloud_direction.y);
	vec3 layer_pos = vec3(shell_hit.x, 500.0, shell_hit.z) * cumulus_size;
	
	// slow field the clouds drift through, deforming them and shifting coverage as they pass
	float drift_field = _sample_cumulus_noise((layer_pos * 0.0212242 - wind_offset * cumulus_warp_follow) * 0.35) - 0.5;
	vec3 drift_offset = wind_offset - travel_axis * (drift_field * cumulus_warp_strength);
	float local_coverage = clamp_to_unit(cumulus_coverage + drift_field * cumulus_coverage_variation);

	vec2 light_cos_angles = vec2(dot(sun_dir, view_dir), dot(moon_dir, view_dir));
	vec3 mie_phase = calc_mie_phase(light_cos_angles.x, cumulus_partial_mie_phase) * atm_sun_mie_tint.rgb
		+ calc_mie_phase(light_cos_angles.y, cumulus_partial_mie_phase) * moon_scatter_mult;
	vec3 light_transmit = vec3(1.0) + mie_phase * cumulus_mie_intensity;
	vec3 scatter_sum = vec3(0.0);
	float cloud_alpha = 0.0;
	float march_step = float(CUMULUS_STEP) * cumulus_thickness;

	// one shared noise sample per pixel keeps the layers as nested contours instead of offset copies
	float shape_noise = _sample_cumulus_shape(layer_pos, drift_offset, travel_axis);
	for (int layer_index = 0; layer_index < CUMULUS_STEP; layer_index++) {
		float layer_height = float(layer_index) * 0.1;
		float layer_density = _calc_cumulus_density(shape_noise, layer_height, local_coverage);
		float layer_transmit = clamp_to_unit(exp(-cumulus_absorption * layer_density * march_step));
		light_transmit *= layer_transmit;
		scatter_sum += light_transmit * (exp(layer_height) * 0.571428571) * layer_density * march_step;
		cloud_alpha += (1.0 - layer_transmit) * (1.0 - cloud_alpha);
	}
	return vec4(scatter_sum, cloud_alpha);
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
			vec4 cumulus_clouds = _render_cumulus_clouds(view_dir, angle_mult.z, sun_dir, moon_dir);
			float cumulus_alpha = smoothstep(0.1, 0.45, cumulus_clouds.a) * horizon_blend;
			vec3 cumulus_color = cumulus_clouds.rgb * cloud_tint * cumulus_intensity + scatter * cumulus_sky_tint_fade;
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
		sky_color = clamp(mix(dithered_color, sky_color, step(0.2, cloud_coverage)), 0.0, 1.0);
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
