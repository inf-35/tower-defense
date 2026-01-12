extends EffectPrototype
class_name MucousSacEffect

@export var hazard_scene: PackedScene ## Assign 'PoisonCloud.tscn' here
@export var spawn_chance: float = 0.1
@export var hazard_lifetime: float = 3.0

@export var required_status: Attributes.Status = Attributes.Status.POISON
@export var required_threshold: float = 0.0

func _init() -> void:
	event_hooks = [GameEvent.EventType.DIED]
	global = true

func create_instance() -> EffectInstance:
	var i = EffectInstance.new()
	apply_generics(i)
	return i

func _handle_attach(_i: EffectInstance) -> void: pass
func _handle_detach(_i: EffectInstance) -> void: pass

func _handle_event(_i: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.DIED:
		return
		
	var dying_unit: Unit = event.unit
	var hit_report: HitReportData = event.data as HitReportData
	var killer_unit: Unit
	
	if hit_report:
		killer_unit = hit_report.source
	
	if not is_instance_valid(dying_unit): return
	
	# dying unit is hostile?
	if not dying_unit.hostile: return
	
	# dying unit has poison?
	if not is_instance_valid(dying_unit.modifiers_component): return
	if not dying_unit.modifiers_component.has_status(required_status, required_threshold): return
	
	# proc chance
	if randf() <= spawn_chance:
		_spawn_cloud(dying_unit.global_position, dying_unit, killer_unit)

func _spawn_cloud(pos: Vector2, _dead_unit: Unit, killer_unit: Unit) -> void:
	if not hazard_scene: return
	
	var island = References.island
	if not is_instance_valid(island): return
	
	var cloud = hazard_scene.instantiate() as Hurtbox
	if not cloud: return
	
	cloud.affiliations_hit = Hitbox.get_mask(_dead_unit.hostile)
	cloud.lifetime = hazard_lifetime

	References.projectiles.add_child.call_deferred(cloud)
	cloud.setup(pos, killer_unit if is_instance_valid(killer_unit) else null)
