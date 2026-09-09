extends Resource
class_name BossEncounterData

@export var title: String = "" ##name shown by the boss healthbar
@export var boss_type: Units.Type = Units.Type.BASIC ##persistent boss unit spawned for this encounter
@export var subwaves: Array[BossSubwaveData] = [] ##ordered subwaves; the final entry repeats if the boss survives
@export var logic_script: Script ##optional bespoke boss logic object extending BossEncounterLogic

func get_subwave(subwave_index: int) -> BossSubwaveData: ##returns the indexed subwave, repeating the final authored entry for long encounters
	if subwaves.is_empty():
		return null
	var clamped_index: int = clampi(subwave_index, 0, subwaves.size() - 1)
	return subwaves[clamped_index]

func create_logic() -> BossEncounterLogic: ##instantiates the bespoke logic object or falls back to inert base behavior
	if logic_script == null:
		return BossEncounterLogic.new()

	var logic_object: Object = logic_script.new()
	if logic_object is BossEncounterLogic:
		return logic_object as BossEncounterLogic

	push_warning("BossEncounterData: logic_script does not extend BossEncounterLogic.")
	return BossEncounterLogic.new()
