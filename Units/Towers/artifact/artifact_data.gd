extends Resource
class_name ArtifactData

@export_group("Reward")
@export var reward: Reward ## reward granted upon completion
@export var waves_to_unlock: int = 1 ## how long to defend/wait after discovery

@export_group("Visuals")
@export var discovered_color: Color = Color.CYAN
