extends Node

const GROUP_UNITS: StringName = &"debug_units"
const GROUP_SHADOW_COMPONENTS: StringName = &"debug_shadow_components"
const GROUP_HP_BARS: StringName = &"debug_hp_bars"
const GROUP_STATUS_ICONS: StringName = &"debug_status_icons"
const GROUP_FLOATING_TEXTS: StringName = &"debug_floating_texts"

var hide_unit_graphics: bool = false
var disable_shadows: bool = true
var disable_hp_bars: bool = true
var disable_status_icons: bool = true
var disable_floating_text: bool = true
func reset_visual_debug_flags() -> void:
	hide_unit_graphics = false
	disable_shadows = false
	disable_hp_bars = false
	disable_status_icons = false
	disable_floating_text = false

func apply_visual_benchmark_preset(preset: String) -> void:
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
		&"no_status_icons":
			disable_status_icons = true
		&"no_floating_text":
			disable_floating_text = true
		&"default":
			pass
		_:
			push_warning("Unknown visual benchmark preset: %s" % preset)

func print_visual_benchmark_config() -> void:
	print("=== Visual Benchmark Flags ===")
	print("hide_unit_graphics=", hide_unit_graphics)
	print("disable_shadows=", disable_shadows)
	print("disable_hp_bars=", disable_hp_bars)
	print("disable_status_icons=", disable_status_icons)
	print("disable_floating_text=", disable_floating_text)

func print_visual_report() -> void:
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
	print("status_icons=", status_icon_count)
	print("visible_status_icons=", visible_status_icons)
	print("floating_text_nodes=", floating_text_count)
	print("visible_floating_texts=", visible_floating_texts)
	print("estimated_visible_canvas_items=", visible_unit_graphics + visible_shadow_sprites + visible_hp_bars + visible_status_icons + visible_floating_texts)
	print_visual_benchmark_config()
