extends Node #Waves

signal wave_started(wave_number: int)

var wave: int = 0 #current wave number

func start_wave(wave: int):
	References.island.spawn_enemies(wave)
	References.island.expand_by_block(8)
	wave_started.emit(wave)

	
func _ready():
	var timer := Timer.new()
	timer.one_shot = false
	add_child(timer)
	timer.start(2.0)
	timer.timeout.connect(func():
		wave += 1
		start_wave(wave)
	)
