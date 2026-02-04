shader_type spatial;
render_mode blend_mix, unshaded;

uniform vec3 Color = vec3(1,1,1);
uniform float Opacity = 1.0;

void fragment() {
	// Called for every pixel the material is visible on.
	ALBEDO = vec3(1,1,1);
	ALPHA = Opacity;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
