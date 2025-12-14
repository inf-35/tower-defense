# poison_explosion_effect.gd
extends GlobalEffect
class_name EffectKillExplosionEffect

# --- configuration ---
@export_category("Trigger")
# the status effect that must be on the unit to trigger the explosion
@export var trigger_status: Attributes.Status = Attributes.Status.POISON

@export_category("Effect")
# this allows a designer to configure the explosion as if it were a standard attack.
@export var aoe_hit_data_prototype: AttackData  ## the AttackData resource that defines the explosion's properties (damage, radius, etc.). DeliveryData will be automatically generated and does not derive from this
#configuration
const _DEBUG: bool = true

func initialise() -> void:
	# connect to the global signal for unit deaths
	References.unit_died.connect(_on_unit_died)

# this is the core of the relic's logic, triggered by the global signal
func _on_unit_died(unit: Unit, _hit_report_data) -> void:
	# --- 1. check prerequisites ---
	if not is_instance_valid(unit) or not is_instance_valid(unit.modifiers_component):
		return
	
	# ensure the required data is configured in the editor
	if not is_instance_valid(aoe_hit_data_prototype):
		push_warning("EffectKillExplosionEffect: aoe_hit_data_prototype is not configured.")
		return
		
	# this relic should only trigger on hostile enemy deaths
	if not unit.hostile:
		return

	# --- 2. check the trigger condition ---
	# check if the dying unit has the required status effect
	if not unit.modifiers_component.has_status(trigger_status, 1.0):
		return

	# --- 3. execute the effect ---
	if _DEBUG: print("EffectKillExplosionEffect: Effect explosion triggered at: ", unit.global_position)
	# create the HitData for the explosion from our configured prototype
	var explosion_hit: HitData = aoe_hit_data_prototype.generate_hit_data()

	explosion_hit.source = References.island.get_towers_by_type(Towers.Type.PLAYER_CORE)[0] #get the player core as source 
	explosion_hit.target = null # this is a targetless AOE
	
	# the explosion should target other hostile units
	explosion_hit.target_affiliation = References.HOSTILE_AFFILIATION
	
	# create the DeliveryData for an instantaneous, centered AOE
	var delivery_data := DeliveryData.new()
	delivery_data.use_source_position_override = true
	delivery_data.source_position = unit.global_position #start the projectile at the unit's position
	delivery_data.delivery_method = DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT
	delivery_data.intercept_position = unit.global_position # center the explosion on the dying unit
	
	# command the CombatManager to resolve this new hit
	CombatManager.resolve_hit(explosion_hit, delivery_data)
