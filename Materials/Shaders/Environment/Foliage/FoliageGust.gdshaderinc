// A single large wave that sweeps across the whole world every so often, on top
// of the continuous per-blade wind.
//
// Every value here is a GLOBAL shader parameter written by GlobalEnvironmentManagerSingleton,
// The editor will flag errors opening this alone -- it is a fragment, not a shader.

// Travel direction; the manager keeps this equal to the wind direction.
global uniform vec2 foliage_gust_direction;
// Distance between crests, so seconds between waves is this over the gust speed.
global uniform float foliage_gust_wavelength_m;
// Metres the crest has travelled, wrapped to one wavelength; replaces the old TIME * speed term.
global uniform float foliage_gust_travel_m;
// Fraction of the cycle the wave occupies; small is a sharp gust, large is a swell.
global uniform float foliage_gust_width;
// Master multiplier; scales every consumer at once without retuning each.
global uniform float foliage_gust_strength;
// Concentrates the wave toward its crest; 1 is a soft swell, 3 is a snap.
global uniform float foliage_gust_sharpness;
// Steepens the arriving edge and lengthens the recovery; 0 is symmetric.
global uniform float foliage_gust_asymmetry;
// Backswing behind the crest, so grass overshoots instead of easing to rest.
global uniform float foliage_gust_rebound;
// Varies amplitude along the crest so the wave is not a uniform band.
global uniform float foliage_gust_patchiness;
// Noise that bends the crest and varies its strength; MUST have repeat enabled or the phase wrap seams.
global uniform sampler2D foliage_gust_wobble_noise;
// Metres the crest snakes forward and back along its length.
global uniform float foliage_gust_wobble_m;
// Length of one undulation along the crest; smaller is a busier edge.
global uniform float foliage_gust_wobble_scale_m;
// Wobble scroll, wrapped at 10.0 so the 1.0x, 2.3x and 0.7x samples below all wrap together.
global uniform float foliage_gust_wobble_phase;
// Second, finer octave of wobble; 0 is one smooth bend, 1 is ragged.
global uniform float foliage_gust_wobble_detail;


// Rises to foliage_gust_strength at the crest and returns to 0, dipping
// slightly negative behind it when rebound is on -- consumers should treat a
// negative value as a backswing, not clamp it away.
float foliage_gust(vec2 world_xz)
{
	float direction_length = length(foliage_gust_direction);
	vec2 dir = direction_length > 0.0001 ? foliage_gust_direction / direction_length : vec2(1.0, 0.0);
	float along = dot(world_xz, dir);
	// Position ALONG the crest, which is what the wobble and patchiness vary
	// over -- sampling those in plain world space varies them through the wave
	// as well, which smears the profile instead of bending the crest.
	float across = dot(world_xz, vec2(-dir.y, dir.x));

	if (foliage_gust_wobble_m > 0.0)
	{
		// The second axis is the pushed wobble phase, so the crest reshapes as it
		// travels rather than carrying a distortion baked into fixed world positions.
		float w0 = texture(foliage_gust_wobble_noise,
				vec2(across / foliage_gust_wobble_scale_m,
					foliage_gust_wobble_phase)).r - 0.5;
		float w1 = texture(foliage_gust_wobble_noise,
				vec2(across / (foliage_gust_wobble_scale_m * 0.27) + 0.37,
					foliage_gust_wobble_phase * 2.3 + 0.61)).r - 0.5;
		along += (w0 + w1 * foliage_gust_wobble_detail) * 2.0 * foliage_gust_wobble_m;
	}

	float phase = fract((along - foliage_gust_travel_m) / foliage_gust_wavelength_m);

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
	// others. Also keyed to `across` and the wobble phase, so it stays with the wave.
	if (foliage_gust_patchiness > 0.0)
	{
		float amp = texture(foliage_gust_wobble_noise,
				vec2(across / (foliage_gust_wobble_scale_m * 0.5) + 0.13,
					foliage_gust_wobble_phase * 0.7 + 0.29)).r;
		wave *= mix(1.0, amp, foliage_gust_patchiness);
	}

	return wave * foliage_gust_strength;
}
