extends UnitComponent
class_name ModifiersComponent

signal stat_changed(attribute: Attributes.id)
const MIN_EFFECTIVE_COOLDOWN: float = 0.001
const MIN_EFFECTIVE_ATTACK_RATE: float = 0.001
#base stats
var base_stats: Dictionary[Attributes.id, float] = {}
#internal storage of modifiers
var _permanent_modifiers: Array[Modifier] = [] #meant for permanent effects (ie local stat changes)
var _modifiers: Array[Modifier] = [] #meant for transient effects (all status effects's effects automatically fall here)
var _status_effects: Dictionary[Attributes.Status, StatusEffect] = {}
#cache of computed effective stats
var _effective_cache: Dictionary[Attributes.id, float] = {}

signal status_changed(type: Attributes.Status, stacks: float, duration: float)

#dynamic attribute system
static var _next_dynamic_id: int = 10000
static var _dynamic_id_registry: Dictionary[StringName, int] = {}
static func register_dynamic_attribute(key: StringName) -> void:
	if _dynamic_id_registry.has(key):
		return #already registered!
	_dynamic_id_registry[key] = _next_dynamic_id
	_next_dynamic_id += 1

static func get_dynamic_id(key: StringName) -> int: ##return 0 -> error/unregistered!
	if not _dynamic_id_registry.has(key):
		push_warning("ModifiersComponent: Unregistered dynamic attribute: ", key)
		return 0 #error
	return _dynamic_id_registry[key]

func _ready() -> void:
	stat_changed.connect(func(_stat): #couple stat changes with ui changes
		UI.update_unit_state.emit(unit)
	)
	Run.player.relics_changed.connect(_on_global_modifiers_changed)
	set_process(false)

#called by the signal from player (indicating relic/global modifier change)
func _on_global_modifiers_changed() -> void:
	#clear the entire cache, as any stat could now be different
	_effective_cache.clear()

	#re-emit stat_changed for all stats this unit possesses to update ui
	for attribute: Attributes.id in base_stats:
		stat_changed.emit(attribute)

func _invalidate_stat(attribute: Attributes.id) -> void: ##invalidates one stat and any derived stat that depends on it
	_effective_cache.erase(attribute)
	stat_changed.emit(attribute)
	if attribute != Attributes.id.ATTACK_RATE:
		return
	_effective_cache.erase(Attributes.id.COOLDOWN)
	stat_changed.emit(Attributes.id.COOLDOWN)

#add a permanent buff/debuff (for level-ups, skill choices, etc.)
func add_permanent_modifier(mod: Modifier) -> void:
	_permanent_modifiers.append(mod)
	_invalidate_stat(mod.attribute)

#remove a permanent buff/debuff (for respecs, etc.)
func remove_permanent_modifier(mod: Modifier) -> void:
	_permanent_modifiers.erase(mod)
	_invalidate_stat(mod.attribute)

#add a buff/debuff
func add_modifier(mod: Modifier) -> void:
	_modifiers.append(mod)
	_invalidate_stat(mod.attribute)

	if mod.source_id == null:
		push_warning("modifier ", self, " has no source id!")

	if mod.cooldown >= 0.0: #TODO: make this editable in change modifier.
		Clock.await_game_time(mod.cooldown).connect(func():
			remove_modifier(mod)
		)

#change modifier notification NOTE: mainly used for external modifier modification, simply notifies that there is a change
func change_modifier(mod: Modifier) -> void:
	_invalidate_stat(mod.attribute)

#remove a buff/debuff
func remove_modifier(mod: Modifier) -> void:
	_modifiers.erase(mod)
	_invalidate_stat(mod.attribute) #this causes the UI to pull_stat; so you must finish everything (cache invalidation) before this

func replace_modifier(mod: Modifier, replacement: Modifier) -> void: #allows us to not repeat stat_changed calls
	_modifiers.erase(mod)
	_effective_cache.erase(replacement.attribute)
	add_modifier(replacement) #this calls stat_changed

