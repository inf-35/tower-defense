extends DefaultBehavior
class_name SpikesBehavior

func get_navcost_for_cell(_cell: Vector2i) -> int: ##keeps spike traps path-transparent while still occupying a tower cell
	return Navigation.BASE_COST
