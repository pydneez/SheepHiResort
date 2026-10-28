shader_type canvas_item;
// Recolours a sheep part painted in greys (gradient map):
//   #ffffff -> highlight   #c0c0c0 -> base   #808080 -> shadow   #404040 -> deep
// Greys between two steps blend between their colours, so soft brush edges
// stay smooth. Very dark pixels (outlines) and pixels with colour in them are
// left exactly as drawn.

uniform vec4 highlight : source_color = vec4(1.0);
uniform vec4 base_colour : source_color = vec4(0.75, 0.75, 0.75, 1.0);
uniform vec4 shadow : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 deep : source_color = vec4(0.25, 0.25, 0.25, 1.0);

const float STEP_HIGHLIGHT = 1.0;
const float STEP_BASE = 0.753;     // #c0
const float STEP_SHADOW = 0.502;   // #80
const float STEP_DEEP = 0.251;     // #40
const float OUTLINE_BELOW = 0.19;  // darker than this = outline, kept as drawn

void fragment() {
	vec3 c = COLOR.rgb;
	float grey = (c.r + c.g + c.b) / 3.0;
	float spread = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	if (spread < 0.08 && grey > OUTLINE_BELOW) {
		vec3 shade;
		if (grey >= STEP_BASE) {
			shade = mix(base_colour.rgb, highlight.rgb, (grey - STEP_BASE) / (STEP_HIGHLIGHT - STEP_BASE));
		} else if (grey >= STEP_SHADOW) {
			shade = mix(shadow.rgb, base_colour.rgb, (grey - STEP_SHADOW) / (STEP_BASE - STEP_SHADOW));
		} else if (grey >= STEP_DEEP) {
			shade = mix(deep.rgb, shadow.rgb, (grey - STEP_DEEP) / (STEP_SHADOW - STEP_DEEP));
		} else {
			// Between the outline and the deep shadow (soft outline edges).
			shade = mix(c, deep.rgb, (grey - OUTLINE_BELOW) / (STEP_DEEP - OUTLINE_BELOW));
		}
		COLOR.rgb = shade;
	}
}
