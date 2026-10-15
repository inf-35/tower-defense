extends Resource
class_name GuildData
@export var title: String = "" ##guild name shown during run creation
@export_multiline var description: String = "" ##describes the starting package
@export var starting_buildings: Array[Towers.Type] = [] ##complete starting building unlocks
@export var starting_relics: Array[RelicData] = [] ##specific relics granted once at startup
