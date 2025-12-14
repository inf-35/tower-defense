# chain_lightning_effect.gd
extends EffectPrototype
class_name ChainLightningEffect

# --- configuration (designer-friendly, configured on the .tres resource) ---
@export var params: Dictionary = {
	"max_jumps": 3,
	"jump_radius": 150.0,
	"damage_falloff_multiplier": 0.66,
}

# this effect is reactive, so its internal state is minimal
var state: Dictionary = {}

func _init() -> void:
	# this effect needs to listen for when its host successfully deals a hit
	self.event_hooks = [GameEvent.EventType.HIT_DEALT]

# this is the main handler, called by the unit's event bus
func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	# --- 1. check prerequisites ---
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return
	
	var hit_report: HitReportData = event.data as HitReportData
	if not is_instance_valid(hit_report.target) or hit_report.recursion > 0:
		return

	# --- 2. get data from the instance ---
	var host_tower: Tower = instance.host as Tower
	if not is_instance_valid(host_tower) or not is_instance_valid(host_tower.attack_component):
		return

	var p_max_jumps: int = instance.params.get("max_jumps", 3)
	var p_jump_radius: float = instance.params.get("jump_radius", 150.0)
	var p_falloff: float = instance.params.get("damage_falloff_multiplier", 0.66)

	# --- 3. start the chain lightning sequence ---
	var primary_target: Unit = hit_report.target
	var already_hit: Array[Unit] = [primary_target]
	var last_hit_target: Unit = primary_target
	var current_damage: float = host_tower.attack_component.get_stat(
		host_tower.modifiers_component, host_tower.attack_component.attack_data, Attributes.id.DAMAGE
	)

	for i: int in range(p_max_jumps):
		var next_target: Unit = _find_next_jump_target(last_hit_target, p_jump_radius, already_hit)
		
		if not is_instance_valid(next_target):
			break
			
		current_damage *= p_falloff
		
		var jump_hit_data: HitData = host_tower.attack_component.attack_data.generate_hit_data()
		jump_hit_data.source = host_tower
		jump_hit_data.target = next_target
		jump_hit_data.damage = current_damage
		jump_hit_data.target_affiliation = primary_target.hostile
		jump_hit_data.recursion = hit_report.recursion + 1
		
		var delivery_data := DeliveryData.new() 
		delivery_data.delivery_method = DeliveryData.DeliveryMethod.HITSCAN
		delivery_data.use_source_position_override = true
		delivery_data.source_position = last_hit_target.global_position

		host_tower.deal_hit(jump_hit_data, delivery_data)
		
		already_hit.append(next_target)
		last_hit_target = next_target

# this helper now accepts the jump radius as a parameter
func _find_next_jump_target(from_target: Unit, jump_radius: float, excluded_targets: Array[Unit]) -> Unit:
	var potential_targets: Array[Unit] = CombatManager.get_units_in_radius(jump_radius, from_target.global_position, from_target.hostile, excluded_targets)
	var closest_dist_sq: float = INF
	var closest_target: Unit = null
	for potential_target: Unit in potential_targets:
		var dist_sq: float = from_target.global_position.distance_squared_to(potential_target.global_position)
		if dist_sq < closest_dist_sq:
			closest_dist_sq = dist_sq
			closest_target = potential_target
				
	return closest_target
