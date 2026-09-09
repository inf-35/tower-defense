extends RefCounted
class_name TowerInfluence

enum Kind {
	EFFECT = 0,
	MODIFIER = 1,
	INPUT = 2,
	OUTPUT = 3,
	TRIGGER = 4,
	LINK = 5,
	ATTACK = 6,
	NEGATIVE = 7,
}

enum PresentationKind {
	INPUT,
	TARGET,
	MODIFIER,
	NEGATIVE,
	ATTACK,
}

enum Scope {
	TOWER,
	WORLD,
}

enum Geometry {
	CELLS,
	LINE,
}

enum VisualRole {
	AUTO,
	HIGHLIGHT,
	INPUT,
	POSITIVE,
	NEGATIVE,
	ATTACK,
}

var registration_id: int = -1
var key: StringName
var owner_ref: WeakRef
var source_ref: WeakRef
var kind: Kind = Kind.LINK
var scope: Scope = Scope.TOWER
var geometry: Geometry = Geometry.CELLS
var cells: Array[Vector2i] = []
var line_from: Vector2 = Vector2.ZERO
var line_to: Vector2 = Vector2.ZERO
var accent_cells: Array[Vector2i] = []
var visual_role: VisualRole = VisualRole.AUTO
var visual_strength: float = 1.0
var line_width: float = 2.0
var effect_prototype: EffectPrototype
var modifier_prototypes: Array[ModifierDataPrototype] = []
var requires_health: bool = false

static func for_cells(
	p_key: StringName,
	p_kind: Kind,
	p_cells: Array[Vector2i],
	p_effect_prototype: EffectPrototype = null,
	p_modifier_prototypes: Array[ModifierDataPrototype] = [],
	p_requires_health: bool = false,
	p_scope: Scope = Scope.TOWER,
	p_visual_role: VisualRole = VisualRole.AUTO,
	p_visual_strength: float = 1.0
) -> TowerInfluence: ##builds one cell-based descriptor shared by indexing and selection rendering
	var influence := TowerInfluence.new()
	influence.key = p_key
	influence.kind = p_kind
	influence.scope = p_scope
	influence.geometry = Geometry.CELLS
	influence.cells = p_cells.duplicate()
	influence.effect_prototype = p_effect_prototype
	influence.modifier_prototypes = p_modifier_prototypes.duplicate()
	influence.requires_health = p_requires_health
	influence.visual_role = p_visual_role
	influence.visual_strength = clampf(p_visual_strength, 0.0, 1.0)
	return influence

static func for_line(
	p_key: StringName,
	p_kind: Kind,
	p_cells: Array[Vector2i],
	p_line_from: Vector2,
	p_line_to: Vector2,
	p_accent_cells: Array[Vector2i] = [],
	p_effect_prototype: EffectPrototype = null,
	p_modifier_prototypes: Array[ModifierDataPrototype] = [],
	p_requires_health: bool = false,
	p_scope: Scope = Scope.TOWER,
	p_visual_role: VisualRole = VisualRole.AUTO,
	p_visual_strength: float = 1.0,
	p_line_width: float = 2.0
) -> TowerInfluence: ##builds one line descriptor whose traversed cells may also participate in tower-preview lookup
	var influence := for_cells(
		p_key,
		p_kind,
		p_cells,
		p_effect_prototype,
		p_modifier_prototypes,
		p_requires_health,
		p_scope,
		p_visual_role,
		p_visual_strength
	)
	influence.geometry = Geometry.LINE
	influence.line_from = p_line_from
	influence.line_to = p_line_to
	influence.accent_cells = p_accent_cells.duplicate()
	influence.line_width = maxf(p_line_width, 0.0)
	return influence

func get_owner() -> Object: ##rehydrates the behavior or effect instance that owns this indexed relationship
	return owner_ref.get_ref() if owner_ref != null else null

func get_source() -> Tower: ##rehydrates the live tower that projects this relationship onto the indexed cells
	return source_ref.get_ref() as Tower if source_ref != null else null

func is_valid() -> bool: ##rejects stale registrations without letting weak references retain dead towers or behaviors
	var source: Tower = get_source()
	return (
		is_instance_valid(get_owner())
		and is_instance_valid(source)
		and not source.is_queued_for_deletion()
		and source.current_state == Tower.State.ACTIVE
	)

func matches_tower(tower: Tower) -> bool: ##applies inexpensive target-shape filters after the cell index has produced a candidate relationship
	if not is_instance_valid(tower):
		return false
	if tower.hostile or tower.current_state != Tower.State.ACTIVE:
		return false
	if requires_health and not is_instance_valid(tower.health_component):
		return false
	return true

func get_presentation_kind() -> PresentationKind: ##collapses runtime relationship detail into the smaller set of distinctions that matters in placement ui
	match kind:
		Kind.EFFECT, Kind.MODIFIER:
			return PresentationKind.MODIFIER
		Kind.INPUT, Kind.TRIGGER:
			return PresentationKind.INPUT
		Kind.NEGATIVE:
			return PresentationKind.NEGATIVE
		Kind.ATTACK:
			return PresentationKind.ATTACK
		_:
			return PresentationKind.TARGET

func get_kind_label() -> String: ##provides the normalized player-facing relation label without exposing runtime effect/modifier distinctions
	match get_presentation_kind():
		PresentationKind.INPUT:
			return "input"
		PresentationKind.MODIFIER:
			return "modifier"
		PresentationKind.NEGATIVE:
			return "negative"
		PresentationKind.ATTACK:
			return "attack"
		_:
			return "target"
