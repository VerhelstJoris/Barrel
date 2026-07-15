shader_type spatial;
render_mode cull_disabled;

uniform float size_small = 0.2;
uniform float size_large = 0.6;
uniform vec3 color_small: source_color = vec3(0.3, 0.6, 0.1);
uniform vec3 color_large: source_color = vec3(0.9, 0.9, 0.2);

//patchiness
group_uniforms patchiness;
uniform sampler2D patch_noise;
uniform float patch_scale = 5.0;
varying float patch_factor;
group_uniforms;

//wind related
group_uniforms wind_movement;
uniform sampler2D wind_noise;
uniform float blade_bend_mult = 0.5;
uniform float wind_strength = 0.1;
uniform vec2 wind_direction = vec2(1.0, 0.0);
varying float current_wind_bend;
uniform float wind_ao_affect = 0.1;
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
uniform float curve_width_shape_mult = 1.0;
uniform sampler2D bending_mask;
uniform float bending_mask_size_m = 200.0;
varying float bend_factor;
group_uniforms;

void vertex()
{
	if(enable_LOD_divide)
	{
		// calculate the distance of this blade to the camera
		vec3 world_camera = (INV_VIEW_MATRIX * vec4(vec3(0.0), 1.0)).xyz;
		vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float dist = distance(world_position.xyz, world_camera);

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

	vec2 wind_position = NODE_POSITION_WORLD.xz / 10.0;
  	wind_position -= TIME * wind_direction * wind_strength;

  	current_wind_bend = texture(wind_noise, wind_position).x;

	current_wind_bend *= wind_strength;
	current_wind_bend *= uv_bottom_to_top * 2.0;

	mat4 inv_model = inverse(MODEL_MATRIX);
  	vec2 local_direction = (inv_model * vec4(wind_direction.x, 0.0, wind_direction.y, 0.0)).xz;

  	VERTEX.xz += current_wind_bend * local_direction;
	VERTEX.xz += blade_bend_mult * pow(uv_bottom_to_top, 2.0);	// bend the blade in the direction this is positioned in

	patch_factor = texture(patch_noise, NODE_POSITION_WORLD.xz / patch_scale).r;
	VERTEX *= mix(size_small, size_large, patch_factor);
	
	vec2 world_coord = vec2(1.0-mod(abs(NODE_POSITION_WORLD.x),bending_mask_size_m) / bending_mask_size_m,
	 1.0-mod(abs(NODE_POSITION_WORLD.z),bending_mask_size_m) / bending_mask_size_m);
	bend_factor = texture(bending_mask, world_coord).x;

	NORMAL = mix(NORMAL, vec3(0.0, 1.0, 0.0), uv_bottom_to_top);
}

void fragment() {
	if (!FRONT_FACING)
	{
		NORMAL = -NORMAL;
	}
	
	ALBEDO = vec3(bend_factor,0,0);
	//AO = uv_bottom_to_top - (current_wind_bend * wind_ao_affect);
	//AO_LIGHT_AFFECT = 1.0;

	//ALBEDO = mix(color_small, color_large, patch_factor);
	//BACKLIGHT = vec3(0.2);

	//ROUGHNESS = 0.4;
	//SPECULAR = 0.2;
}