#particle_manager.gd (autoload singleton)
extends Node

#--- configuration ---
@export var particle_library: Dictionary[StringName, PackedScene] = {
	ID.Particles.ENEMY_HIT_SPARKS : preload("res://Assets/Particles/enemy_hit_sparks.tscn"),
	ID.Particles.ENEMY_DEATH_SPARKS: preload("res://Assets/Particles/enemy_death_sparks.tscn")
}

#--- object pooling ---
const INITIAL_POOL_SIZE: int = 5
#dictionary[stringname, array[gpuparticles2d]]
var _emitter_pool: Dictionary = {}

func _ready() -> void:
	#initial shader compilation
	for effect_name: StringName in particle_library:
		_emitter_pool[effect_name] = []
		_expand_pool(effect_name, INITIAL_POOL_SIZE)
	#pre-populate pools
	for effect_name: StringName in particle_library:
		play_particles(effect_name, Vector2(10000, 203000.0))

func play_particles(effect_name: StringName, position: Vector2, rotation: float = 0.0) -> void:
	if not _emitter_pool.has(effect_name):
		push_warning("ParticleManager: Unknown effect '%s'" % effect_name)
		return

	#1. find an available emitter
	var emitter: GPUParticles2D = _find_free_emitter(effect_name)

	#2. if none available, expand the pool and grab the new one
	if not emitter:
		emitter = _expand_pool(effect_name, 1).back()

	#3. configure and play
	emitter.global_position = position
	emitter.rotation = rotation
	emitter.emitting = true
	#note: no need to manually manage return. the emitter stays in the pool array.
	#we just check 'emitting' property next time we need one.

func _find_free_emitter(effect_name: StringName) -> GPUParticles2D:
	var pool: Array = _emitter_pool[effect_name]
	for emitter: GPUParticles2D in pool:
		if not emitter.emitting:
			return emitter
	return null

func _expand_pool(effect_name: StringName, count: int) -> Array:
	var scene: PackedScene = particle_library[effect_name]
	var new_emitters: Array = []

	if not is_instance_valid(scene):
		return []

	for i: int in count:
		var emitter: GPUParticles2D = scene.instantiate()
		emitter.one_shot = true #crucial for pooling logic
		emitter.emitting = false
		add_child(emitter)

		_emitter_pool[effect_name].append(emitter)
		new_emitters.append(emitter)

	return new_emitters
