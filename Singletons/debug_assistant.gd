extends Node

const GROUP_UNITS: StringName = &"debug_units"
const GROUP_SHADOW_COMPONENTS: StringName = &"debug_shadow_components"
const GROUP_HP_BARS: StringName = &"debug_hp_bars"
const GROUP_STATUS_ICONS: StringName = &"debug_status_icons"
const GROUP_FLOATING_TEXTS: StringName = &"debug_floating_texts"
const GROUP_HITBOXES: StringName = &"debug_hitboxes"
const PERF_SAMPLER_PATH: String = "res://tools/perf_sampler/perf_sampler.gd"
const PERF_SAMPLER_NODE_NAME: String = "PerfSampler"
const PERF_SAMPLER_INTERVAL: float = 0.05
const PERF_COUNTER_NAMES: Array[StringName] = [
	&"attacks_started",
	&"sibling_attacks_started",
	&"hits_resolved",
	&"hits_received",
	&"hits_dealt_events",
	&"global_events_published",
	&"global_event_subscriber_callbacks",
	&"local_event_subscriber_callbacks",
	&"local_effect_callbacks",
	&"global_effect_callbacks",
	&"line_aoe_queries",
	&"line_aoe_query_results",
	&"cone_aoe_radius_queries",
	&"radius_queries",
	&"radius_query_results",
	&"ray_queries",
	&"ray_query_hits",
	&"simulated_projectile_ticks",
	&"simulated_projectile_collision_checks",
	&"simulated_projectile_collisions",
	&"vfx_requests",
	&"vfx_suppressed",
	&"vfx_instances_created",
	&"vfx_scene_instances_created",
	&"aoe_field_requests",
	&"aoe_field_instances_created",
	&"particle_requests",
	&"particle_pool_expands",
	&"particle_requests_suppressed",
	&"floating_text_value_requests",
	&"floating_text_damage_requests",
	&"floating_text_text_requests",
	&"floating_text_icon_requests",
	&"floating_text_spawned",
	&"damage_text_immediate_spawns",
	&"damage_text_coalesced_requests",
	&"damage_text_flushes",
	&"damage_text_merges",
	&"clock_timers_created",
	&"clock_timers_expired",
	&"clock_timers_removed_inactive",
]
const BENCHMARK_PRESETS: Array[StringName] = [
	&"default",
	&"no_world_ui",
	&"no_status_icons",
	&"no_floating_text",
	&"no_shadows",
	&"no_vfx",
	&"no_projectile_visuals",
	&"no_projectile_trails",
	&"no_combat_lighting",
	&"no_render_extras",
	&"hide_world_visuals",
]

var hide_unit_graphics: bool = false
var disable_shadows: bool = false
var disable_hp_bars: bool = false
var disable_status_icons: bool = false
var disable_floating_text: bool = false
var disable_vfx_visuals: bool = false
var disable_projectile_visuals: bool = false
var disable_projectile_trails: bool = false
var disable_combat_lighting: bool = false
var allied_graphics_tint: Color = Color(1.05, 1.05, 1.05, 1.0)
var enemy_graphics_tint: Color = Color(0.92, 0.846, 0.846, 1.0)
var current_benchmark_preset: StringName = &"default"
var benchmark_preset_changed_msec: int = 0
var perf_instrumentation_active: bool = false
var _benchmark_preset_index: int = 0
var _perf_counters: Dictionary[StringName, int] = {}

func _ready() -> void: ##keeps benchmark hotkeys available without requiring mcp runtime access
	benchmark_preset_changed_msec = Time.get_ticks_msec()
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void: ##handles chorded local debug hotkeys for sampling and visual benchmark presets
	var key_event: InputEventKey = event as InputEventKey
	if not is_instance_valid(key_event):
		return
	if not key_event.pressed or key_event.echo:
		return
	if not key_event.ctrl_pressed or not key_event.shift_pressed:
		return

	match key_event.keycode:
		KEY_F7:
			_toggle_perf_sampler()
			get_viewport().set_input_as_handled()
		KEY_F8:
			_apply_next_benchmark_preset()
			get_viewport().set_input_as_handled()
		KEY_F9:
			_apply_named_benchmark_preset(&"default")
			get_viewport().set_input_as_handled()
		KEY_F10:
			print_visual_report()
			get_viewport().set_input_as_handled()

