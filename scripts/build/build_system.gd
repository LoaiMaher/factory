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

func belt_path(start: Vector2i, finish: Vector2i) -> Array[Dictionary]:
	var cells: Array[Vector2i] = [start]
	var delta: Vector2i = finish - start
	var first_axis_x: bool = absi(delta.x) >= absi(delta.y)
	var axes: Array[bool] = [first_axis_x, not first_axis_x]
	var current: Vector2i = start
	for use_x: bool in axes:
		var amount: int = delta.x if use_x else delta.y
		var step: Vector2i = Vector2i(signi(amount), 0) if use_x else Vector2i(0, signi(amount))
		for _index: int in range(absi(amount)):
			current += step
			cells.append(current)
	var path: Array[Dictionary] = []
	for index: int in range(cells.size()):
		var direction: Vector2i = cells[index + 1] - cells[index] if index + 1 < cells.size() else cells[index] - cells[index - 1] if index > 0 else Vector2i(0, 1)
		var facing: int = 0
		if direction == Vector2i(1, 0): facing = 1
		elif direction == Vector2i(0, -1): facing = 2
		elif direction == Vector2i(-1, 0): facing = 3
		path.append({"cell": cells[index], "rotation": facing})
	return path

func place_path(sim: FactorySim, path: Array[Dictionary], kind: String) -> bool:
	for point: Dictionary in path:
		if not sim.can_place(kind, point["cell"], int(point["rotation"])):
			return false
	for point: Dictionary in path:
		sim.add_entity(kind, point["cell"], int(point["rotation"]))
	return true
