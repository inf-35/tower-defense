extends Node

@onready var tower_grid: = References.island.tower_grid

const L_PATTERN: Array[Vector2i] = [
	Vector2i(0,0), Vector2i(0,1), Vector2i(1,0)
]

const GRID_2_PATTERN: Array[Vector2i] = [
	Vector2i(0,0), Vector2i(0,1), Vector2i(1,0), Vector2i(1,1)
]

const WALL_3_PATTERN: Array[Vector2i] = [
	Vector2i(-1,0), Vector2i(0,0), Vector2i(1,0),
]

const PATTERN_RULES := {
	# e.g. an L-shape of Fire towers unlocks “Burn Chain”
	burn_chain = { type = Towers.Type.DPS_TOWER,
	  offsets = L_PATTERN,
	  },
	# e.g. three Ice towers in a line unlock “Glacial Wall”
	glacial_wall = { type = Towers.Type.SLOW_TOWER,
	  offsets = WALL_3_PATTERN,
	 },
	# …add as many as you like…
}

var _pattern_offsets := {}

func _ready():
	References.island.tower_changed.connect(_on_tower_changed)
	_precompute_patterns()

func _on_tower_changed(change_position: Vector2i):
	var changed_type: Towers.Type = References.island.tower_grid[change_position]
	
	for rule_key: String in PATTERN_RULES: 
		var rule: Dictionary = PATTERN_RULES[rule_key]
		if rule.type != changed_type: #ignore all patterns with wrong tower type
			continue
		
		var pattern_detected: bool = false
		# for each offset in the pattern, compute the candidate pivot
		for off: Vector2i in _pattern_offsets[rule_key]:
			var pivot = change_position - off
			# test the pattern at that pivot
			if matches_pattern_at(pivot, rule.offsets, changed_type, true):
				var tower_type: Towers.Type = tower_grid[pivot]
				pattern_detected = true

		#if pattern_detected:

		#tower.unlock_upgrade(rule.upgrade)
				# if you only want one trigger per placement, you can `break` here

# Call this to see if `pattern` of `type_id` exists with its origin at `cell`
func matches_pattern_at(cell: Vector2i, pattern: Array[Vector2i], type_id: Towers.Type, include_reflections := true) -> bool:
	var variants = _generate_pattern_variants(pattern, include_reflections)
	for variant in variants:
		var ok = true
		for off in variant:
			var pos = cell + off
			if not tower_grid.has(pos) or tower_grid[pos] != type_id:
				ok = false
				break
		if ok:
			return true
	return false

# Generate all rotations (and optional reflections) of the pattern
func _generate_pattern_variants(pattern: Array[Vector2i], include_reflections: bool) -> Array[Array]:
	var variants: Array[Array] = []
	var current = pattern.duplicate()
	# 4 rotations
	for i in 4:
		variants.append(current.duplicate())
		current = _rotate_90(current)
	if include_reflections:
		# reflect original and rotate that too
		current = _reflect(pattern)
		for i in 4:
			variants.append(current.duplicate())
			current = _rotate_90(current)
	return variants

func _precompute_patterns() -> void:
	_pattern_offsets.clear()
	for rule_key: String in PATTERN_RULES:
		var rule: Dictionary = PATTERN_RULES[rule_key]
		var variants := _generate_pattern_variants(rule.offsets, true)
		_pattern_offsets[rule_key] = []
		for variant: Array[Vector2i] in variants:
			for offset: Vector2i in variant:
				if not _pattern_offsets[rule_key].has(offset):
					_pattern_offsets[rule_key].append(offset)

# Rotate every offset by +90° around origin
func _rotate_90(pat: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for off in pat:
		# (x,y) -> (-y, x)
		out.append(Vector2i(-off.y, off.x))
	return out

# Reflect horizontally (mirror x)
func _reflect(pat: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for off in pat:
		# (x,y) -> (-x, y)
		out.append(Vector2i(-off.x, off.y))
	return out
