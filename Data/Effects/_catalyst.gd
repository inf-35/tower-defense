extends EffectPrototype
class_name CatalystEffect

@export var params: Dictionary = {
	"hooks": [], #array of relative vector2i offsets, where neighbouring towers can slot into
}

var state: Dictionary = {
	"catalyst_effects": {}, #Tower -> Array[EffectInstance], stores effects caused by this catalyst
	"current_recipe": null, #current recipe the catalyst is upholding
}

func _handle_detach(instance: EffectInstance):
	clear_effects(instance)

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

	var hooks: Array[Vector2i]; hooks.assign(instance.params.hooks)
	var catalyst_effects: Dictionary = instance.state.catalyst_effects #Dictionary[Tower, Array[EffectPrototype]]
	var adjacencies: Dictionary[Vector2i, Tower] = adjacency_data.adjacent_towers
	var hooked_towers: Array[Tower] = [] #stores towers which are located on "hook" tiles.

	var element_list: Dictionary[Towers.Element, int] = {}
	#rotate the hooks appropriately
	var rotation: float = instance.host.facing * PI * 0.5
	var translated_hooks: Array[Vector2i]
	for hook: Vector2i in hooks:
		translated_hooks.append(Vector2i(Vector2(hook).rotated(rotation)))

	#get hooked towers
	for adjacency: Vector2i in adjacencies:
		if not translated_hooks.has(adjacency): #filter out adjacencies that are not hooks
			continue
		
		var tower: Tower = adjacencies[adjacency]
		hooked_towers.append(tower) #add tower to the list of towers concerned (see line 63)
		
		var element: Towers.Element = Towers.get_tower_element(tower.type)
		
		if not element_list.has(element): #create element lit, see catalyst_recipes
			element_list[element] = 1
		else:
			element_list[element] += 1

	#compare with catalyst recipes
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
	clear_effects(instance) 
	#add new effects
	for adjacent_tower: Tower in hooked_towers:
		var adjacent_tower_element: Towers.Element = Towers.get_tower_element(adjacent_tower.type)
		if not recipe.effects.has(adjacent_tower_element): #adjacent tower's element does not fall under any effect
			continue
		
		var effect_to_apply: EffectPrototype = recipe.effects[adjacent_tower_element]
		adjacent_tower.apply_effect(effect_to_apply)
		
		if not catalyst_effects.has(adjacent_tower): #record this new effect down under the affected tower
			catalyst_effects[adjacent_tower] = [effect_to_apply]
		else:
			catalyst_effects[adjacent_tower].append(effect_to_apply)

func clear_effects(instance: EffectInstance):
	assert(instance.state.has("catalyst_effects")) #check for parameter prerequisites
	
	var catalyst_effects: Dictionary = instance.state.catalyst_effects
	for affected_tower: Tower in catalyst_effects:
		for effect_prototype: EffectPrototype in catalyst_effects[affected_tower]:
			affected_tower.remove_effect(effect_prototype)
