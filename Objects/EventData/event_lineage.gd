extends RefCounted
class_name EventLineage

const DEFAULT_CAPACITY: int = 10

var _capacity: int = DEFAULT_CAPACITY
var _agent_keys: Array[int] = []
var _agent_labels: Array[String] = []

func duplicate() -> EventLineage: ##returns an independent lineage copy with producer order and repeat counts preserved
	var lineage := EventLineage.new()
	lineage._capacity = _capacity
	lineage._agent_keys = _agent_keys.duplicate()
	lineage._agent_labels = _agent_labels.duplicate()

	return lineage

func has_producer(producer: Object) -> bool: ##returns whether a runtime producer appears at least once in this lineage
	return count_producer(producer) > 0

func count_producer(producer: Object) -> int: ##counts how many times a runtime producer appears in this lineage
	var producer_key: int = get_producer_key(producer)
	if producer_key <= 0:
		return 0

	var count: int = 0
	for agent_key: int in _agent_keys:
		if agent_key == producer_key:
			count += 1
	return count

func has_producer_label(label: StringName) -> bool: ##returns whether a producer family label appears at least once in this lineage
	return count_producer_label(label) > 0

func count_producer_label(label: StringName) -> int: ##counts how many times a producer family label appears in this lineage
	if String(label).is_empty():
		return 0

	var count: int = 0
	for producer_label: String in _agent_labels:
		if producer_label == String(label):
			count += 1

	return count

func push_producer_label(label: StringName) -> void: ##records a producer family occurrence while preserving repeat counts
	var producer_label: String = String(label)
	if producer_label.is_empty():
		return

	var producer_key: int = -absi(producer_label.hash())
	if producer_key == 0:
		producer_key = -1
	_push_producer_entry(producer_key, producer_label)

func push_producer(producer: Object) -> void: ##records a runtime producer occurrence while preserving repeat counts
	var producer_key: int = get_producer_key(producer)
	if producer_key <= 0:
		return

	_push_producer_entry(producer_key, get_producer_label(producer))

func _push_producer_entry(producer_key: int, producer_label: String) -> void: ##stores one lineage occurrence and trims old entries when the bounded history is full
	_agent_keys.append(producer_key)
	_agent_labels.append(producer_label)
	while _agent_keys.size() > _capacity:
		_agent_keys.remove_at(0)
		_agent_labels.remove_at(0)

static func get_producer_key(producer: Object) -> int:
	if not is_instance_valid(producer):
		return 0

	return producer.get_instance_id()

static func get_producer_label(producer: Object) -> String:
	if not is_instance_valid(producer):
		return ""

	var script: Script = producer.get_script() as Script
	if is_instance_valid(script) and not script.resource_path.is_empty():
		return script.resource_path.get_file().get_basename()

	return producer.get_class()
