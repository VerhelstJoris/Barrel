shader_type spatial;

uniform vec3 color_small : source_color = vec3(0.3, 0.6, 0.1);
uniform vec3 color_large : source_color = vec3(0.9, 0.9, 0.2);

group_uniforms patchiness;
uniform sampler2D patch_noise;
uniform float patch_scale = 5.0f;
group_uniforms;

group_uniforms wind_movement;
uniform sampler2D wind_noise;
uniform float wind_noise_scale = 10.0f;
uniform float wind_strength = 0.1f;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_highlight_strength = 0.15f;
group_uniforms;

group_uniforms bend_mask_related;
uniform sampler2D bending_mask;
uniform float bending_mask_size_m = 200.0f;
uniform float bend_darken_strength = 0.3f;
uniform float bend_AO_effect_mult = 1.0f;
group_uniforms;

group_uniforms fake_relief;
uniform bool enable_fake_relief = true;
uniform float relief_height = 0.15f;
group_uniforms;

uniform float base_AO = 0.5f;	//approxsimate average AO

varying vec3 world_pos;

void vertex()
{
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	if (enable_fake_relief)
	{
		float h = texture(patch_noise, world_pos.xz / patch_scale).r;
		VERTEX.y += h * relief_height;
	}
}

void fragment()
{
	float patch_factor = texture(patch_noise, world_pos.xz / patch_scale).r;
	vec3 base_color = mix(color_small, color_large, patch_factor);

	// moving noise streak stands in for wind-bent blades catching the light
	vec2 wind_uv = world_pos.xz / wind_noise_scale - TIME * wind_direction * wind_strength;
	float wind_val = texture(wind_noise, wind_uv).r;
	base_color += wind_val * wind_highlight_strength;

	vec2 bend_uv = 
	vec2(
		1.0 - mod(abs(world_pos.x), bending_mask_size_m) / bending_mask_size_m,
		1.0 - mod(abs(world_pos.z), bending_mask_size_m) / bending_mask_size_m
	);
	float bend_mask = texture(bending_mask, bend_uv).r;
	base_color = mix(base_color, base_color * (1.0 - bend_darken_strength), bend_mask);

	ALBEDO = base_color;
	AO = clamp(base_AO - bend_mask * bend_AO_effect_mult, 0.0, 1.0);
	AO_LIGHT_AFFECT = 1.0;
	BACKLIGHT = vec3(0.2);

	ROUGHNESS = 0.4;
	SPECULAR = 0.15;
}
