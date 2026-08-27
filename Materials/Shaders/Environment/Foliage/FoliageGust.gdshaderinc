// A single large wave that sweeps across the whole world every so often, on top
// of the continuous per-blade wind.
//
// Included by BOTH Grass.gdshader and FoliageLayer.gdshaderinc, because the
// wave has to be in phase across the frontier -- two copies of this maths would
// drift and the wave would visibly break where the blades stop.
// The editor will flag errors opening this alone -- it is a fragment, not a shader.

group_uniforms foliage_gust;
// Distance between crests, so seconds between waves is this over the speed.
uniform float foliage_gust_wavelength_m = 300.0f;
// Metres per second the crest travels.
uniform float foliage_gust_speed = 20.0f;
// Fraction of the cycle the wave occupies; small is a sharp gust, large is a swell.
uniform float foliage_gust_width = 0.25f;
// Noise that bends the crest so it is not a ruler-straight line; 0 disables.
uniform sampler2D foliage_gust_wobble_noise : hint_default_white;
uniform float foliage_gust_wobble_m = 0.0f;
group_uniforms;


// 0 outside the wave, rising smoothly to 1 at the crest.
float foliage_gust(vec2 world_xz, vec2 direction)
{
	float along = dot(world_xz, normalize(direction));

	if (foliage_gust_wobble_m > 0.0)
	{
		float wobble = texture(foliage_gust_wobble_noise,
				world_xz / (foliage_gust_wavelength_m * 0.5)).r;
		along += (wobble - 0.5) * 2.0 * foliage_gust_wobble_m;
	}

	float phase = fract((along - TIME * foliage_gust_speed) / foliage_gust_wavelength_m);
	float from_crest = abs(phase - 0.5);
	return 1.0 - smoothstep(0.0, max(foliage_gust_width, 0.001) * 0.5, from_crest);
}
