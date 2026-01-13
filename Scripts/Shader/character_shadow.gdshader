shader_type spatial;
render_mode depth_draw_always;

uniform bool first_person_mode = false;

void fragment() {
	if (first_person_mode) {
		ALPHA = 0.0;
	} else {
		ALPHA = 1.0;
		// Add your normal texture/color code here
	}
}