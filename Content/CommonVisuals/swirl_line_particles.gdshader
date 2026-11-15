shader_type particles;
render_mode disable_velocity, disable_force;

uniform vec2 line_start;
uniform vec2 line_delta;
uniform vec4 swirl_color : source_color = vec4(1.0);
uniform float half_width = 5.0;
uniform vec2 sprite_scale = vec2(0.027, 0.051);
uniform vec2 drift_speed = vec2(4.0, 12.0);
uniform float angle_noise = 0.0;
uniform bool forward_only = false;
uniform float flow_strength = 1.0;

float swirl_random(inout uint state) {
	state = state * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return float(((word >> 22u) ^ word) & 16777215u) / 16777216.0;
}

void start() {
	float line_length = length(line_delta);
	ACTIVE = line_length > 0.0001;
	uint state = RANDOM_SEED ^ NUMBER;
	vec2 direction = ACTIVE ? line_delta / line_length : vec2(1.0, 0.0);
	vec2 normal = vec2(-direction.y, direction.x);
	float along = swirl_random(state);
	float lateral = mix(-half_width, half_width, swirl_random(state));
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xy = line_start + line_delta * along + normal * lateral;

	vec2 heading = direction;
	if (!forward_only) {
		float sign_along = swirl_random(state) < 0.5 ? -1.0 : 1.0;
		heading = normalize(direction * sign_along + normal * mix(-0.35, 0.35, swirl_random(state)));
		float wobble = mix(-angle_noise, angle_noise, swirl_random(state));
		float angle = atan(heading.y, heading.x) + wobble;
		heading = vec2(cos(angle), sin(angle));
	}
	VELOCITY.xy = heading * mix(drift_speed.x, drift_speed.y, swirl_random(state));
	//store the opacity variation in the unused depth velocity of these 2d particles.
	VELOCITY.z = mix(0.75, 1.0, swirl_random(state));
	//store angle, normalized age, spin and scale for the next simulation step.
	float rotation = swirl_random(state) * TAU;
	float spin = mix(-0.96, 0.96, swirl_random(state));
	float scale = mix(sprite_scale.x, sprite_scale.y, swirl_random(state));
	CUSTOM = vec4(rotation, 0.0, spin, scale);
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	ACTIVE = CUSTOM.y < 1.0;
	CUSTOM.x += CUSTOM.z * DELTA;
	vec2 axis = vec2(cos(CUSTOM.x), sin(CUSTOM.x)) * CUSTOM.w;
	TRANSFORM[0].xy = axis;
	TRANSFORM[1].xy = vec2(-axis.y, axis.x);
	TRANSFORM[3].xy += VELOCITY.xy * DELTA * flow_strength;
	COLOR = swirl_color;
	COLOR.a *= VELOCITY.z * max(0.0, 1.0 - CUSTOM.y);
}
