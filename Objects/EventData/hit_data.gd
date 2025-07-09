extends EventData
class_name HitData #stores information about a hit (runtime)

var source: Unit #dealer of hit
var target: Unit #receiver of hit

var damage: float = 0.0
var radius: float = 0.0 #AOE effect of the hit
var modifiers: Array[Modifier] = []
var status_effects: Dictionary[Attributes.Status, Vector2] = {} #Attributes.Status -> Vector2(stack, cooldown)

var expected_damage: float = 0.0 #see TargetingCoordinator, projected amount of damage caused

var vfx_on_spawn : VFXInfo #see VFXManager and VFXInstance
var vfx_on_impact : VFXInfo
#see unit.gd, deal_hit and take_hit and AttackData
