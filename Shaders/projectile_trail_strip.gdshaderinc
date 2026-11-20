uniform sampler2D trail_points_texture : filter_nearest, repeat_disable;
uniform int trail_smooth_steps = 3;
uniform int trail_head_steps = 3;

vec2 _control_point(int index, int count, int row) {
	return texelFetch(trail_points_texture, ivec2(clamp(index, 0, count - 1), row), 0).xy;
}

vec2 _curve_point(int index, int count, int row) {
	if (count == 2) {
		return _control_point(index, count, row);
	}
	float coordinate = float(index) / float(trail_smooth_steps);
	int segment = min(int(floor(coordinate)), count - 2);
	float t = coordinate - float(segment);
	float t2 = t * t;
	float t3 = t2 * t;
	vec2 p0 = _control_point(segment - 1, count, row);
	vec2 p1 = _control_point(segment, count, row);
	vec2 p2 = _control_point(segment + 1, count, row);
	vec2 p3 = _control_point(segment + 2, count, row);
	return 0.5 * (
		2.0 * p1
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	);
}

vec2 _strip_point(int index, int count, int row, int body_steps, vec2 head_extension) {
	if (index <= body_steps) {
		return _curve_point(index, count, row);
	}
	float progress = float(index - body_steps) / float(trail_head_steps);
	return _control_point(count - 1, count, row) + head_extension * progress;
}

void vertex() {
	// paired outer/inner instances share a trajectory row without packing row ids into low-precision custom data.
	int row = INSTANCE_ID / TRAIL_LAYERS;
	int count = max(int(INSTANCE_CUSTOM.x + 0.5), 2);
	int body_steps = count == 2 ? 1 : (count - 1) * trail_smooth_steps;
	vec2 heading = _control_point(count - 1, count, row) - _curve_point(body_steps - 1, count, row);
	if (all(lessThan(abs(heading), vec2(0.00001)))) {
		heading = texelFetch(trail_points_texture, ivec2(0, row), 0).zw;
	}
	bool has_extension = INSTANCE_CUSTOM.y > 0.0 && any(greaterThanEqual(abs(heading), vec2(0.00001)));
	vec2 head_extension = has_extension ? normalize(heading) * INSTANCE_CUSTOM.y : vec2(0.0);
	int last_index = body_steps + (has_extension ? trail_head_steps : 0);
	// unused samples collapse to the endpoint while young trails retain the original sampling density.
	int index = min(int(VERTEX.x + 0.5), last_index);
	vec2 center = _strip_point(index, count, row, body_steps, head_extension);
	vec2 previous = _strip_point(max(index - 1, 0), count, row, body_steps, head_extension);
	vec2 next = _strip_point(min(index + 1, last_index), count, row, body_steps, head_extension);
	vec2 tangent = next - previous;
	vec2 normal = all(lessThan(abs(tangent), vec2(0.00001))) ? vec2(0.0, -1.0) : normalize(vec2(tangent.y, -tangent.x));
	float progress = min(float(index) / float(body_steps), 1.0);
	float extension_progress = float(max(index - body_steps, 0)) / float(trail_head_steps);
	float head_fade = 1.0 - smoothstep(0.0, 1.0, extension_progress);
	VERTEX = center + normal * VERTEX.y * INSTANCE_CUSTOM.z * smoothstep(0.0, 1.0, progress) * head_fade;
	COLOR.a *= pow(progress, 1.35) * head_fade;
}