func reset_visual_debug_flags() -> void: ##returns all benchmark-only presentation flags to their normal runtime state
	hide_unit_graphics = false
	disable_shadows = false
	disable_hp_bars = false
	disable_status_icons = false
	disable_floating_text = false
	disable_vfx_visuals = false
	disable_projectile_visuals = false
	disable_projectile_trails = false
	disable_combat_lighting = false

func apply_visual_benchmark_preset(preset: String) -> void: ##sets one named diagnostic preset and applies it to already-live presentation nodes
	var preset_name: StringName = StringName(preset)
	var preset_index: int = BENCHMARK_PRESETS.find(preset_name)
	if preset_index >= 0:
		_benchmark_preset_index = preset_index
		current_benchmark_preset = preset_name
	else:
		current_benchmark_preset = &"default"
		benchmark_preset_changed_msec = Time.get_ticks_msec()

	reset_visual_debug_flags()
	match preset:
		&"hide_world_visuals":
			hide_unit_graphics = true
			disable_shadows = true
			disable_hp_bars = true
			disable_status_icons = true
			disable_floating_text = true
		&"no_shadows":
			disable_shadows = true
		&"no_world_ui":
			disable_hp_bars = true
			disable_status_icons = true
			disable_floating_text = true
		&"no_render_extras":
			disable_vfx_visuals = true
			disable_projectile_visuals = true
			disable_projectile_trails = true
			disable_combat_lighting = true
		&"no_vfx":
			disable_vfx_visuals = true
		&"no_projectile_visuals":
			disable_projectile_visuals = true
			disable_projectile_trails = true
		&"no_projectile_trails":
			disable_projectile_trails = true
		&"no_combat_lighting":
			disable_combat_lighting = true
		&"no_status_icons":
			disable_status_icons = true
		&"no_floating_text":
			disable_floating_text = true
		&"default":
			pass
		_:
			push_warning("Unknown visual benchmark preset: %s" % preset)
			current_benchmark_preset = &"default"
	benchmark_preset_changed_msec = Time.get_ticks_msec()
	apply_runtime_debug_flags()

func get_benchmark_preset_elapsed_seconds() -> float: ##returns how long the current benchmark preset has been active for csv segmentation
	return float(Time.get_ticks_msec() - benchmark_preset_changed_msec) / 1000.0

func get_benchmark_flags_label() -> String: ##returns a compact text label for active diagnostic flags in sampler rows
	var active_flags: PackedStringArray = PackedStringArray()
	if hide_unit_graphics:
		active_flags.append("hide_unit_graphics")
	if disable_shadows:
		active_flags.append("disable_shadows")
	if disable_hp_bars:
		active_flags.append("disable_hp_bars")
	if disable_status_icons:
		active_flags.append("disable_status_icons")
	if disable_floating_text:
		active_flags.append("disable_floating_text")
	if disable_vfx_visuals:
		active_flags.append("disable_vfx_visuals")
	if disable_projectile_visuals:
		active_flags.append("disable_projectile_visuals")
	if disable_projectile_trails:
		active_flags.append("disable_projectile_trails")
	if disable_combat_lighting:
		active_flags.append("disable_combat_lighting")
	if active_flags.is_empty():
		return "none"
	return ";".join(active_flags)

func start_perf_instrumentation() -> void: ##enables cheap event counters that are drained by the csv perf sampler
	reset_perf_counters()
	perf_instrumentation_active = true

func stop_perf_instrumentation() -> void: ##disables event counters so normal play does not pay diagnostic bookkeeping cost
	perf_instrumentation_active = false
	reset_perf_counters()

func reset_perf_counters() -> void: ##zeros every named event counter without changing visual benchmark flags
	_perf_counters.clear()
	for counter_name: StringName in PERF_COUNTER_NAMES:
		_perf_counters[counter_name] = 0

func record_perf_event(counter_name: StringName, amount: int = 1) -> void: ##increments one diagnostic counter while instrumentation is enabled
	if not perf_instrumentation_active:
		return
	if amount == 0:
		return

	_perf_counters[counter_name] = _perf_counters.get(counter_name, 0) + amount

