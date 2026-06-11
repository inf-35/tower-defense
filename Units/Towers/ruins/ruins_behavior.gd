extends Behavior
class_name RuinsBehavior

const SEARCH_ACTION_KEY: StringName = &"search"

@export var _ruins_data: RuinsData ##authored reward-state packet for this ruins instance

var _is_claiming: bool = false

func start() -> void: ##environmental ruins are inert until the player interacts with them through the inspector
	pass

func on_inspector_action(action_key: StringName) -> void: ##dispatches inspector-side custom actions authored on the ruins tower data
	if action_key != SEARCH_ACTION_KEY:
		return
	if _is_claiming:
		return
	if not is_instance_valid(_ruins_data):
		return
	if not is_instance_valid(_ruins_data.reward_choices):
		return

	_is_claiming = true
	var presented: bool = RewardService.generate_and_present_configured_choices(_ruins_data.reward_choices)
	if not presented:
		_is_claiming = false
		return

	RewardService.reward_process_complete.connect(_on_reward_claimed, CONNECT_ONE_SHOT)

func _on_reward_claimed() -> void:
	_is_claiming = false
	if not is_instance_valid(unit):
		return
	if not is_instance_valid(_ruins_data):
		return
	if not _ruins_data.consume_on_claim:
		return

	unit.died.emit(HitReportData.blank_hit_report)
	unit.queue_free()
