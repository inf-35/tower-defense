extends GlobalEffect
class_name InterestRelic

@export var interest: float = 0.0 ##proportion of player flux earned as interest at the end of every wave
@export var floor: float = 0.0 ##minimum interest
@export var cap: float = 0.0 ##maximum interest

func initialise() -> void:
	Phases.wave_ended.connect(func(_wave_number: int): _on_wave_ended())

func _on_wave_ended() -> void:
	Player.flux += clampf(Player.flux * interest, floor, cap)
	
