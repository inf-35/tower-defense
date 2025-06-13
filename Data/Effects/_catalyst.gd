extends EffectPrototype
class_name CatalystEffect

@export var params: Dictionary = {
	"hooks": [], #array of vector2i adjacencies/hooks, where neighbouring towers can slot into
}

var state: Dictionary = {
	"catalyst_effects": {}, #Tower -> Array[EffectInstance], stores effects caused by this catalyst
	"current_recipe": null, #current recipe the catalyst is upholding
	#this allows us to delete effects that are no longer relevant
}

func _handle_event(instance: EffectInstance, event : GameEvent):
	if event.event_type != GameEvent.EventType.ADJACENCY_UPDATED:
		return
	
	assert(instance.params.has("hooks") \
		and instance.state.has("catalyst_effects") \
		and instance.state.has("current_recipe")) #check for parameter prerequisites
	assert(instance.host is Tower) #catalyst must be a tower

	var adjacency_data: AdjacencyReportData = event.data as AdjacencyReportData
	
	if adjacency_data.pivot != instance.host: #we seem to have received the wrong report
		push_error("received wrong adjacency report. pivot:  ", adjacency_data.pivot, " received by: ", instance.host)
		return

	var hooks: Array[Vector2i] = instance.params.hooks as Array[Vector2i]
	var catalyst_effects: Dictionary[Tower, Array] = instance.state.catalyst_effects as Dictionary[Tower, Array]
	var adjacent_towers: Array[Tower] = adjacency_data.adjacent_towers.values()
	
	var element_list: Dictionary[Towers.Element, int] = {}
	for tower: Tower in adjacent_towers:
		var element: Towers.Element = Towers.get_tower_element(tower.type)
		if not element_list.has(element):
			element_list[element] = 1
		else:
			element_list[element] += 1
			
	var result = CatalystRecipes.get_most_relevant_recipe(element_list)
	if not result: #we didnt get any valid recipe
		instance.state.current_recipe = null
		return
	
	var recipe: CatalystRecipes.CatalystRecipe = result as CatalystRecipes.CatalystRecipe
	if instance.state.current_recipe == recipe:
		return #no change in recipe
	else:
		instance.state.current_recipe = recipe
	#clear existing effects
	for affected_tower: Tower in catalyst_effects:
		for effect_instance: EffectInstance in catalyst_effects[affected_tower]:
			affected_tower.remove_effect(effect_instance.effect_prototype)
	#add new effects
	for adjacent_tower: Tower in adjacent_towers:
		var adjacent_tower_element: Towers.Element = Towers.get_tower_element(adjacent_tower.type)
		if not recipe.effects.has(adjacent_tower_element): #adjacent tower's element does not fall under any effect
			continue
		
		adjacent_tower.apply_effect(recipe.effects[adjacent_tower_element])
