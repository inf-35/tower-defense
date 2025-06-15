extends Node #CatalystRecipes, technically a singleton but we're using objects like structs here

class CatalystRecipe:
	var requisites: Dictionary[Towers.Element, int] = {} #stores prerequisite elements
	var effects: Dictionary[Towers.Element, EffectPrototype] = {}
	#stores which effects adjacent towers will receive by adjacent tower element
	#NOTE: it is a purposeful design decision to sort this by element. adjacent towers of the same
	#element should ALWAYS receive the same effects by a catalyst.
	
	func _init(_requisites: Dictionary[Towers.Element, int], _effects: Dictionary[Towers.Element, EffectPrototype]):
		requisites = _requisites
		effects = _effects
	
	func get_element_count() -> int:
		var counter: int = 0
		for element_stack: int in requisites.values():
			counter += element_stack
		return counter
		
	func check_sufficiency_with(element_list: Dictionary[Towers.Element, int]) -> bool:
		var sufficiency: bool = true
		for requisite_element: Towers.Element in requisites:
			if not element_list.has(requisite_element):
				sufficiency = false
				break
			
			if requisites[requisite_element] > element_list[requisite_element]:
				sufficiency = false
				break
		return sufficiency

var catalyst_recipes: Array[CatalystRecipe] = [
	CatalystRecipe.new(
		{Towers.Element.KINETIC: 2},
		{Towers.Element.KINETIC: preload("res://Data/Effects/debug_on_hit_dealt.tres")}
	)
]

static func get_element_count(element_list: Dictionary[Towers.Element, int]) -> int:
	var counter: int = 0 #count the number of components in a element list.
	for element_stack: int in element_list.values():
		counter += element_stack
	return counter

func get_most_relevant_recipe(element_list: Dictionary[Towers.Element, int]):
	var most_relevant_recipe: CatalystRecipe
	var record_length: int = 0
	var element_count: int = get_element_count(element_list)
	
	if element_count <= 1: #early return for lists with only 1 element or less
		return
	
	for recipe: CatalystRecipe in catalyst_recipes:
		var recipe_element_count: int = recipe.get_element_count()
		if element_count < recipe_element_count: #ignore recipes which take more elements than we have
			continue
			
		if recipe_element_count < record_length: #ignore recipes which are less relevant anyways
			continue

		var sufficient: bool = recipe.check_sufficiency_with(element_list)
		if sufficient and recipe_element_count > record_length: #get longest matching recipe
			most_relevant_recipe = recipe #should be no ties
			record_length = recipe_element_count
			
	return most_relevant_recipe #returns null if no suitable recipes
