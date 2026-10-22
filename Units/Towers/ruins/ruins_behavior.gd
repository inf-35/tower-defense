extends Behavior
class_name RuinsBehavior

const SEARCH_ACTION_KEY: StringName = &"search"

@export var ruins_data: RuinsData ##scene-authored reward choices and consumption rule, shared by generated and loaded ruins

func start() -> void: ##environmental ruins are inert until the player interacts with them through the inspector
	pass

func on_inspector_action(action_key: StringName) -> void: ##dispatches inspector-side custom actions authored on the ruins tower data
	if action_key != SEARCH_ACTION_KEY:
		return
	if unit.abstractive or unit.disabled or RewardService.is_choosing_reward:
		return
	if not is_instance_valid(ruins_data) or not is_instance_valid(ruins_data.reward_choices):
		push_error("Ruins: the scene must provide valid reward choices.")
		return

	RewardService.reward_process_complete.connect(_on_reward_claimed, CONNECT_ONE_SHOT)
	if not RewardService.generate_and_present_configured_choices(ruins_data.reward_choices):
		RewardService.reward_process_complete.disconnect(_on_reward_claimed)
		push_warning("Ruins: no eligible rewards are available; leaving the ruins intact.")

func _on_reward_claimed() -> void: ##consumes the source only after its prompt completes, without persisting an interaction state
	if not is_instance_valid(unit) or unit.is_queued_for_deletion() or unit.disabled:
		return
	if not ruins_data.consume_on_claim:
		return

	unit.died.emit(HitReportData.blank_hit_report)
	unit.queue_free()
