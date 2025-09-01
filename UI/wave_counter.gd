extends Label
class_name WaveCounter

func _ready():
	UI.start_wave.connect(func(wave: int):
		text = "WAVE " + str(wave)
	)
