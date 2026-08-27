// A single large wave that sweeps across the whole world every so often, on top
// of the continuous per-blade wind.
//
// Included by BOTH Grass.gdshader and FoliageLayer.gdshaderinc, because the
// wave has to be in phase across the frontier -- two copies of this maths would
// drift and the wave would visibly break where the blades stop.
// The editor will flag errors opening this alone -- it is a fragment, not a shader.

group_uniforms foliage_gust;
// Travel direction; keep matched to the per-blade wind direction.
uniform vec2 foliage_gust_direction = vec2(1.0, 0.0);
// Distance between crests, so seconds between waves is this over the speed.
uniform float foliage_gust_wavelength_m = 300.0f;
// Metres per second the crest travels.
uniform float foliage_gust_speed = 20.0f;
// Fraction of the cycle the wave occupies; small is a sharp gust, large is a swell.
uniform float foliage_gust_width = 0.25f;
// Master multiplier; scales every consumer at once without retuning each.
uniform float foliage_gust_strength = 1.0f;
// Concentrates the wave toward its crest; 1 is a soft swell, 3 is a snap.
uniform float foliage_gust_sharpness = 1.5f;
// Steepens the arriving edge and lengthens the recovery; 0 is symmetric.
uniform float foliage_gust_asymmetry = 0.5f;
// Backswing behind the crest, so grass overshoots instead of easing to rest.
uniform float foliage_gust_rebound = 0.15f;
// Varies amplitude along the crest so the wave is not a uniform band.
uniform float foliage_gust_patchiness = 0.35f;
// Noise that bends the crest and varies its strength; 0 wobble disables the bend.
uniform sampler2D foliage_gust_wobble_noise : hint_default_white;
// Metres the crest snakes forward and back along its length.
uniform float foliage_gust_wobble_m = 30.0f;
// Length of one undulation along the crest; smaller is a busier edge.
uniform float foliage_gust_wobble_scale_m = 200.0f;
// How fast the crest shape evolves, so no two passes look the same.
uniform float foliage_gust_wobble_speed = 0.02f;
// Second, finer octave of wobble; 0 is one smooth bend, 1 is ragged.
uniform float foliage_gust_wobble_detail = 0.4f;
group_uniforms;


// Rises to foliage_gust_strength at the crest and returns to 0, dipping
// slightly negative behind it when rebound is on -- consumers should treat a
// negative value as a backswing, not clamp it away.
float foliage_gust(vec2 world_xz)
{
	vec2 dir = normalize(foliage_gust_direction);
	float along = dot(world_xz, dir);
	// Position ALONG the crest, which is what the wobble and patchiness vary
	// over -- sampling those in plain world space varies them through the wave
	// as well, which smears the profile instead of bending the crest.
	float across = dot(world_xz, vec2(-dir.y, dir.x));

	if (foliage_gust_wobble_m > 0.0)
	{
		// The second axis is TIME, so the crest reshapes as it travels rather
		// than carrying a distortion baked into fixed world positions.
		float w0 = texture(foliage_gust_wobble_noise,
				vec2(across / foliage_gust_wobble_scale_m,
					TIME * foliage_gust_wobble_speed)).r - 0.5;
		float w1 = texture(foliage_gust_wobble_noise,
				vec2(across / (foliage_gust_wobble_scale_m * 0.27) + 0.37,
					TIME * foliage_gust_wobble_speed * 2.3 + 0.61)).r - 0.5;
		along += (w0 + w1 * foliage_gust_wobble_detail) * 2.0 * foliage_gust_wobble_m;
	}

	float phase = fract((along - TIME * foliage_gust_speed) / foliage_gust_wavelength_m);

	// Signed distance from the crest. The wave travels along +direction, so a
	// point meets the phase > 0.5 side first: that is the leading edge.
	float offset = phase - 0.5;
	float half_width = max(foliage_gust_width, 0.001) * 0.5;

	// Compress the leading side and stretch the trailing one, so the wave
	// arrives abruptly and releases slowly, the way grass snaps over and springs
	// back. This is what separates a gust from a sine bump.
	float lead = half_width * (1.0 - foliage_gust_asymmetry);
	float tail = half_width * (1.0 + foliage_gust_asymmetry);
	float span = offset > 0.0 ? lead : tail;

	float t = clamp(abs(offset) / max(span, 0.0001), 0.0, 1.0);
	float wave = pow(1.0 - smoothstep(0.0, 1.0, t), max(foliage_gust_sharpness, 0.001));

	// Shallow negative lobe trailing the crest: the overshoot as grass recoils.
	if (foliage_gust_rebound > 0.0)
	{
		float lobe = 1.0 - smoothstep(0.0, tail, abs(offset + tail * 1.6));
		wave -= lobe * foliage_gust_rebound;
	}

	// Amplitude varies along the crest, so some stretches gust harder than
	// others. Also keyed to `across` and TIME, so it stays with the wave.
	if (foliage_gust_patchiness > 0.0)
	{
		float amp = texture(foliage_gust_wobble_noise,
				vec2(across / (foliage_gust_wobble_scale_m * 0.5) + 0.13,
					TIME * foliage_gust_wobble_speed * 0.7 + 0.29)).r;
		wave *= mix(1.0, amp, foliage_gust_patchiness);
	}

	return wave * foliage_gust_strength;
}
