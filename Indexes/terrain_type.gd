class_name Terrain
#repository of data, purely static

enum Base { #base terrain type
	EARTH,
	SHORE,
	SEA,
}

static func get_color(terrain_base: Base) -> Color:
	match terrain_base:
		Base.EARTH: return Color.DARK_OLIVE_GREEN
		Base.SHORE: return Color.DARK_TURQUOISE
		Base.SEA: return Color.DARK_BLUE
		_: return Color.BLACK

static func is_navigable(terrain_base: Base) -> bool: #can this terrain be navigated upon?
	match terrain_base:
		Base.EARTH: return true
		Base.SHORE: return true
		Base.SEA: return false
		_: return false

static func is_constructable(terrain_base: Base) -> int: #can this terrain be constructed upon?
	match terrain_base:
		Base.EARTH: return 2
		Base.SHORE: return 1
		Base.SEA: return 0
		_: return 0
