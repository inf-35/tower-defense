extends EventData
class_name HitData #stores information about a hit

var source: Unit #dealer of hit
var target: Unit #receiver of hit

var damage: float = 0.0
#see unit.gd, deal_hit and take_hit
