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

func belt_path(start: Vector2i, finish: Vector2i, end_rotation: int = -1) -> Array[Dictionary]:
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
	if not path.is_empty() and end_rotation >= 0:
		path[path.size() - 1]["rotation"] = posmod(end_rotation, 4)
	return path

func belt_path_to_belt(start: Vector2i, target_cell: Vector2i, target_rotation: int) -> Array[Dictionary]:
	var forward: Vector2i = _forward(target_rotation)
	var left: Vector2i = _forward(target_rotation + 3)
	var right: Vector2i = _forward(target_rotation + 1)
	var candidates: Array[Vector2i] = [target_cell + left, target_cell + right, target_cell - forward]
	var best_path: Array[Dictionary] = []
	for candidate: Vector2i in candidates:
		var candidate_path: Array[Dictionary] = belt_path(start, candidate)
		var crosses_target: bool = false
		for point: Dictionary in candidate_path:
			if point["cell"] == target_cell:
				crosses_target = true
				break
		if crosses_target or (not best_path.is_empty() and candidate_path.size() >= best_path.size()):
			continue
		var direction: Vector2i = target_cell - candidate
		candidate_path[candidate_path.size() - 1]["rotation"] = _rotation_for(direction)
		best_path = candidate_path
	return best_path

func place_path(sim: FactorySim, path: Array[Dictionary], kind: String) -> bool:
	for point: Dictionary in path:
		if not sim.can_place(kind, point["cell"], int(point["rotation"])):
			return false
	for point: Dictionary in path:
		sim.add_entity(kind, point["cell"], int(point["rotation"]))
	return true

func _forward(direction_rotation: int) -> Vector2i:
	return [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)][posmod(direction_rotation, 4)]

func _rotation_for(direction: Vector2i) -> int:
	if direction == Vector2i(1, 0):
		return 1
	if direction == Vector2i(0, -1):
		return 2
	if direction == Vector2i(-1, 0):
		return 3
	return 0
