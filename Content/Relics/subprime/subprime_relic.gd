extends GlobalEffect
class_name SubprimeRelic

@export var maximum_bonus: float = 1.0 ##how much more flux is earned at zero distance as a proportion of the original flux earned
@export var gradient_floor: float = 200.0 
@export var gradient_ceiling: float = 30.0

func initialise() -> void:
	References.unit_died.connect(_on_unit_died)

func _on_unit_died(target: Unit, hit_report_data: HitReportData):
	if not target.hostile:
		return #only care about hostile kills
		
	if not hit_report_data.death_caused:
		return #only care about kills
	
	var distance: float = (target.global_position).length()
	var proportion: float = clampf((gradient_floor - distance) / (gradient_floor - gradient_ceiling), 0.0, 1.0)
	hit_report_data.flux_value *= 1.0 + proportion * maximum_bonus
	print(hit_report_data.flux_value)
	#this modified flux value will be passed into on_killed
	pass
