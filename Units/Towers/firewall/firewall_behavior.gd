extends Behavior
class_name FirewallBehavior

#overrides default navcost behaviour
func get_navcost_for_cell(cell: Vector2i): #see Tower.get_navcost_for_cell
	var tower: Tower = unit as Tower
	var local_pos: Vector2i = cell - tower.tower_position
	
	#detemine where the central hollow is
	#for a 3x1 tower, the center is (1,0), and for a 1x3 tower (rotated) the center is (0,1)
	var center_x := floori(tower.size.x * 0.5)
	var center_y := floori(tower.size.y * 0.5)
	var gate_local_pos := Vector2i(center_x, center_y)
	if local_pos == gate_local_pos:
		return Navigation.BASE_COST
	else:
		return Towers.get_tower_navcost(tower.type)
