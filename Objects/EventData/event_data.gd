extends RefCounted
class_name EventData
#see child classes i.e. hit_data, etc.
var recursion: int = 0 #counter to prevent infinite recursion loops, stops at recursion_limit (see Effect.RECURSION_LIMIT)

func duplicate() -> EventData: ##deep duplicates to create an unrelated, unique eventdata
	# 1. create a new instance of the *actual* subclass (e.g., HitData, CellData).
	# get_script().new() is the canonical way to instantiate an object of the same class.
	var new_instance: EventData = get_script().new()
	
	# 2. get the list of all properties defined in the script.
	var properties: Array[Dictionary] = get_property_list() 
	# 3. iterate through the properties and copy them to the new instance.
	for prop_info: Dictionary in properties:
		# we only copy properties that are meant to be stored (i.e., data).
		# this correctly handles exported variables and ignores most transient state.
			
		var prop_name: StringName = prop_info.name
		var value: Variant = get(prop_name)
		# --- 4. intelligent deep copy logic ---
		
		if prop_name == &"target":
			# if it is an object, we MUST check if it's a valid, non-freed instance.
			# is_instance_valid() is the canonical way to do this.
			if not is_instance_valid(value):
				# the object has been freed. set the property on the new instance to null
				# to represent the broken reference, and skip to the next property.
				new_instance.set(prop_name, null)
				continue

		if value == null:
			continue
		# if the value is another duplicatable object, call its duplicate method recursively.
		if value is EventData:
			new_instance.set(prop_name, value.duplicate())
		# if it's a dictionary or array, use their built-in deep duplicate.
		elif value is Dictionary or value is Array:
			new_instance.set(prop_name, value.duplicate(true))
		# for all other types (primitives, resources, other objects), copy the value/reference directly.
		else:
			new_instance.set(prop_name, value)
			
	return new_instance