func consume_perf_counters() -> Dictionary[StringName, int]: ##returns interval event totals and resets them for the next sampler row
	var output: Dictionary[StringName, int] = {}
	for counter_name: StringName in PERF_COUNTER_NAMES:
		output[counter_name] = _perf_counters.get(counter_name, 0)
		_perf_counters[counter_name] = 0
	return output

func apply_runtime_debug_flags() -> void: ##pushes current diagnostic flags onto already-instantiated visual nodes without touching combat state
	_apply_unit_graphics_flags()
	_apply_shadow_flags()
	_apply_hp_bar_flags()
	_apply_floating_text_flags()
	_apply_vfx_flags()
	_apply_lighting_flags()

func print_visual_benchmark_config() -> void: ##prints the active diagnostic flags so profiler captures can be matched to their preset
	print("=== Visual Benchmark Flags ===")
	print("current_benchmark_preset=", current_benchmark_preset)
	print("benchmark_preset_elapsed_sec=", get_benchmark_preset_elapsed_seconds())
	print("benchmark_flags=", get_benchmark_flags_label())
	print("hide_unit_graphics=", hide_unit_graphics)
	print("disable_shadows=", disable_shadows)
	print("disable_hp_bars=", disable_hp_bars)
	print("disable_status_icons=", disable_status_icons)
	print("disable_floating_text=", disable_floating_text)
	print("disable_vfx_visuals=", disable_vfx_visuals)
	print("disable_projectile_visuals=", disable_projectile_visuals)
	print("disable_projectile_trails=", disable_projectile_trails)
	print("disable_combat_lighting=", disable_combat_lighting)

func print_visual_report() -> void: ##prints current presentation node counts for quick interactive benchmark sanity checks
	var unit_count: int = 0
	var visible_unit_graphics: int = 0
	for unit: Unit in get_tree().get_nodes_in_group(GROUP_UNITS):
		unit_count += 1
		if is_instance_valid(unit.graphics) and unit.graphics.visible:
			visible_unit_graphics += 1

	var hp_bar_count: int = 0
	var visible_hp_bars: int = 0
	for hp_bar: UnitHPBar in get_tree().get_nodes_in_group(GROUP_HP_BARS):
		hp_bar_count += 1
		if hp_bar.visible:
			visible_hp_bars += 1

	var status_icon_count: int = 0
	var visible_status_icons: int = 0
	for status_icon: UnitStatusIcon in get_tree().get_nodes_in_group(GROUP_STATUS_ICONS):
		status_icon_count += 1
		if status_icon.visible:
			visible_status_icons += 1

	var floating_text_count: int = 0
	var visible_floating_texts: int = 0
	for floating_text: FloatingText in get_tree().get_nodes_in_group(GROUP_FLOATING_TEXTS):
		floating_text_count += 1
		if floating_text.visible:
			visible_floating_texts += 1

	var shadow_component_count: int = 0
	var shadow_sprite_count: int = 0
	var visible_shadow_sprites: int = 0
	for shadow_component: ShadowComponent in get_tree().get_nodes_in_group(GROUP_SHADOW_COMPONENTS):
		shadow_component_count += 1
		if is_instance_valid(shadow_component.shadow_sprite):
			shadow_sprite_count += 1
			if shadow_component.shadow_sprite.visible:
				visible_shadow_sprites += 1
		if is_instance_valid(shadow_component.height_sprite):
			shadow_sprite_count += 1
			if shadow_component.height_sprite.visible:
				visible_shadow_sprites += 1

	print("=== Visual Benchmark Report ===")
	print("units=", unit_count)
	print("visible_unit_graphics=", visible_unit_graphics)
	print("shadow_components=", shadow_component_count)
	print("shadow_sprites=", shadow_sprite_count)
	print("visible_shadow_sprites=", visible_shadow_sprites)
	print("hp_bars=", hp_bar_count)
	print("visible_hp_bars=", visible_hp_bars)
	if is_instance_valid(UI.world_unit_ui_manager):
		print("world_ui_registered_units=", UI.world_unit_ui_manager.get_registered_unit_count())
		print("world_ui_active_bars=", UI.world_unit_ui_manager.get_active_bar_count())
		print("world_ui_pooled_bars=", UI.world_unit_ui_manager.get_pooled_bar_count())
	print("status_icons=", status_icon_count)
	print("visible_status_icons=", visible_status_icons)
	print("floating_text_nodes=", floating_text_count)
	print("visible_floating_texts=", visible_floating_texts)
	print("estimated_visible_canvas_items=", visible_unit_graphics + visible_shadow_sprites + visible_hp_bars + visible_status_icons + visible_floating_texts)
	print_visual_benchmark_config()

