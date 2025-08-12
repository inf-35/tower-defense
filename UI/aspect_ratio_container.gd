@tool # Makes the script run in the editor for instant feedback
extends AspectRatioContainer
class_name AspectRatioSolid

# Store the last known bounding box of the siblings.
# We use a Vector2 to track both max width and max height.
var _last_target_bounds := Vector2(-1, -1)

func _process(_delta):
	var parent = get_parent() as Control
	if not parent:
		if custom_minimum_size != Vector2.ZERO:
			custom_minimum_size = Vector2.ZERO
		return

	# --- 1. Find the Maximum Sibling Bounding Box ---
	var max_sibling_bounds := Vector2.ZERO
	for child in parent.get_children():
		# Rule: Ignore ourselves.
		if child == self:
			continue
			
		# Rule: Ignore other instances of this same class.
		if child is AspectRatioSolid:
			continue

		# We only consider visible Control nodes.
		var c = child as Control
		if c and c.is_visible_in_tree():
			# Find the max width and height among all valid siblings.
			max_sibling_bounds.x = max(max_sibling_bounds.x, c.size.x)
			max_sibling_bounds.y = max(max_sibling_bounds.y, c.size.y)
			
	# --- 2. The Safeguard: Only Update on Change ---
	# Bail out if the collective size of the siblings hasn't changed.
	if max_sibling_bounds.is_equal_approx(_last_target_bounds):
		return

	# A relevant sibling has changed size. This is our trigger.
	_last_target_bounds = max_sibling_bounds
	
	# If there are no valid siblings to measure, reset our size.
	if max_sibling_bounds == Vector2.ZERO:
		custom_minimum_size = Vector2.ZERO
		return

	# --- 3. Calculate Aspect-Correct Size for Both Dimensions ---
	# We need to find a size that is >= max_sibling_bounds AND maintains our ratio.
	var new_min_size: Vector2
	
	# Calculate the aspect ratio of the siblings' bounding box.
	# We must avoid dividing by zero if the max height is 0.
	var sibling_content_ratio = 0.0
	if max_sibling_bounds.y > 0:
		sibling_content_ratio = max_sibling_bounds.x / max_sibling_bounds.y
	
	# Compare the siblings' collective shape to our target shape.
	if sibling_content_ratio > ratio:
		# The siblings are proportionally WIDER than our ratio.
		# Therefore, we must match their width, and calculate our height from that.
		new_min_size.x = max_sibling_bounds.x
		new_min_size.y = max_sibling_bounds.x / ratio
	else:
		# The siblings are proportionally TALLER or equal.
		# Therefore, we must match their height, and calculate our width from that.
		new_min_size.y = max_sibling_bounds.y
		new_min_size.x = max_sibling_bounds.y * ratio

	# Apply the final calculated minimum size.
	custom_minimum_size = new_min_size
