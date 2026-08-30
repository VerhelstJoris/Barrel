// Everything the blades and the terrain layer MUST agree on, declared once so
// the names cannot drift apart. Included by both Grass.gdshader and
// FoliageLayer.gdshaderinc; a repeated #include is ignored by the preprocessor.
// The editor will flag errors opening this alone -- it is a fragment, not a shader.

group_uniforms foliage_appearance;
uniform vec3 foliage_color_small : source_color = vec3(0.3, 0.6, 0.1);
uniform vec3 foliage_color_large : source_color = vec3(0.9, 0.9, 0.2);
// Base occlusion before distance flattening lifts it toward 1.0.
uniform float foliage_base_AO = 0.5f;
uniform float foliage_roughness = 0.4f;
uniform float foliage_specular = 0.15f;
uniform vec3 foliage_backlight : source_color = vec3(0.2);
group_uniforms;

group_uniforms foliage_patchiness;
uniform sampler2D foliage_patch_noise : hint_default_white;
uniform float foliage_patch_scale = 5.0f;
group_uniforms;

group_uniforms foliage_distant_uniformity;
// Distance at which blades and layer start converging on a shared look.
uniform float foliage_clump_min_distance = 8.0f;
// Distance at which that convergence completes.
uniform float foliage_clump_max_distance = 25.0f;
// Patch scale multiplier at full distance; patches coarsen as detail is lost.
uniform float foliage_patch_scale_far_mult = 4.0f;
// Lifts AO toward 1.0 at full distance.
uniform float foliage_ao_far_flatten = 1.0f;
// Fades normal detail out at full distance.
uniform float foliage_normal_flatten_far = 1.0f;
// Fades specular out at full distance; per-blade normals turn any highlight
// into sparkle once blades go sub-pixel.
uniform float foliage_specular_far_flatten = 1.0f;
// Pushes roughness toward 1 at full distance, broadening what highlight is left.
uniform float foliage_roughness_far_flatten = 0.5f;
group_uniforms;


// How far this position has converged on the distant look; 0 near, 1 far.
float foliage_clump_factor(float cam_dist)
{
	return smoothstep(foliage_clump_min_distance, foliage_clump_max_distance, cam_dist);
}


// How much features coarsen at this distance; shared so patches, gusts and
// warps all scale together.
float foliage_coarsen(float clump)
{
	return mix(1.0, foliage_patch_scale_far_mult, clump);
}


// The shared colour lookup: patches coarsen with distance on both sides.
float foliage_patch_factor(vec2 world_xz, float clump)
{
	return texture(foliage_patch_noise, world_xz / (foliage_patch_scale * foliage_coarsen(clump))).r;
}