#add a status effect with new precedence rules
func add_status(type: Attributes.Status, stack: float, cooldown: float, source_id: int = 0) -> bool:
	#NOTE: 0 by default refers to the player core
	if _is_status_blocked_by_cleanse(type):
		return false

	#if a status of this type already exists, refresh it
	if _status_effects.has(type):
		var existing_status: StatusEffect = _status_effects[type]
		#delegate the refresh logic to the status effect object itself
		existing_status.refresh(stack, cooldown)
		#apply the updated state
		update_status(existing_status)
		check_reactions_for_status(type)
		return true

	#if it's a new status, create and configure it
	var status := StatusEffect.new(type, stack, cooldown, source_id)
	_status_effects[type] = status

	#create and manage a dedicated timer for this new status if it's not permanent
	if cooldown > 0.0:
		var new_timer := Clock.create_game_timer(cooldown)
		#link the timer and the status object
		status.timer = new_timer
		#connect the timer's timeout to the status object's handler
		status.timer.timeout.connect(func():
			status.on_timeout()
			update_status(status) #tell the component to process the change
		)
		#gametimers automatically start
	update_status(status)
	check_reactions_for_status(type)
	return true

func set_status_timers_paused(paused: bool) -> void: ##pauses or resumes every active status duration timer owned by this component
	for status_type: Attributes.Status in _status_effects:
		var status: StatusEffect = _status_effects[status_type]
		if is_instance_valid(status.timer):
			status.timer.paused = paused

func _is_status_blocked_by_cleanse(type: Attributes.Status) -> bool:
	if type == Attributes.Status.CLEANSE:
		return false
	return _status_effects.has(Attributes.Status.CLEANSE)

#update a status effect
func update_status(status: StatusEffect) -> void:
	#if the status has no stacks left, remove it from tracking
	if status.stack <= 0.0:
		status.cleanup() #tell the status to clean up its timer
		_replace_status_modifiers(status, [])
		if _status_effects.has(status.type):
			_status_effects.erase(status.type)

		status_changed.emit(status.type, status.stack, status.cooldown)
		_recalculate_overlay_color()
		return

	#create new modifiers that reflect the current state of the status effect
	_replace_status_modifiers(status, create_underlying_modifiers(status))

	var time_left: float = status.timer.duration - status.timer.time_elapsed if is_instance_valid(status.timer) else -1.0
	status_changed.emit(status.type, status.stack, time_left)

	_recalculate_overlay_color()

func _replace_status_modifiers(status: StatusEffect, replacements: Array[Modifier]) -> void: ##swaps one status's modifier rows and invalidates each affected attribute only after the final state is installed
	var affected_attributes: Dictionary[Attributes.id, bool] = {}
	for modifier: Modifier in status._modifiers:
		_modifiers.erase(modifier)
		affected_attributes[modifier.attribute] = true

	status._modifiers = replacements
	for modifier: Modifier in replacements:
		_modifiers.append(modifier)
		affected_attributes[modifier.attribute] = true

	for attribute: Attributes.id in affected_attributes:
		_invalidate_stat(attribute)

#helper function to recalculate the visual overlay of units when under status effects
func _recalculate_overlay_color() -> void:
	if not is_instance_valid(unit):
		return

	var best_overlay: Color = Color.TRANSPARENT
	var best_stack: float = -INF
	
	if has_status(Attributes.Status.STUN, 0.5):
		unit.set_tint_layer(
			TintService.LAYER_STATUS,
			Attributes.status_effects[Attributes.Status.STUN].overlay_color,
			1.0,
			false,
			TintService.BlendMode.OVERLAY
		)
		return

	#find the dominant status effect to display visually
	for status_type: Attributes.Status in _status_effects:
		var status_effect: StatusEffect = _status_effects[status_type]
		#prioritize the status with the highest stack count, then preserve the authored alpha/color of that status
		if status_effect.stack > best_stack:
			best_stack = status_effect.stack
			best_overlay = Attributes.status_effects[status_type].overlay_color

	if best_overlay.a <= 0.0:
		unit.clear_tint_layer(TintService.LAYER_STATUS)
		return

	unit.set_tint_layer(
		TintService.LAYER_STATUS,
		Color(best_overlay.r, best_overlay.g, best_overlay.b, 1.0),
		best_overlay.a,
		false,
		TintService.BlendMode.MODULATE
	)

