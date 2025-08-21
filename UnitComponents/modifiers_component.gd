extends UnitComponent
class_name ModifiersComponent

signal stat_changed(attribute: Attributes.id)
#base stats
var base_stats: Dictionary[Attributes.id, float] = {}
# internal storage of modifiers
var _permanent_modifiers: Array[Modifier] = [] #meant for permanent effects (ie local stat changes)
var _modifiers: Array[Modifier] = [] #meant for transient effects (all status effects's effects automatically fall here)
var _status_effects: Dictionary[Attributes.Status, StatusEffect] = {}
# cache of computed effective stats
var _effective_cache: Dictionary[Attributes.id, float] = {}

func _ready():
	stat_changed.connect(func(stat): #couple stat changes with ui changes
		UI.update_unit_state.emit(unit)
	)

# add a permanent buff/debuff (for level-ups, skill choices, etc.)
func add_permanent_modifier(mod: Modifier) -> void:
	_permanent_modifiers.append(mod)
	_effective_cache.erase(mod.attribute)
	stat_changed.emit(mod.attribute)

# remove a permanent buff/debuff (for respecs, etc.)
func remove_permanent_modifier(mod: Modifier) -> void:
	_effective_cache.erase(mod.attribute)
	stat_changed.emit(mod.attribute)
	_permanent_modifiers.erase(mod)

# add a buff/debuff
func add_modifier(mod: Modifier) -> void:
	_modifiers.append(mod)
	_effective_cache.erase(mod.attribute)
	stat_changed.emit(mod.attribute)
	
	if mod.source_id == null:
		push_warning("modifier ", self, " has no source id!")

	if mod.cooldown >= 0.0: #TODO: make this editable in change modifier.
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
	stat_changed.emit(mod.attribute) #this causes the UI to pull_stat; so you must finish everything (cache invalidation) before this
	
func replace_modifier(mod: Modifier, replacement: Modifier) -> void: #allows us to not repeat stat_changed calls
	if mod:
		_modifiers.erase(mod)
	_effective_cache.erase(mod.attribute)
	add_modifier(replacement)

#add a status effect
func add_status(type: Attributes.Status, stack: float, cooldown: float = -1.0) -> void:
	if _status_effects.has(type):
		var existing_status: StatusEffect = _status_effects[type]
		if existing_status.can_stack():
			existing_status.stack += stack #consolidate statuses together
			update_status(existing_status)
			check_reactions_for_status(type)
			
			if cooldown >= 0.0:
				get_tree().create_timer(cooldown).timeout.connect(func():
					existing_status.stack -= stack
					update_status(existing_status)
				)
		return

	var status := StatusEffect.new(type, stack)
	status.cooldown = cooldown

	_status_effects[type] = status
	update_status(status)
	check_reactions_for_status(type)

	if status.cooldown >= 0.0:
		get_tree().create_timer(status.cooldown).timeout.connect(func():
			status.stack -= stack #so we can subtract it after cooldown ends
			update_status(status)
		)
#update a status effect
func update_status(status: StatusEffect) -> void:
	# If the status has no stacks left, we're done. Remove it from tracking.
	if status.stack <= 0.0:
		remove_modifier(status._modifier)
		_status_effects.erase(status.type)
		#status._modifier = null # Clear the reference
		return

	# Create a new modifier that reflects the current state of the status effect.
	var old_modifier = status._modifier
	var new_modifier = create_underlying_modifier(status)
	status._modifier = new_modifier # Link the new modifier to the status effect
	replace_modifier(old_modifier, new_modifier) # Add the new modifier to the primary processing list
