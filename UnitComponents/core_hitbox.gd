extends Hitbox
class_name CoreHitbox
#custom behaviour for the core hitbox --- directly affects player health

func _ready() -> void: ##registers the inherited debug hitbox group before wiring keep-damage collision behavior
	super._ready()
	monitoring = true #the core is the one hitbox that actively watches for entering enemies
	area_entered.connect(func(area: Area2D):
		if not area is Hitbox:
			return

		if area.unit == null:
			return
		if area.unit.is_queued_for_deletion():
			return

		if not area.unit.hostile:
			return
			
		if area.unit.abstractive:
			return

		if Run.has_active_run() and is_instance_valid(Run.boss_encounters) and Run.boss_encounters.is_active_boss(area.unit):
			Run.boss_encounters.fail_boss_reached_keep()
			return

		var enemy: Unit = area.unit
		#health-loss effects can clear the wave; resolve outside the physics collision flush.
		var resolve_keep_damage: Callable = func() -> void:
			if not Run.has_active_run() or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				return
			Run.player.hp -= 1
			if Run.has_active_run() and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				enemy.died.emit(HitReportData.new())
		resolve_keep_damage.call_deferred()
	)