#checks all reactions that involve the newly updated status type to see if any have been triggered.
func check_reactions_for_status(updated_status_type: Attributes.Status) -> void:
	for reaction: Attributes.ReactionData in Attributes.reactions:
		#there's no way this update could have triggered it. skip the check entirely.
		if not reaction.requisites.has(updated_status_type):
			continue

		var all_requisites_met: bool = true
		var reaction_stack: int = 10
		for required_status: Attributes.Status in reaction.requisites:
			var required_stacks: float = reaction.requisites[required_status]

			#check if the unit has the status and if the stacks are sufficient.
			if not _status_effects.has(required_status) or _status_effects[required_status].stack < required_stacks:
				all_requisites_met = false
				break #a requisite is not met, no need to check others for this reaction.
			else:
				var possible_reaction_stack: int = floor(_status_effects[required_status].stack / required_stacks)
				if possible_reaction_stack < reaction_stack:
					reaction_stack = possible_reaction_stack

		#if, after checking all requisites, the flag is still true, the reaction triggers.
		if all_requisites_met:
			reaction.effect.call(unit)
			#consume effect
			for status_to_consume in reaction.requisites:
				_status_effects[status_to_consume].stack -= reaction.requisites[status_to_consume] * reaction_stack
				update_status(_status_effects[status_to_consume])

func create_underlying_modifiers(status: StatusEffect) -> Array[Modifier]: ##creates one runtime modifier per explicit status attribute row
	#look up the definition of this status type from our central attributes store.
	var status_data: Attributes.StatusEffectData = Attributes.status_effects[status.type]
	var output: Array[Modifier] = []

	for attribute_data: Attributes.StatusAttributeData in status_data.attributes:
		#calculate the total effect based on the number of stacks.
		var total_additive: float = attribute_data.additive_per_stack * status.stack
		var total_multiplicative: float = pow(attribute_data.multiplicative_per_stack, status.stack)

		#create a new modifier instance. note that we don't handle cooldowns here,
		#as the status effect's cooldown is managed by the add_status function's timer logic.
		#the source_id should be carried over if needed, assuming statuseffect has one.
		var new_modifier := Modifier.new(
			attribute_data.attribute,
			total_multiplicative,
			total_additive,
			-1.0, #cooldown is permanent, as we handle expiration manually
			null, #status effects generally don't use override.
			status.source_id #doesnt actually work rn
		)
		new_modifier.cooldown = -1.0 #status-modifiers are always permanent
		#they are manually removed when their parent status runs out
		output.append(new_modifier)

	return output

func register_stat(attr: Attributes.id, value: float) -> void: #registers a stat
	if value == null:
		return
	base_stats[attr] = value #overwrites if neccessary
	_effective_cache.erase(attr)  #ensure clean first read
	stat_changed.emit(attr)

func register_dynamic_stat(key: StringName, value: float) -> void:
	register_stat(get_dynamic_id(key), value)

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

func has_dynamic_stat(key: StringName) -> bool:
	return base_stats.has(get_dynamic_id(key))

func pull_stat(attr: Attributes.id) -> Variant:
	if _effective_cache.has(attr):
		return _effective_cache[attr] #return cache

	if attr == Attributes.id.COOLDOWN:
		return _pull_cooldown_stat()
	if attr == Attributes.id.ATTACK_RATE:
		return _pull_attack_rate_stat()

	if not has_stat(attr):
		return null #unregistered stat!

	var upgraded_value := base_stats[attr]
	var perm_sum_add: float = 0.0
	var perm_product_mult: float = 1.0
	var perm_override = null

	for modifier: Modifier in _permanent_modifiers:
		if modifier.attribute != attr:
			continue

		perm_sum_add += modifier.additive
		perm_product_mult *= modifier.multiplicative
		if modifier.override != null:
			perm_override = modifier.override

	upgraded_value = upgraded_value * perm_product_mult + perm_sum_add if perm_override == null else perm_override

	#--- stage 2: apply transient modifiers to the upgraded stat ---
	var sum_add: float = 0.0
	var product_mult: float = 1.0
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

	#--- stage 3: apply global (relic) modifiers ---
	var final_value: float = transient_value #start with the result of stage 2
	var global_modifiers: Array[Modifier] = Run.player.get_modifiers_for_unit(self.unit)

	if not global_modifiers.is_empty():
		var global_sum_add: float = 0.0
		var global_product_mult: float = 1.0
		var global_override = null #global overrides are powerful, use with care

		for modifier: Modifier in global_modifiers:
			if modifier.attribute != attr:
				continue

			global_sum_add += modifier.additive
			global_product_mult *= modifier.multiplicative
			if modifier.override != null:
				global_override = modifier.override

		final_value = (final_value + global_sum_add) * global_product_mult if global_override == null else global_override

	return final_value

