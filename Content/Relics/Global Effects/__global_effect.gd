# global_effect.gd
extends Node
class_name GlobalEffect

# this function will be called by the GlobalModifierService immediately after instantiation
# to give the effect any necessary context.
func initialise() -> void:
	# this virtual function will be overridden by concrete effects
	pass
