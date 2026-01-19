# audio.gd (Autoload Singleton)
extends Node

# --- configuration ---
# in the inspector, we link sound names (as StringNames) to AudioStream resources.
# to support variations, a value can also be an Array of AudioStreams.
@export var sound_library: Dictionary[StringName, Variant] = {
	ID.Sounds.ENEMY_HIT_SOUND : preload("res://Sounds/thud.wav"),
	ID.Sounds.BUTTON_CLICK_SOUND : preload("res://Sounds/button_click.wav"),
	ID.Sounds.BUTTON_HOVER_SOUND : preload("res://Sounds/hover_click.wav"),
	ID.Sounds.TOWER_PLACED_SOUND : preload("res://Sounds/tower_place_down.wav")
}

# --- object pooling ---
const SFX_POOL_SIZE: int = 10 # number of initial concurrent sound effects
var _sfx_player_pool: Array[AudioStreamPlayer2D] = []

func _ready() -> void:  
	process_mode = Node.PROCESS_MODE_ALWAYS
	# pre-populate the object pool for 2D sound effect players
	for i: int in SFX_POOL_SIZE:
		var player := AudioStreamPlayer2D.new()
		add_child(player)
		# CRITICAL: assign this player to the "SFX" audio bus
		player.bus = &"SFX"
		_sfx_player_pool.append(player)

# the main public API for playing positional, one-shot sound effects.
func play_sound(sound_name: StringName, volume: float = 0.0, position: Vector2 = Vector2.ZERO) -> void:
	# 1. check if the requested sound exists in our library
	if not sound_library.has(sound_name):
		push_warning("AudioManager: Sound '%s' not found in library." % sound_name)
		return
	
	# 2. check if there is an available player in the pool
	if _sfx_player_pool.is_empty():
		var new_player := AudioStreamPlayer2D.new()
		add_child(new_player)
		new_player.bus = &"SFX"
		_sfx_player_pool.append(new_player)
	
	# 3. get a player from the pool and configure it
	var player: AudioStreamPlayer2D = _sfx_player_pool.pop_front()
	
	var stream_resource: Variant = sound_library[sound_name]
	
	# --- handle sound variations ---
	if stream_resource is Array:
		# if the library entry is an array, pick a random stream from it
		player.stream = stream_resource.pick_random() as AudioStream
	elif stream_resource is AudioStream:
		# otherwise, just use the single stream
		player.stream = stream_resource
	else:
		# invalid data, return the player to the pool
		_sfx_player_pool.append(player)
		return

	player.global_position = position
	player.volume_db = volume
	player.finished.connect(_on_sfx_player_finished.bind(player), CONNECT_ONE_SHOT)
	player.play()
	
# this function is called when a sound effect has finished playing
func _on_sfx_player_finished(player: AudioStreamPlayer2D) -> void:
	# return the player to the back of the pool, ready for reuse
	_sfx_player_pool.append(player)
