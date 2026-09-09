#audio.gd (autoload singleton)
extends Node

#--- configuration ---
#in the inspector, we link sound ids to audiostream resources.
#values may be a single stream or an array of variations.
var sound_library: Dictionary[StringName, Variant] = {
	ID.Sounds.ENEMY_HIT_SOUND : preload("res://Sounds/thud.wav"),
	ID.Sounds.BUTTON_CLICK_SOUND : preload("res://Sounds/button_click.wav"),
	ID.Sounds.BUTTON_HOVER_SOUND : preload("res://Sounds/hover_click.wav"),
	ID.Sounds.TOWER_PLACED_SOUND : preload("res://Sounds/tower_place_down.wav"),
	ID.Sounds.MUSIC_COMBAT_LOOP : preload("res://Sounds/combat_loop.wav"),
	ID.Sounds.AMBIENCE_BIRDSONG : [
		preload("res://Sounds/birdsong_1.wav"),
		preload("res://Sounds/birdsong_rattle.wav"),
	],
	ID.Sounds.AMBIENCE_WOODS : [
		preload("res://Sounds/woods_ambient_1.wav"),
		preload("res://Sounds/woods_ambient_2.wav"),
	],
	ID.Sounds.COIN_PICKUP_SOUND : [
		preload("res://Sounds/coin_clink_1.wav"),
		preload("res://Sounds/coin_click_2.wav"),
		preload("res://Sounds/coin_click_3.wav"),
	],
	ID.Sounds.COIN_SPEND_SOUND : [
		preload("res://Sounds/coins_spend.wav"),
	],
	ID.Sounds.ARROW_FIRE_SOUND : [
		preload('res://Sounds/arrow_fire.wav'),
	],
	ID.Sounds.ARROW_THUNK_SOUND : [
		preload("res://Sounds/arrow_thunk.wav"),
	],
	ID.Sounds.AOE_FIRE_SOUND : [
		preload("res://Sounds/aoe_aura.wav")
	],
	ID.Sounds.FLAME_FIRE_SOUND : [
		preload("res://Sounds/flame_fire.wav")
	],
	ID.Sounds.CANNON_FIRE_SOUND : [
		preload("res://Sounds/cannon_fire.wav")
	]
}

#--- object pooling ---
const SFX_POOL_SIZE: int = 10 #number of initial concurrent sound effects
const FATIGUE_WINDOW_SECONDS: float = 0.8
const FATIGUE_FREE_CALLS: float = 2.0
const FATIGUE_SATURATED_CALLS: float = 10.0
const FATIGUE_MAX_ATTENUATION_DB: float = -6.0

var _sfx_player_pool: Array[AudioStreamPlayer2D] = []
var _audio_player_tweens: Dictionary[AudioStreamPlayer2D, Array] = {} ##audiostreamplayer2d -> array[tween]
var _sound_fatigue: Dictionary[StringName, SoundFatigueState] = {}

class SoundFatigueState extends RefCounted:
	var score: float = 0.0
	var last_tick_msec: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	#pre-populate the object pool for 2d sound effect players
	for i: int in SFX_POOL_SIZE:
		var player := AudioStreamPlayer2D.new()
		add_child(player)
		#critical: assign this player to the "sfx" audio bus
		player.bus = &"SFX"
		_sfx_player_pool.append(player)

	var audio_ambience := AudioAmbience.new()
	add_child(audio_ambience)

func play_sound(sound_name: StringName, volume: float = 0.0, position: Vector2 = Vector2.ZERO, is_sfx: bool = true) -> AudioStreamPlayer2D: ##plays one positional sound id, applying centralized repeat-call fatigue before playback
	if sound_name == &"":
		return null

	#1. check if the requested sound exists in our library
	if not sound_library.has(sound_name):
		push_warning("AudioManager: Sound '%s' not found in library." % sound_name)
		return null

	#2. check if there is an available player in the pool
	if _sfx_player_pool.is_empty():
		var new_player := AudioStreamPlayer2D.new()
		add_child(new_player)
		new_player.bus = &"SFX"
		_sfx_player_pool.append(new_player)

	#3. get a player from the pool and configure it
	var player: AudioStreamPlayer2D = _sfx_player_pool.pop_front()

	var stream_resource: Variant = sound_library[sound_name]
	if stream_resource is Array:
		var stream_options: Array = stream_resource
		if stream_options.is_empty():
			_sfx_player_pool.append(player)
			return null
		player.stream = stream_options.pick_random() as AudioStream
	elif stream_resource is AudioStream:
		player.stream = stream_resource
	else:
		_sfx_player_pool.append(player)
		return null

	if not is_instance_valid(player.stream):
		_sfx_player_pool.append(player)
		return null

	player.global_position = position
	player.pitch_scale = 1.0
	if is_sfx:
		player.volume_db = _apply_sound_fatigue(sound_name, volume)
		player.pitch_scale = randf_range(0.6, 1.2)
	_connect_finished_once(player)
	player.play()
	return player

