extends InteractiveRichTextLabel
class_name WaveCounter

func _ready() -> void:
	super._ready()

	UI.start_wave.connect(func(wave: int):
		text = str(wave)
	)
