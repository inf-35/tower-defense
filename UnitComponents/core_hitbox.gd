extends Hitbox
class_name CoreHitbox
#custom behaviour for the core hitbox --- directly affects player health

func _ready() -> void:
	area_entered.connect(func(area: Area2D):
		if not area is Hitbox:
			return

		if area.unit == null:
			return

		if not area.unit.hostile:
			return
			
		if area.unit.abstractive:
			return

		Run.player.hp -= 1

		area.unit.died.emit.call_deferred(HitReportData.new())
	)