func create_registered_audio_tween(audio_stream_player: AudioStreamPlayer2D) -> Tween:
	var tween: Tween = create_tween()
	if not _audio_player_tweens.has(audio_stream_player):
		_audio_player_tweens[audio_stream_player] = []
	_audio_player_tweens[audio_stream_player].append(tween)
	tween.finished.connect(func():
		_audio_player_tweens[audio_stream_player].erase(tween)
	)
	return tween

func stop_sound(audio_stream_player: AudioStreamPlayer2D):
	audio_stream_player.stop()
	for tween: Tween in _audio_player_tweens.get(audio_stream_player, []):
		tween.stop()
	_on_sfx_player_finished(audio_stream_player)

func _connect_finished_once(player: AudioStreamPlayer2D) -> void: ##arms a pooled player return callback without duplicating stale one-shot connections
	var callback: Callable = _on_sfx_player_finished.bind(player)
	if player.finished.is_connected(callback):
		player.finished.disconnect(callback)
	player.finished.connect(callback, CONNECT_ONE_SHOT)

func get_volume_from_damage(damage: float) -> float:
	return (log(maxf(damage, 0.0001)) * 0.8) - 10.0

func _apply_sound_fatigue(sound_name: StringName, base_volume_db: float) -> float: ##attenuates repeated calls of the same sound id within a short realtime window
	var state: SoundFatigueState = _get_sound_fatigue_state(sound_name)
	var current_tick_msec: int = Time.get_ticks_msec()
	var elapsed_seconds: float = _get_fatigue_elapsed_seconds(state, current_tick_msec)
	state.score = _decay_fatigue_score(state.score, elapsed_seconds)

	var saturation: float = inverse_lerp(FATIGUE_FREE_CALLS, FATIGUE_SATURATED_CALLS, state.score)
	var attenuation_db: float = lerpf(0.0, FATIGUE_MAX_ATTENUATION_DB, clampf(saturation, 0.0, 1.0))

	state.score += 1.0
	state.last_tick_msec = current_tick_msec
	return base_volume_db + attenuation_db

func _get_sound_fatigue_state(sound_name: StringName) -> SoundFatigueState: ##returns the persistent fatigue bucket for a sound id
	if _sound_fatigue.has(sound_name):
		return _sound_fatigue[sound_name]

	var state := SoundFatigueState.new()
	state.last_tick_msec = Time.get_ticks_msec()
	_sound_fatigue[sound_name] = state
	return state

func _get_fatigue_elapsed_seconds(state: SoundFatigueState, current_tick_msec: int) -> float: ##converts monotonic ticks into a non-negative realtime delta for fatigue decay
	if state.last_tick_msec <= 0:
		return 0.0

	return maxf(float(current_tick_msec - state.last_tick_msec) / 1000.0, 0.0)

func _decay_fatigue_score(score: float, elapsed_seconds: float) -> float: ##drops repeat-call pressure to zero once the sound has had enough quiet time
	if elapsed_seconds <= 0.0:
		return score

	var decay_calls: float = elapsed_seconds / FATIGUE_WINDOW_SECONDS
	return maxf(score - decay_calls, 0.0)

#this function is called when a sound effect has finished playing
func _on_sfx_player_finished(player: AudioStreamPlayer2D) -> void:
	#return the player to the back of the pool, ready for reuse
	if _sfx_player_pool.has(player):
		return
	_sfx_player_pool.append(player)
