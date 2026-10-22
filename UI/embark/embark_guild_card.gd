extends EmbarkChoice
class_name EmbarkGuildCard

@export var guild: GuildData ##canonical starting package selected by this card; the icon remains scene-authored

func _ready() -> void:
	title = guild.title
	super._ready()
