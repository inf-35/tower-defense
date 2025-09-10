# particle_manager.gd (Autoload Singleton)
extends Node

# --- configuration ---
# in the inspector, link effect names (as StringNames) to your pre-configured
# GPUParticles2D PackedScene files.
@export var particle_library: Dictionary[StringName, PackedScene] = {
	ID.Particles.ENEMY_HIT_SPARKS : preload("res://Assets/Particles/enemy_hit_sparks.tscn"),
	ID.Particles.ENEMY_DEATH_SPARKS: preload("res://Assets/Particles/enemy_death_sparks.tscn")
}

# --- object pooling ---
const POOL_SIZE_PER_EMITTER: int = 3 #initial pool size
var _emitter_pool: Dictionary[StringName, Array] = {} #each array contains GPUParticles2D instances

func _ready() -> void:
	# pre-populate the object pools for each effect type at the start of the game
	for effect_name: StringName in particle_library:
		_emitter_pool[effect_name] = []
		var scene: PackedScene = particle_library[effect_name]
		if not is_instance_valid(scene):
			push_error("ParticleManager: Scene for '%s' is not valid." % effect_name)
			continue
			
		for i: int in POOL_SIZE_PER_EMITTER:
			var emitter: GPUParticles2D = scene.instantiate()
			# add the emitter to a dedicated container node for organization
			add_child(emitter)
			_emitter_pool[effect_name].append(emitter)

# the main public API. any script can call this to play a particle effect.
func play_particles(effect_name: StringName, position: Vector2, rotation: float = 0.0) -> void:
	# 1. get an available emitter from the pool
	if not _emitter_pool.has(effect_name) or _emitter_pool[effect_name].is_empty():
		var emitter: GPUParticles2D = particle_library[effect_name].instantiate()
		add_child(emitter)
		_emitter_pool[effect_name].append(emitter)
		
	var emitter: GPUParticles2D = _emitter_pool[effect_name].pop_front()
	
	# 2. configure and play the effect
	emitter.global_position = position
	emitter.rotation = rotation
	emitter.restart() # reset and start the particle emission
	
	# 3. create a timer to return the emitter to the pool after its lifetime.
	# this timer correctly respects get_tree().paused.
	var lifetime: float = emitter.lifetime
	await get_tree().create_timer(lifetime).timeout
	
	# after the timer, if the emitter is still valid, return it to the pool
	if is_instance_valid(emitter):
		_emitter_pool[effect_name].append(emitter)
