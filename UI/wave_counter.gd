extends InteractiveRichTextLabel
class_name WaveCounter

func _ready():
	super._ready()
	
	UI.start_wave.connect(func(wave: int):
		text = str(wave)
	)
