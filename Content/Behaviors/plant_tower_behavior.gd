extends DefaultTowerBehavior
class_name PlantTowerBehavior

const NETWORK_INFLUENCE_KEY: StringName = &"plant_forest_network"

func draw_visuals(canvas: RangeIndicator) -> void: ##draws the normal attack range while shared introspection owns the plant-forest network cells
	super.draw_visuals(canvas)

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes the plant and forest towers contributing to its contiguous network
	if not is_instance_valid(unit) or not unit is Tower:
		return []
	var tower: Tower = unit as Tower
	var sources: Array[Tower] = []
	var seen_sources: Dictionary[int, bool] = {}
	for effect_prototype: EffectPrototype in tower.intrinsic_effects:
		if not effect_prototype is ConditionalRelicEffect:
			continue
		var conditional_effect: ConditionalRelicEffect = effect_prototype as ConditionalRelicEffect
		if conditional_effect.condition_kind != ConditionalRelicEffect.ConditionKind.CONTIGUOUS_TYPES:
			continue
		for source: Tower in conditional_effect.get_condition_source_towers(tower):
			if seen_sources.has(source.unit_id):
				continue
			seen_sources[source.unit_id] = true
			sources.append(source)

	var cells: Array[Vector2i] = []
	for source: Tower in sources:
		cells.append_array(source.get_occupied_cells())
	if cells.is_empty():
		return []
	return [TowerInfluence.for_cells(
		NETWORK_INFLUENCE_KEY,
		TowerInfluence.Kind.LINK,
		cells,
		null,
		[],
		false,
		TowerInfluence.Scope.WORLD,
		TowerInfluence.VisualRole.HIGHLIGHT
	)]
