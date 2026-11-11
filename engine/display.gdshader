shader_type canvas_item;

// The game's last step to the screen, run on the Screen container at device
// resolution. A display mode swaps each palette colour (src) for the mode's
// (dst); anything drawn off the palette, like pure black, takes its nearest
// palette colour's swap. CRT lines then darken one device row in every
// `scale` rows by 35%: the bottom row of each chunky pixel, counted from the
// top of the game (offset_y is the letterbox bar above it). Rows are counted
// in ints, so it stays exact at mediump precision.

uniform vec3 src[16];
uniform vec3 dst[16];
uniform bool use_mode = false;
uniform bool crt = false;
uniform float scale = 1.0;
uniform int offset_y = 0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (use_mode) {
		int best = 0;
		float best_d = 100.0;
		for (int i = 0; i < 16; i++) {
			vec3 d = c.rgb - src[i];
			float dd = dot(d, d);
			if (dd < best_d) {
				best_d = dd;
				best = i;
			}
		}
		c.rgb = dst[best];
	}
	int s = int(scale);
	if (crt && s >= 2 && (int(FRAGCOORD.y) - offset_y) % s == s - 1) {
		c.rgb *= 0.65;
	}
	COLOR = c;
}
