extends EventData
class_name AdjacencyReportData #stores information about a tower's updated adjacencies

var pivot: Tower
var adjacent_towers: Dictionary[Vector2i, Tower] = {}
#towers are stored with their relative offsets about the pivot tower
