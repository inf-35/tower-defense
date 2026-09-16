extends EventData
class_name AdjacencyReportData #stores information about a tower's updated adjacencies

var pivot: Tower
var cells: Dictionary[Vector2i, Vector2i] = {}
var adjacent_towers: Dictionary[Vector2i, Tower] = {}
var unique_towers: Array[Tower] = []
#cells and towers are stored by relative offset about the pivot tower