func _apply_unit_graphics_flags() -> void:
	for unit: Unit in get_tree().get_nodes_in_group(GROUP_UNITS):
		if is_instance_valid(unit) and is_instance_valid(unit.graphics):
			unit.graphics.visible = not hide_unit_graphics

func _apply_shadow_flags() -> void:
	for shadow_component: ShadowComponent in get_tree().get_nodes_in_group(GROUP_SHADOW_COMPONENTS):
		if not is_instance_valid(shadow_component):
			continue

		shadow_component.set_process(shadow_component.is_dynamic and not disable_shadows)
		if is_instance_valid(shadow_component.shadow_sprite):
			shadow_component.shadow_sprite.visible = not disable_shadows
		if is_instance_valid(shadow_component.height_sprite):
			shadow_component.height_sprite.visible = not disable_shadows

func _apply_hp_bar_flags() -> void:
	for hp_bar: UnitHPBar in get_tree().get_nodes_in_group(GROUP_HP_BARS):
		if is_instance_valid(hp_bar) and hp_bar.has_method(&"apply_debug_visibility_flags"):
			hp_bar.call(&"apply_debug_visibility_flags")
	if is_instance_valid(UI.world_unit_ui_manager):
		UI.world_unit_ui_manager.apply_debug_visibility_flags()

	for status_icon: UnitStatusIcon in get_tree().get_nodes_in_group(GROUP_STATUS_ICONS):
		if not is_instance_valid(status_icon):
			continue
		if disable_hp_bars or disable_status_icons:
			status_icon.visible = false
			status_icon.set_process(false)

func _apply_floating_text_flags() -> void:
	if not disable_floating_text:
		return

	for floating_text: FloatingText in get_tree().get_nodes_in_group(GROUP_FLOATING_TEXTS):
		if not is_instance_valid(floating_text):
			continue
		floating_text.visible = false
		floating_text.set_process(false)

func _apply_vfx_flags() -> void:
	if is_instance_valid(VFXManager) and VFXManager.has_method(&"apply_debug_visual_flags"):
		VFXManager.call(&"apply_debug_visual_flags")

func _apply_lighting_flags() -> void:
	if not Run.has_active_run():
		return
	if not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return
	if not is_instance_valid(Run.references.island.combat_lighting_service):
		return

	var service: CombatLightingService = Run.references.island.combat_lighting_service
	if service.has_method(&"apply_debug_visual_flags"):
		service.call(&"apply_debug_visual_flags")

func _toggle_perf_sampler() -> void:
	var root: Window = get_tree().root
	var existing: Node = root.get_node_or_null(PERF_SAMPLER_NODE_NAME)
	if is_instance_valid(existing):
		var path: String = existing.call(&"get_output_path")
		existing.call(&"stop_sampling")
		existing.queue_free()
		print("DebugAssistant: stopped perf sampler at ", path)
		return

	var sampler_script: Script = load(PERF_SAMPLER_PATH) as Script
	if not is_instance_valid(sampler_script):
		push_warning("DebugAssistant: could not load %s" % PERF_SAMPLER_PATH)
		return

	var sampler: Node = sampler_script.new() as Node
	if not is_instance_valid(sampler):
		push_warning("DebugAssistant: could not create perf sampler.")
		return

	sampler.name = PERF_SAMPLER_NODE_NAME
	root.add_child(sampler)
	var output_path: String = sampler.call(&"start_sampling", "", PERF_SAMPLER_INTERVAL, true, false)
	print("DebugAssistant: started perf sampler at ", output_path)

func _apply_next_benchmark_preset() -> void:
	_benchmark_preset_index = wrapi(_benchmark_preset_index + 1, 0, BENCHMARK_PRESETS.size())
	_apply_named_benchmark_preset(BENCHMARK_PRESETS[_benchmark_preset_index])

func _apply_named_benchmark_preset(preset: StringName) -> void:
	print("DebugAssistant: applying benchmark preset ", String(preset))
	apply_visual_benchmark_preset(String(preset))
	print_visual_report()
