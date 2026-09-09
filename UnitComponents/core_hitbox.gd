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

		if not area.unit.hostile:
			return
			
		if area.unit.abstractive:
			return

		if Run.has_active_run() and is_instance_valid(Run.boss_encounters) and Run.boss_encounters.is_active_boss(area.unit):
			Run.boss_encounters.fail_boss_reached_keep()
			return

		Run.player.hp -= 1

		area.unit.died.emit.call_deferred(HitReportData.new())
	)
