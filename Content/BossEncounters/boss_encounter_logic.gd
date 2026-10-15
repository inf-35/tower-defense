extends RefCounted
class_name BossEncounterLogic

func initialise(_context: BossEncounterContext) -> void: ##receives the runtime context before the first encounter hook
	pass

func on_encounter_started(_context: BossEncounterContext) -> void: ##called after the persistent boss has been spawned
	pass

func on_subwave_started(_context: BossEncounterContext) -> void: ##called each time combat resumes for a boss subwave
	pass

func update_subwave(_context: BossEncounterContext, _delta: float) -> void: ##called while a boss subwave is active
	pass

func on_subwave_cleared(_context: BossEncounterContext) -> void: ##called when minion/time conditions send the boss into prep
	pass

func on_boss_frozen_for_prep(_context: BossEncounterContext) -> void: ##called after the boss has been disabled for prep
	pass

func on_boss_resumed_for_combat(_context: BossEncounterContext) -> void: ##called after the boss has been re-enabled for combat
	pass

func on_boss_died(_context: BossEncounterContext) -> void: ##called when the persistent boss dies and the encounter ends
	pass

func get_preview_enemy_stacks(_subwave_index: int) -> Array[Array]: ##returns encounter-owned enemies for existing wave and breach previews
	return []

func get_save_data() -> Dictionary: ##returns bespoke runtime state that should persist through boss prep saves
	return {}

func load_save_data(_data: Dictionary) -> void: ##restores bespoke runtime state saved during boss prep
	pass
