class_name TerrainBaseStat
extends Resource #defines stats for a terraintype

@export var color: Color ##default base color
@export var texture: Texture2D

@export var navigable: bool ##is this terrain navigable
@export var constructable: bool ##is this terrain constructable upon.
@export var modifiers: Array[ModifierDataPrototype] ##this array holds all the modifier prototypes this terrain grants to towers built on it
