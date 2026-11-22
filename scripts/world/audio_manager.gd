extends Node3D
class_name FactoryAudioManager

const MAX_PLAYERS: int = 24
const MACHINE_SOUNDS: Dictionary = {
	"miner_mk1": "miner_drill_rumble",
	"smelter": "smelter_roar",
	"constructor": "constructor_press",
	"assembler": "assembler_servo",
	"geo_tap": "geo_tap_steam",
}

var sim: FactorySim
var listener: Node3D
var players: Array[AudioStreamPlayer3D] = []
var owners: Array[int] = []
var sound_names: Array[String] = []
var distances: Array[float] = []
var loop_streams: Dictionary = {}
var one_shots: Dictionary = {}

func setup(factory_sim: FactorySim, audio_listener: Node3D) -> void:
	sim = factory_sim
	listener = audio_listener

func _ready() -> void:
	_configure_buses()
	for index: int in range(MAX_PLAYERS):
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.name = "AudioPlayer_%02d" % index
		player.bus = "SFX"
		player.unit_size = 6.0
		player.max_distance = 40.0
		add_child(player)
		players.append(player)
		owners.append(-1)
		sound_names.append("")
		distances.append(0.0)
	for filename: String in [
			"miner_drill_rumble", "smelter_roar", "constructor_press",
			"assembler_servo", "geo_tap_steam", "belt_rattle"]:
		var loaded: AudioStreamWAV = load("res://assets/audio/%s.wav" % filename) as AudioStreamWAV
		if loaded == null:
			continue
		var looped: AudioStreamWAV = loaded.duplicate() as AudioStreamWAV
		looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looped.loop_begin = 0
		looped.loop_end = int(looped.data.size() / 2)
		loop_streams[filename] = looped
	for filename: String in [
			"placement_confirm", "invalid_placement", "dismantle",
			"pick_hit", "ui_click"]:
		var loaded: AudioStreamWAV = load("res://assets/audio/%s.wav" % filename) as AudioStreamWAV
		if loaded != null:
			one_shots[filename] = loaded

func _process(_delta: float) -> void:
	if sim == null:
		return
	_sync_machine_loops()

func play_one_shot(name: String, world_position: Vector3) -> void:
	if not one_shots.has(name):
		return
	var index: int = -1
	for candidate: int in range(players.size()):
		if owners[candidate] < 0 and not players[candidate].playing:
			index = candidate
			break
	if index < 0:
		for candidate: int in range(players.size()):
			if owners[candidate] < 0:
				continue
			if index < 0 or distances[candidate] > distances[index]:
				index = candidate
	if index < 0:
		return
	players[index].stop()
	owners[index] = -1
	sound_names[index] = ""
	players[index].stream = one_shots[name]
	players[index].global_position = world_position
	players[index].volume_db = -5.0
	players[index].play()

func _sync_machine_loops() -> void:
	var candidates: Array[Dictionary] = []
	for entity: FactoryEntity in sim.entities.values():
		var sound_name: String = ""
		var productivity: float = 0.0
		if entity.kind.begins_with("belt_") and not entity.belt_items.is_empty():
			sound_name = "belt_rattle"
			productivity = 0.65
		elif MACHINE_SOUNDS.has(entity.kind):
			var state: Dictionary = sim.visual_state(entity.id)
			sound_name = str(MACHINE_SOUNDS[entity.kind])
			productivity = float(state.get("productivity", 0.0))
		if sound_name.is_empty() or productivity <= 0.02 or not loop_streams.has(sound_name):
			continue
		var distance: float = listener.global_position.distance_to(entity.position) if listener != null else 0.0
		if distance > 40.0:
			continue
		candidates.append({
			"id": entity.id,
			"kind": sound_name,
			"position": entity.position,
			"productivity": productivity,
			"distance": distance
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"])
	)
	if candidates.size() > MAX_PLAYERS:
		candidates.resize(MAX_PLAYERS)
	var desired: Dictionary = {}
	for candidate: Dictionary in candidates:
		desired[int(candidate["id"])] = true
	for index: int in range(players.size()):
		if owners[index] >= 0 and not desired.has(owners[index]):
			players[index].stop()
			owners[index] = -1
			sound_names[index] = ""
	for candidate: Dictionary in candidates:
		var entity_id: int = int(candidate["id"])
		var index: int = owners.find(entity_id)
		if index < 0:
			for free_index: int in range(players.size()):
				if owners[free_index] < 0 and not players[free_index].playing:
					index = free_index
					break
		if index < 0:
			continue
		var sound_name: String = str(candidate["kind"])
		if owners[index] != entity_id or sound_names[index] != sound_name:
			players[index].stop()
			players[index].stream = loop_streams[sound_name]
			owners[index] = entity_id
			sound_names[index] = sound_name
		players[index].global_position = candidate["position"]
		players[index].volume_db = linear_to_db(clampf(float(candidate["productivity"]), 0.0, 1.0))
		distances[index] = float(candidate["distance"])
		if not players[index].playing:
			players[index].play()

func _configure_buses() -> void:
	var master_index: int = AudioServer.get_bus_index("Master")
	if master_index >= 0:
		AudioServer.set_bus_volume_db(master_index,
			linear_to_db(clampf(float(ProjectSettings.get_setting("factory/audio/master_volume", 1.0)), 0.0, 1.0)))
	var sfx_index: int = AudioServer.get_bus_index("SFX")
	if sfx_index < 0:
		AudioServer.add_bus()
		sfx_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(sfx_index, "SFX")
		AudioServer.set_bus_send(sfx_index, "Master")
	AudioServer.set_bus_volume_db(sfx_index,
		linear_to_db(clampf(float(ProjectSettings.get_setting("factory/audio/sfx_volume", 1.0)), 0.0, 1.0)))
