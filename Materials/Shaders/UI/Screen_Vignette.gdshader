shader_type canvas_item;

uniform float alpha = 1.0;
uniform float inner_radius = 0.0;
uniform float outer_radius = 1.0;
uniform float edge_mult = 1;
uniform vec2 uv_offset = vec2(0.0,0.0);

void fragment() {
	vec2 uv_to_use = UV + uv_offset;
	float x = abs(uv_to_use.r-(0.5))*2.0 * edge_mult;
	float y = abs(uv_to_use.g-(0.5))*2.0 * edge_mult;
	float q = 1.0-(1.0-sqrt(x*x+y*y)/outer_radius)/(1.0-inner_radius);
	COLOR = vec4(0, 0, 0, q*alpha);
}

