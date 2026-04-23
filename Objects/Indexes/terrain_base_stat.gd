class_name TerrainBaseStat
extends Resource #defines stats for a terraintype

@export var color: Color ##default base color
@export var wash_color: Color = Color(1.0, 1.0, 1.0, 0.25) ##pale edge color used by the watercolor falloff
@export_range(0.0, 1.0, 0.01) var dominance_strength: float = 0.0 ##how strongly this terrain claims watercolor color ownership
@export var texture: Texture2D

@export var navigable: bool ##is this terrain navigable
@export var constructable: bool ##is this terrain constructable upon.
@export var modifiers: Array[ModifierDataPrototype] ##this array holds all the modifier prototypes this terrain grants to towers built on it