func _pull_cooldown_stat() -> Variant: ##resolves cooldown in cooldown-space first, then applies flat attacks-per-second bonuses in rate-space
	if not has_stat(Attributes.id.COOLDOWN):
		return null

	var global_modifiers: Array[Modifier] = Run.player.get_modifiers_for_unit(self.unit)
	var cooldown_value: float = base_stats[Attributes.id.COOLDOWN]
	cooldown_value = _apply_modifier_stage(cooldown_value, Attributes.id.COOLDOWN, _permanent_modifiers)
	cooldown_value = _apply_modifier_stage(cooldown_value, Attributes.id.COOLDOWN, _modifiers)
	cooldown_value = _apply_modifier_stage(cooldown_value, Attributes.id.COOLDOWN, global_modifiers)
	cooldown_value = maxf(cooldown_value, MIN_EFFECTIVE_COOLDOWN)

	var attack_rate_bonus: float = 0.0
	attack_rate_bonus = _apply_modifier_stage(attack_rate_bonus, Attributes.id.ATTACK_RATE, _permanent_modifiers)
	attack_rate_bonus = _apply_modifier_stage(attack_rate_bonus, Attributes.id.ATTACK_RATE, _modifiers)
	attack_rate_bonus = _apply_modifier_stage(attack_rate_bonus, Attributes.id.ATTACK_RATE, global_modifiers)

	var resolved_attack_rate: float = maxf((1.0 / cooldown_value) + attack_rate_bonus, MIN_EFFECTIVE_ATTACK_RATE)
	var final_value: float = 1.0 / resolved_attack_rate
	_effective_cache[Attributes.id.COOLDOWN] = final_value
	return final_value

func _pull_attack_rate_stat() -> Variant: ##returns the resolved flat attacks-per-second bonus for debugging and future facade access
	var global_modifiers: Array[Modifier] = Run.player.get_modifiers_for_unit(self.unit)
	var attack_rate_bonus: float = 0.0
	attack_rate_bonus = _apply_modifier_stage(attack_rate_bonus, Attributes.id.ATTACK_RATE, _permanent_modifiers)
	attack_rate_bonus = _apply_modifier_stage(attack_rate_bonus, Attributes.id.ATTACK_RATE, _modifiers)
	attack_rate_bonus = _apply_modifier_stage(attack_rate_bonus, Attributes.id.ATTACK_RATE, global_modifiers)
	_effective_cache[Attributes.id.ATTACK_RATE] = attack_rate_bonus
	return attack_rate_bonus

func _apply_modifier_stage(base_value: float, attr: Attributes.id, modifiers: Array[Modifier]) -> float: ##applies one modifier layer using the repo's standard base*mult+add convention
	var sum_add: float = 0.0
	var product_mult: float = 1.0
	var override = null

	for modifier: Modifier in modifiers:
		if modifier.attribute != attr:
			continue

		sum_add += modifier.additive
		product_mult *= modifier.multiplicative
		if modifier.override != null:
			override = modifier.override

	return base_value * product_mult + sum_add if override == null else override

func pull_dynamic_stat(key: StringName) -> Variant:
	return pull_stat(get_dynamic_id(key))

#data retrieval functions
func has_status(status: Attributes.Status, threshold: float = 0.0) -> bool:
	if not _status_effects.has(status):
		return false
	return _status_effects[status].stack > threshold

func get_status_count(status: Attributes.Status) -> float:
	if not _status_effects.has(status):
		return 0.0
	return _status_effects[status].stack

func get_active_statuses() -> Array[StatusEffect]: ##returns active real status objects for systems that also need statuslike effects
	var statuses: Array[StatusEffect] = []
	for status_type: Attributes.Status in _status_effects:
		var status: StatusEffect = _status_effects[status_type]
		if status.stack > 0.0:
			statuses.append(status)

	return statuses

func blocks_statuslike_effects() -> bool: ##returns whether attached statuslike effects should currently be rejected
	return _status_effects.has(Attributes.Status.CLEANSE)

func get_save_data() -> Dictionary:
	return {} #TODO