# checks all reactions that involve the newly updated status type to see if any have been triggered.
func check_reactions_for_status(updated_status_type: Attributes.Status) -> void:
	for reaction: Attributes.ReactionData in Attributes.reactions:
		# there's no way this update could have triggered it. Skip the check entirely.
		if not reaction.requisites.has(updated_status_type):
			continue

		var all_requisites_met: bool = true
		var reaction_stack: int = 10
		for required_status: Attributes.Status in reaction.requisites:
			var required_stacks: float = reaction.requisites[required_status]
			
			# Check if the unit has the status and if the stacks are sufficient.
			if not _status_effects.has(required_status) or _status_effects[required_status].stack < required_stacks:
				all_requisites_met = false
				break # A requisite is not met, no need to check others for this reaction.
			else:
				var possible_reaction_stack: int = floor(_status_effects[required_status].stack / required_stacks)
				if possible_reaction_stack < reaction_stack:
					reaction_stack = possible_reaction_stack
		
		# If, after checking all requisites, the flag is still true, the reaction triggers.
		if all_requisites_met:
			reaction.effect.call(unit)
			#consume effect
			for status_to_consume in reaction.requisites:
				_status_effects[status_to_consume].stack -= reaction.requisites[status_to_consume] * reaction_stack
				update_status(_status_effects[status_to_consume])

func create_underlying_modifier(status: StatusEffect) -> Modifier:
	# Look up the definition of this status type from our central Attributes store.
	var status_data = Attributes.status_effects[status.type]

	# Calculate the total effect based on the number of stacks.
	var total_additive = status_data.additive_per_stack * status.stack
	var total_multiplicative = pow(status_data.multiplicative_per_stack, status.stack)

	# Create a new Modifier instance. Note that we don't handle cooldowns here,
	# as the status effect's cooldown is managed by the add_status function's timer logic.
	# The source_id should be carried over if needed, assuming StatusEffect has one.
	var new_mod = Modifier.new(
		status_data.attribute,
		total_multiplicative,
		total_additive,
		null, # Status effects generally don't use override.
		status.source_id #doesnt actually work rn
	)
	new_mod.cooldown = -1.0 #status-modifiers are ALWAYS permanent
	#they are manually removed when their parent status runs out
	
	return new_mod

func register_stat(attr: Attributes.id, value: float) -> void: #registers a stat
	if value == null:
		return
	base_stats[attr] = value #overwrites if neccessary
	_effective_cache.erase(attr)  # ensure clean first read
	stat_changed.emit(attr)
		
func register_data(data: Data) -> void: #registers any arbitrary data resource; polymorphic
	if not data:
		push_warning("no data found in ", self)
		return

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

	var upgraded_value := base_stats[attr]
	var perm_sum_add := 0.0
	var perm_product_mult := 1.0
	var perm_override = null
	
	for modifier: Modifier in _permanent_modifiers:
		if modifier.attribute != attr:
			continue
		
		perm_sum_add += modifier.additive
		perm_product_mult *= modifier.multiplicative
		if modifier.override != null:
			perm_override = modifier.override
	
	upgraded_value = (upgraded_value + perm_sum_add) * perm_product_mult if perm_override == null else perm_override

	# --- STAGE 2: Apply transient modifiers to the upgraded stat ---
	var sum_add := 0.0
	var product_mult := 1.0
	var override = null
	
	for modifier: Modifier in _modifiers:
		if modifier.attribute != attr:
			continue
	
		sum_add += modifier.additive
		product_mult *= modifier.multiplicative
		if modifier.override != null:
			override = modifier.override
	
	var result = (upgraded_value + sum_add) * product_mult if override == null else override
	_effective_cache[attr] = result #cache result
	return result
	#TODO: decide whether we want per-unit filtering
	##compute stat
	#var base_value := base_stats[attr]
	#var sum_add := 0.0 #consolidated addition figure
	#var product_mult := 1.0 #consolidated multiplication figure
	#var override = null #force-set figure, null if no such modifier exists
	#
	##var best_modifier_by_source_id: Dictionary[int, Modifier] = {} #best_modifier_by_source_id[source_id] -> Modifier
	###this prevents endless stacking by a single unit
	##for modifier: Modifier in _modifiers:
		##if modifier.attribute != attr:
			##continue
		##
		##var source_id: int = modifier.source_id
		##if not best_modifier_by_source_id.has(source_id):
			##best_modifier_by_source_id[source_id] = modifier
			##continue
		##
		##var modifier_to_beat: Modifier = best_modifier_by_source_id[source_id]
		##if abs(modifier.additive) > abs(modifier_to_beat.additive) or abs(modifier.multiplicative - 1) > abs(modifier_to_beat.multiplicative - 1):
			##best_modifier_by_source_id[source_id] = modifier
