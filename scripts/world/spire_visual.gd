extends Node3D
class_name SpireVisual

var current_stage: int = -1
var keel: MeshInstance3D
var hull_frame: MeshInstance3D

func _ready() -> void:
	keel = MeshInstance3D.new()
	var keel_mesh: BoxMesh = BoxMesh.new()
	keel_mesh.size = Vector3(4.0, 0.45, 0.8)
	keel.mesh = keel_mesh
	keel.position = Vector3(5.0, 4.0, 5.0)
	keel.material_override = _material(Color("b8c3bd"))
	keel.visible = false
	add_child(keel)
	hull_frame = MeshInstance3D.new()
	var frame_mesh: BoxMesh = BoxMesh.new()
	frame_mesh.size = Vector3(7.0, 0.45, 0.75)
	hull_frame.mesh = frame_mesh
	hull_frame.position = Vector3(5.0, 3.0, 5.0)
	hull_frame.material_override = _material(Color("9cbbc0"))
	hull_frame.visible = false
	add_child(hull_frame)

func set_stage(stage: int) -> void:
	if stage == current_stage:
		return
	current_stage = stage
	if stage >= 1 and not keel.visible:
		keel.visible = true
		var keel_tween: Tween = create_tween()
		keel_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		keel_tween.tween_property(keel, "position:y", 8.0, 8.0)
	if stage >= 2 and not hull_frame.visible:
		hull_frame.visible = true
		var frame_tween: Tween = create_tween()
		frame_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		frame_tween.tween_property(hull_frame, "position:y", 8.0, 8.0)

func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.42
	material.roughness = 0.55
	return material
