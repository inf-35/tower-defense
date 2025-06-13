extends EventData
class_name HitData #stores information about a hit (runtime)

var source: Unit #dealer of hit
var target: Unit #receiver of hit

var damage: float = 0.0
var modifiers: Array[Modifier] = []

var expected_damage: float = 0.0 #see TargetingCoordinator, projected amount of damage caused
#see unit.gd, deal_hit and take_hit
