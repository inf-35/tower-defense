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
	stat_changed.connect(func(_stat): #couple stat changes with ui changes
		UI.update_unit_state.emit(unit)
	)
	Player.relics_changed.connect(_on_global_modifiers_changed)
	set_process(false)
	
# called by the signal from player (indicating relic/global modifier change)
func _on_global_modifiers_changed() -> void:
	# clear the entire cache, as any stat could now be different
	_effective_cache.clear()
	
	# re-emit stat_changed for all stats this unit possesses to update ui
	for attribute: Attributes.id in base_stats:
		stat_changed.emit(attribute)

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
		Clock.await_game_time(mod.cooldown).connect(func():
			remove_modifier(mod)
		)

#change modifier notification NOTE: mainly used for external modifier modification, simply notifies that there is a change
func change_modifier(mod: Modifier) -> void:
	_effective_cache.erase(mod.attribute)
	stat_changed.emit(mod.attribute)

# remove a buff/debuff
func remove_modifier(mod: Modifier) -> void:
	_modifiers.erase(mod)
	_effective_cache.erase(mod.attribute)
	stat_changed.emit(mod.attribute) #this causes the UI to pull_stat; so you must finish everything (cache invalidation) before this
	
func replace_modifier(mod: Modifier, replacement: Modifier) -> void: #allows us to not repeat stat_changed calls
	_modifiers.erase(mod)
	_effective_cache.erase(replacement.attribute)
	add_modifier(replacement) #this calls stat_changed

# add a status effect with new precedence rules
func add_status(type: Attributes.Status, stack: float, cooldown: float, source_id: int = 0) -> void:
	#NOTE: 0 by default refers to the player core
	# if a status of this type already exists, refresh it
	if _status_effects.has(type):
		var existing_status: StatusEffect = _status_effects[type]
		# delegate the refresh logic to the status effect object itself
		existing_status.refresh(stack, cooldown)
		# apply the updated state
		update_status(existing_status)
		check_reactions_for_status(type)
		return

	# if it's a new status, create and configure it
	var status := StatusEffect.new(type, stack, cooldown, source_id)
	_status_effects[type] = status
	
	# create and manage a dedicated timer for this new status if it's not permanent
	if cooldown > 0.0:
		var new_timer := Clock.create_game_timer(cooldown)
		# link the timer and the status object
		status.timer = new_timer
		# connect the timer's timeout to the status object's handler
		status.timer.timeout.connect(func():
			status.on_timeout()
			update_status(status) # tell the component to process the change
		)
		#gametimers automatically start
	update_status(status)
	check_reactions_for_status(type)

# update a status effect
func update_status(status: StatusEffect) -> void:
	# if the status has no stacks left, remove it from tracking
	if status.stack <= 0.0:
		status.cleanup() # tell the status to clean up its timer
		remove_modifier(status._modifier)
		if _status_effects.has(status.type):
			_status_effects.erase(status.type)
		
		_recalculate_overlay_color()
		return

	# create a new modifier that reflects the current state of the status effect
	var old_modifier: Modifier = status._modifier
	var new_modifier: Modifier = create_underlying_modifier(status)
	status._modifier = new_modifier
	if old_modifier != null:
		replace_modifier(old_modifier, new_modifier)
	else:
		add_modifier(new_modifier)
		
		
	_recalculate_overlay_color()
	
#helper function to recalculate the visual overlay of units when under status effects
func _recalculate_overlay_color() -> void:
	if not is_instance_valid(unit) or not is_instance_valid(unit.graphics) or not is_instance_valid(unit.graphics.material):
		return
		
	var material: ShaderMaterial = unit.graphics.material as ShaderMaterial
	var best_overlay: Color = Color.TRANSPARENT
	
	# find the dominant status effect to display visually
	for status_type: Attributes.Status in _status_effects:
		var status: StatusEffect = _status_effects[status_type]
		var status_color: Color = Attributes.status_effects[status_type].overlay_color
		# prioritize the overlay with the highest alpha (intensity)
		if status_color.a > best_overlay.a:
			best_overlay = status_color
			
	# push the calculated color to the shader uniform
	material.set_shader_parameter(&"overlay_color", best_overlay)

# checks all reactions that involve the newly updated status type to see if any have been triggered.
func check_reactions_for_status(updated_status_type: Attributes.Status) -> void:
	for reaction: Attributes.ReactionData in Attributes.reactions:
		# there's no way this update could have triggered it. skip the check entirely.
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
		
		# if, after checking all requisites, the flag is still true, the reaction triggers.
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
		-1.0, #cooldown is permanent, as we handle expiration manually
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
	
	upgraded_value = upgraded_value * perm_product_mult + perm_sum_add if perm_override == null else perm_override

	# --- STAGE 2: apply transient modifiers to the upgraded stat ---
	var sum_add := 0.0
	var product_mult := 1.0
	var override = null
	
	for modifier: Modifier in _modifiers:
		if modifier.attribute != attr:
			continue
			
		#if attr == Attributes.id.REGEN_PERCENT:
			#print(modifier, " found!")
	
		sum_add += modifier.additive
		product_mult *= modifier.multiplicative
		if modifier.override != null:
			override = modifier.override
	
	var transient_value: float = upgraded_value * product_mult + sum_add if override == null else override
	
	# --- STAGE 3: apply global (relic) modifiers ---
	var final_value: float = transient_value # start with the result of stage 2
	var global_modifiers: Array[Modifier] = Player.get_modifiers_for_unit(self.unit)

	if not global_modifiers.is_empty():
		var global_sum_add: float = 0.0
		var global_product_mult: float = 1.0
		var global_override = null # global overrides are powerful, use with care

		for modifier: Modifier in global_modifiers:
			if modifier.attribute != attr:
				continue
			
			global_sum_add += modifier.additive
			global_product_mult *= modifier.multiplicative
			if modifier.override != null:
				global_override = modifier.override
		
		final_value = (final_value + global_sum_add) * global_product_mult if global_override == null else global_override

	return final_value

#data retrieval functions
func has_status(status: Attributes.Status, threshold: float = 0.0) -> bool:
	if not _status_effects.has(status):
		return false
	return _status_effects[status].stack > threshold
