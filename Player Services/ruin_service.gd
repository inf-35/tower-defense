extends Node
class_name RuinService

# defines why a tower was ruined, which dictates its fate
enum RuinReason { KILLED, SOLD }

# we track the tower node itself and the reason it was ruined
var _ruined_towers: Dictionary[Tower, RuinReason] = {}

#initialise is the _ready substitute
func initialise() -> void:
	# this service is the only thing that needs to listen for the end of a wave
	Phases.wave_ended.connect(_on_wave_ended)

# the main public API for towers to register themselves as ruined
func register_ruin(tower: Tower, reason: RuinReason) -> void:
	if not is_instance_valid(tower) or _ruined_towers.has(tower):
		return
	
	_ruined_towers[tower] = reason

# this function is the core of the system's logic
func _on_wave_ended(_wave_number: int) -> void:
	if _ruined_towers.is_empty():
		return
		
	# create a copy of the keys to iterate over, as the dictionary will be modified
	var towers_to_process: Array[Tower] = _ruined_towers.keys()
	
	for tower: Tower in towers_to_process:
		if not is_instance_valid(tower):
			# if the tower was somehow destroyed by another means, clean it up
			_ruined_towers.erase(tower)
			continue

		var reason: RuinReason = _ruined_towers[tower]
		
		match reason:
			RuinReason.KILLED:
				# towers that were killed are resurrected
				tower.resurrect()
			RuinReason.SOLD:
				# towers that were sold are permanently removed
				tower.queue_free()
	
	# clear the dictionary for the next wave
	_ruined_towers.clear()
