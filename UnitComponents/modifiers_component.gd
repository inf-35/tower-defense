extends UnitComponent
class_name ModifiersComponent

signal stat_changed(attribute: Attributes.id)

#base stats
var base_stats: Dictionary[Attributes.id, float] = {}
# internal storage of modifiers
var _modifiers: Array[Modifier] = []
# cache of computed effective stats
var _effective_cache: Dictionary[Attributes.id, float] = {}

# add a buff/debuff
func add_modifier(mod: Modifier) -> void:
	_modifiers.append(mod)
	_effective_cache.erase(mod.attribute)
	stat_changed.emit(mod.attribute)
	
	if mod.source_id == null:
		push_warning("modifier ", self, " has no source id!")

	if mod.cooldown >= 0.0:
		get_tree().create_timer(mod.cooldown).timeout.connect(func():
			remove_modifier(mod)
		)

#change modifier
func change_modifier(mod: Modifier) -> void:
	_effective_cache.erase(mod.attribute)
	stat_changed.emit(mod.attribute)

# remove a buff/debuff
func remove_modifier(mod: Modifier) -> void:
	_modifiers.erase(mod)
	_effective_cache.erase(mod.attribute)
	stat_changed.emit(mod.attribute)
	
func register_stat(attr: Attributes.id, value: float) -> void: #registers a stat
	if value == null:
		return
	base_stats[attr] = value #overwrites if neccessary
	_effective_cache.erase(attr)  # ensure clean first read
	stat_changed.emit(attr)
		
func register_data(data: Data) -> void: #registers any arbitrary data resource; polymorphic
	for attr: Attributes.id in Attributes.id.values():
		var value = data.resolve(attr) #try and get all attributes from data
		if value == null: #attribute does not exist
			continue
		
		register_stat(attr, value)
	
	data.value_changed.connect(func(attribute: Attributes.id): #re-register base stat if changed
		register_stat(attribute, data.resolve(attribute))
	)

func has_stat(attr: Attributes.id) -> bool:
	return base_stats.has(attr)

func pull_stat(attr: Attributes.id) -> Variant:
	if _effective_cache.has(attr):
		return _effective_cache[attr] #return cache
	
	if not has_stat(attr):
		return null #unregistered stat!
	
	#compute stat
	var base_value := base_stats[attr]
	var sum_add := 0.0 #consolidated addition figure
	var product_mult := 1.0 #consolidated multiplication figure
	var override = null #force-set figure, null if no such modifier exists
	
	#var best_modifier_by_source_id: Dictionary[int, Modifier] = {} #best_modifier_by_source_id[source_id] -> Modifier
	##this prevents endless stacking by a single unit
	#for modifier: Modifier in _modifiers:
		#if modifier.attribute != attr:
			#continue
		#
		#var source_id: int = modifier.source_id
		#if not best_modifier_by_source_id.has(source_id):
			#best_modifier_by_source_id[source_id] = modifier
			#continue
		#
		#var modifier_to_beat: Modifier = best_modifier_by_source_id[source_id]
		#if abs(modifier.additive) > abs(modifier_to_beat.additive) or abs(modifier.multiplicative - 1) > abs(modifier_to_beat.multiplicative - 1):
			#best_modifier_by_source_id[source_id] = modifier
	#TODO: decide whether we want per-unit filtering
	for modifier: Modifier in _modifiers: #run over strongest attribute per source
		if modifier.attribute != attr:
			continue
	
		sum_add += modifier.additive
		product_mult *= modifier.multiplicative
		if modifier.override != null:
			override = modifier.override
	
	var result = (base_value + sum_add) * product_mult if override == null else override
	_effective_cache[attr] = result #cache result
	return result
