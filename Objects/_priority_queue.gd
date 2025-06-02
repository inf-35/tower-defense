class_name PriorityQueue

var heap: Array[Array] = [] #input/output final heap array
#heap[n][0] is the priority 
#heap[n][1] is the value/reference
func parent(i: int) -> int:
	return (i - 1) >> 1 #divide by two; "shift down an octave"
func left_child(i: int) -> int:
	return (2 * i) + 1 
func right_child(i: int) -> int:
	return (2 * i) + 2
	
func shift_up(i: int, array: Array = heap) -> void: #bubble from leaf to root
	while array[parent(i)][0] > array[i][0] and i > 0:
		var swap: Array = array[parent(i)] #if child < parent, swap.
		array[parent(i)] = array[i]
		array[i] = swap
		
		i = parent(i)

func shift_down(i: int, array: Array = heap) -> void: #sink from root to leaf
	while true:
		var smallest_index: int = i #find whether parent, lchild or rchild is the smallest.
		if array.size() > left_child(i) and array[left_child(i)][0] < array[smallest_index][0]:
			smallest_index = left_child(i)
		if array.size() > right_child(i) and array[right_child(i)][0] < array[smallest_index][0]:
			smallest_index = right_child(i)
			
		if smallest_index == i: #if parent is the smallest finish
			break
			
		var swap: Array = array[smallest_index] #if child < parent, swap.
		array[smallest_index] = array[i]
		array[i] = swap
		
		i = smallest_index

func insert(p: Array, array: Array = heap) -> void:
	array.append(p) #add value as leaf
	shift_up(array.size() - 1) #bubble leaf upwards

func insert_array(value_array: Array[Array], array: Array = heap) -> void:
	for p: Array in value_array:
		insert(p, array)

func pop(array: Array = heap) -> void: #doesnt actually return value, retrieve beforehand
	if array.is_empty():
		return

	var result = array[0] #get minimum value
	
	array[0] = array[array.size() - 1] #set root to leaf (quite large)
	array.remove_at(array.size() - 1)
	shift_down(0) #bubble down new root

func get_min(array: Array = heap) -> Variant: return heap[0] #get root

func leaf() -> int: return size() - 1

func size() -> int: return heap.size()

func is_empty() -> bool: return size() == 0

func _init(value_array: Array[Array] = []) -> void:
	insert_array(value_array)
