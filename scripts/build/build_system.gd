extends RefCounted
class_name FactoryBuildSystem

var selected: String = ""
var rotation: int = 0
var belt_start: Variant = null
var dismantle_mode: bool = false

func choose(building_id: String) -> void:
	selected = building_id
	belt_start = null

func rotate() -> void:
	rotation = (rotation + 1) % 4
