extends Hitbox
class_name CoreHitbox
#custom behaviour for the core hitbox --- directly affects player health

func _ready():
	area_entered.connect(func(area: Area2D):
		if not area is Hitbox:
			return
		
		if area.unit == null:
			return
		
		if not area.unit.hostile:
			return
			

		Player.flux -= area.unit.health_component.health
		area.unit.died.emit()
	)
