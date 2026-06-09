extends RefCounted
class_name EventLineage

const DEFAULT_CAPACITY: int = 10

var _capacity: int = DEFAULT_CAPACITY
var _agent_keys: Array[int] = []
var _agent_labels: Dictionary[int, String] = {}

func duplicate() -> EventLineage:
	var lineage := EventLineage.new()
	lineage._capacity = _capacity

	for agent_key: int in _agent_keys:
		lineage._agent_keys.append(agent_key)

	for agent_key: int in _agent_labels:
		lineage._agent_labels[agent_key] = _agent_labels[agent_key]

	return lineage

func has_producer(producer: Object) -> bool:
	var producer_key: int = get_producer_key(producer)
	if producer_key <= 0:
		return false

	return _agent_keys.has(producer_key)

func push_producer(producer: Object) -> void:
	var producer_key: int = get_producer_key(producer)
	if producer_key <= 0 or _agent_keys.has(producer_key):
		return

	_agent_keys.append(producer_key)
	_agent_labels[producer_key] = get_producer_label(producer)

	while _agent_keys.size() > _capacity:
		var removed_key: int = _agent_keys[0]
		_agent_keys.remove_at(0)
		_agent_labels.erase(removed_key)

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
