extends RefCounted
class_name TutorialContent

enum Fact {
	CAMERA_PANNED,
	CAMERA_ZOOMED,
	TOWER_BAR_SELECTED,
	TURRET_PLACED,
	PLAYER_STATS_HOVERED,
	WAVE_TIMELINE_HOVERED,
	FARM_PLACED = 7,
	TRADE_OPENED = 8,
}

enum Element {
	TOWER_BAR,
	PLAYER_STATS,
	WAVE_TIMELINE,
	START_WAVE_BUTTON,
	TRADE_BUTTON,
	TRADE_MENU,
}

enum Anchor {
	CENTRAL,
	TOWER_BAR,
	PLAYER_STATS,
	TIMELINE,
	START_WAVE,
	TRADE,
	TARGET_OFFSET,
}

class ChecklistItem extends RefCounted:
	var fact: int
	var text: String

	func _init(fact_id: int = Fact.CAMERA_PANNED, item_text: String = "") -> void:
		fact = fact_id
		text = item_text

class Chapter extends RefCounted:
	var id: StringName = StringName()
	var anchor: int = Anchor.CENTRAL
	var checklist_items: Array[ChecklistItem] = []
	var paragraph_text: String = ""
	var footer_text: String = ""
	var hover_targets: Dictionary[int, int] = {}
	var highlight_elements: Array[int] = []
	var start_wave_locked: bool = true
	var auto_advance: bool = true
	var auto_advance_delay: float = 0.8
	var allow_manual_continue: bool = false
	var pause_clock: bool = false
	var target_offset: Vector2 = Vector2.ZERO

	func get_required_facts() -> Array[int]: ##returns the facts that must be complete before this chapter can advance
		var facts: Array[int] = []
		for item: ChecklistItem in checklist_items:
			facts.append(item.fact)
		return facts
