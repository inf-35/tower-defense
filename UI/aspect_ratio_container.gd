@tool #makes the script run in the editor for instant feedback
extends AspectRatioContainer
class_name AspectRatioSolid

#store the last known bounding box of the siblings.
#we use a vector2 to track both max width and max height.
var _last_target_bounds: Vector2 = Vector2(-1, -1)

func _process(_delta) -> void:
	var parent = get_parent() as Control
	if not parent:
		if custom_minimum_size != Vector2.ZERO:
			custom_minimum_size = Vector2.ZERO
		return

	#--- 1. find the maximum sibling bounding box ---
	var max_sibling_bounds: Vector2 = Vector2.ZERO
	for child in parent.get_children():
		#rule: ignore ourselves.
		if child == self:
			continue

		#rule: ignore other instances of this same class.
		if child is AspectRatioSolid:
			continue

		#we only consider visible control nodes.
		var c = child as Control
		if c and c.is_visible_in_tree():
			#find the max width and height among all valid siblings.
			max_sibling_bounds.x = max(max_sibling_bounds.x, c.size.x)
			max_sibling_bounds.y = max(max_sibling_bounds.y, c.size.y)

	#--- 2. the safeguard: only update on change ---
	#bail out if the collective size of the siblings hasn't changed.
	if max_sibling_bounds.is_equal_approx(_last_target_bounds):
		return

	#a relevant sibling has changed size. this is our trigger.
	_last_target_bounds = max_sibling_bounds

	#if there are no valid siblings to measure, reset our size.
	if max_sibling_bounds == Vector2.ZERO:
		custom_minimum_size = Vector2.ZERO
		return

	#--- 3. calculate aspect-correct size for both dimensions ---
	#we need to find a size that is >= max_sibling_bounds and maintains our ratio.
	var new_min_size: Vector2

	#calculate the aspect ratio of the siblings' bounding box.
	#we must avoid dividing by zero if the max height is 0.
	var sibling_content_ratio: float = 0.0
	if max_sibling_bounds.y > 0:
		sibling_content_ratio = max_sibling_bounds.x / max_sibling_bounds.y

	#compare the siblings' collective shape to our target shape.
	if sibling_content_ratio > ratio:
		#the siblings are proportionally wider than our ratio.
		#therefore, we must match their width, and calculate our height from that.
		new_min_size.x = max_sibling_bounds.x
		new_min_size.y = max_sibling_bounds.x / ratio
	else:
		#the siblings are proportionally taller or equal.
		#therefore, we must match their height, and calculate our width from that.
		new_min_size.y = max_sibling_bounds.y
		new_min_size.x = max_sibling_bounds.y * ratio

	#apply the final calculated minimum size.
	custom_minimum_size = new_min_size
