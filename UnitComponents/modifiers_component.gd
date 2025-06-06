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
	
	if not base_stats.has(attr):
		return null #unregistered stat!
	
	#compute stat
	var base_value := base_stats[attr]
	var sum_add := 0.0 #consolidated addition figure
	var product_mult := 1.0 #consolidated multiplication figure
	var override = null #force-set figure, null if no such modifier exists
	
	var status_best: Dictionary[Attributes.Status, Modifier] = {} #status -> modifier
	
	for mod: Modifier in _modifiers: #find best modifier in each status
		if mod.attribute != attr:
			continue

		var status: Attributes.Status = mod.status
		if (not status_best.has(status)) or (abs(mod.additive) > abs(status_best[status].additive)) or (abs(1 - mod.multiplicative) > abs(1 - status_best[status].multiplicative)):
			status_best[status] = mod
	
	for modifier: Modifier in status_best.values(): #iterate through "strongest" modifiers
		sum_add += modifier.additive
		product_mult *= modifier.multiplicative
		if modifier.override != null:
			override = modifier.override
	
	var result = (base_value + sum_add) * product_mult if override == null else override
	_effective_cache[attr] = result #cache result
	return result
