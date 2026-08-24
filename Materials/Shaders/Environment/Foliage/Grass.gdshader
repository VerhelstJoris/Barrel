shader_type spatial;
render_mode cull_disabled;

uniform float size_small = 0.2f;
uniform float size_large = 0.6f;
uniform vec3 color_small: source_color = vec3(0.3, 0.6, 0.1);
uniform vec3 color_large: source_color = vec3(0.9, 0.9, 0.2);

//patchiness
group_uniforms patchiness;
uniform sampler2D patch_noise;
uniform float patch_scale = 5.0f;
varying float patch_factor;
group_uniforms;

//wind related
group_uniforms wind_movement;
uniform sampler2D wind_noise;
uniform float blade_bend_mult = 0.5f;
uniform float wind_strength = 0.1f;
uniform vec2 wind_direction = vec2(1.0, 0.0);
varying float current_wind_bend;
uniform float wind_ao_affect = 0.1f;
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
// The bend mask is now ONE accumulator texture for the whole world, sized to a
// window that follows the camera. It is anchored in world texel space and
// addressed toroidally: as the window slides, texels wrap rather than move, so
// a trail stays on the patch of ground it was pressed into.
//
// FoliageWorld writes bending_mask, bend_window_origin_texel, bend_res and
// bend_texels_per_m every frame -- leave them alone in the inspector. The old
// bending_mask_size_m is gone; the window size is bend_res / bend_texels_per_m.
uniform sampler2D bending_mask : filter_nearest;
uniform ivec2 bend_window_origin_texel;
uniform int bend_res = 1024;
uniform float bend_texels_per_m = 16.0f;
uniform float bending_mask_strength_horizontal = 2.0f;
uniform float bending_mask_strength_vertical = 2.0f;
uniform float bend_AO_efect_mult = 1.0f;
varying float bending_mask_strength;
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
uniform float clump_min_distance = 8.0f;
uniform float clump_max_distance = 25.0f;
uniform float clump_normal_flatten = 1.0f;
uniform float patch_scale_far_mult = 4.0f;
uniform float ao_far_flatten = 1.0f;
uniform float dist_jitter_amount = 4.0f;
varying float clump_factor_v;
group_uniforms;

float hash21(vec2 p)
{
	return fract(sin(dot(p, vec2(127.12, 311.7))) * 43758.545663);
}

// bend_res is a power of two, so the toroidal wrap is a bitmask. Do NOT use %
// here: integer modulo is undefined for negative operands, and world texel
// indices go negative across half the world.
int wrap_bend_texel(int v, int mask)
{
	return v & mask;
}

// Reads the accumulator at a world XZ position. Returns 0 outside the window,
// which is correct -- that ground is too far from the camera for bending to be
// legible anyway.
float sample_bend(vec2 world_xz)
{
	vec2 texel_pos = world_xz * bend_texels_per_m;
	vec2 rel = texel_pos - vec2(bend_window_origin_texel);

	if (rel.x < 0.0 || rel.y < 0.0 || rel.x >= float(bend_res) || rel.y >= float(bend_res))
	{
		return 0.0;
	}

	// Manual bilinear across the wrap. A plain linear sampler would blend
	// across the toroidal seam wherever the world texel index crosses a
	// multiple of bend_res, which shows up as a hairline artefact that drifts
	// around the window as the camera moves.
	vec2 t = texel_pos - 0.5;
	vec2 f = fract(t);
	ivec2 base = ivec2(floor(t));
	int m = bend_res - 1;

	int x0 = wrap_bend_texel(base.x, m);
	int x1 = wrap_bend_texel(base.x + 1, m);
	int y0 = wrap_bend_texel(base.y, m);
	int y1 = wrap_bend_texel(base.y + 1, m);

	float b00 = texelFetch(bending_mask, ivec2(x0, y0), 0).r;
	float b10 = texelFetch(bending_mask, ivec2(x1, y0), 0).r;
	float b01 = texelFetch(bending_mask, ivec2(x0, y1), 0).r;
	float b11 = texelFetch(bending_mask, ivec2(x1, y1), 0).r;

	return mix(mix(b00, b10, f.x), mix(b01, b11, f.x), f.y);
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
	float clump_factor = enable_clump_uniformity ? smoothstep(clump_min_distance, clump_max_distance, dist + dist_jitter) : 0.0;
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
	vec2 wind_position = wind_sample_pos / 10.0;
  	wind_position -= TIME * wind_direction * wind_strength;

  	current_wind_bend = texture(wind_noise, wind_position).x;

	current_wind_bend *= wind_strength;
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
	float distant_patch_scale = patch_scale * mix(1.0, patch_scale_far_mult, clump_factor);
	patch_factor = texture(patch_noise, NODE_POSITION_WORLD.xz / distant_patch_scale).r;
	VERTEX *= mix(size_small, size_large, patch_factor);

	// push the whole blade toward the up-facing tip normal as distance grows,
	NORMAL = mix(NORMAL, vec3(0.0, 1.0, 0.0), max(uv_bottom_to_top, clump_factor * clump_normal_flatten));
}

void fragment() {
	if (!FRONT_FACING)
	{
		NORMAL = -NORMAL;
	}
	
	float base_ao = uv_bottom_to_top - (current_wind_bend * wind_ao_affect);
	float bend_ao = bending_mask_strength * bend_AO_efect_mult;
	float flattened_base_ao = mix(base_ao, 1.0, clump_factor_v * ao_far_flatten);
	AO = clamp(flattened_base_ao - bend_ao, 0.0, 1.0);
	AO_LIGHT_AFFECT = 1.0;

	ALBEDO = mix(color_small, color_large, patch_factor);
	BACKLIGHT = vec3(0.2);

	ROUGHNESS = 0.4;
	SPECULAR = 0.15;
}