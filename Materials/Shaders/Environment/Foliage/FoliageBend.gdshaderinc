// Reads the foliage bend accumulator. Include in any material that needs to
// know how flattened the grass is at a world position. Covers only how to READ
// the value; how a material reacts to it stays in that material.
// The editor will flag errors opening this alone -- it is a fragment, not a shader.

// Accumulator for the whole world, anchored in world texel space and wrapped.
uniform sampler2D bending_mask : filter_nearest;
// Window's lower corner in world texels; FoliageWorld writes this every frame.
uniform ivec2 bend_window_origin_texel;
// Accumulator side length in texels. Must be a power of two.
uniform int bend_res = 1024;
// Accumulator resolution, so window size in metres is bend_res / this.
uniform float bend_texels_per_m = 16.0f;


// Bitmask wrap; integer % is undefined for the negative indices this sees.
int wrap_bend_texel(int v, int mask)
{
	return v & mask;
}


// Returns 0 outside the window, where bending is too distant to read anyway.
float sample_bend(vec2 world_xz)
{
	vec2 texel_pos = world_xz * bend_texels_per_m;
	vec2 rel = texel_pos - vec2(bend_window_origin_texel);

	if (rel.x < 0.0 || rel.y < 0.0 || rel.x >= float(bend_res) || rel.y >= float(bend_res))
	{
		return 0.0;
	}

	// Manual bilinear: a linear sampler would blend across the toroidal seam.
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
