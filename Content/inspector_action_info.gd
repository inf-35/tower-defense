extends Resource
class_name InspectorAction

enum ActionType {
	UPGRADE, ## for towers
	SELL, ## selling towers / clearing structures
	ACTIVATE_ABILITY, ## towers which have custom abilities
	CUSTOM            ## unique script logic
}

@export var type: ActionType = ActionType.UPGRADE
@export var label: String = "Upgrade"
@export var icon: Texture2D
@export var tooltip: String = ""


@export var upgrade_index: int = 0 ## for UPGRADE type: which index in the upgrades_into array to use? (default 0)
@export var custom_signal_key: StringName = &"" ## for CUSTOM type: a string key that the tower/inspector can listen for
