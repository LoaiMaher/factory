extends RefCounted
class_name FactoryEntity

var id: int = -1
var kind: String = ""
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var recipe_id: String = ""
var input_buffer: Dictionary = {}
var output_buffer: Dictionary = {}
var belt_items: Array[Dictionary] = []
var rate_history: Dictionary = {}
var status: String = "Stopped"
var progress: float = 0.0
var extra: Dictionary = {}
var cost: Dictionary = {}
var satisfaction: float = 0.0
var last_delivery_time: Dictionary = {}
var splitter_cursor: int = 0
var merger_cursor: int = 0

func record(item_id: String, amount: float, sim_time: float) -> void:
	if not rate_history.has(item_id):
		rate_history[item_id] = []
	var events: Array = rate_history[item_id]
	events.append({"time": sim_time, "amount": amount})

func rate(item_id: String, sim_time: float) -> float:
	var events: Array = rate_history.get(item_id, [])
	var total: float = 0.0
	for event: Dictionary in events:
		if float(event["time"]) >= sim_time - 60.0:
			total += float(event["amount"])
	return total

func prune_rates(sim_time: float) -> void:
	for item_id: String in rate_history:
		var events: Array = rate_history[item_id]
		while not events.is_empty() and float(events[0]["time"]) < sim_time - 60.0:
			events.pop_front()
