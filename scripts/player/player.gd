extends CharacterBody3D
class_name FactoryPlayer

const WALK_SPEED: float = 7.0
const SPRINT_SPEED: float = 11.5
const JUMP_VELOCITY: float = 5.8
const MOUSE_SENSITIVITY: float = 0.0022

var inventory: Dictionary = {
	"iron_plate": 100, "iron_rod": 50, "wire": 80,
	"concrete": 40, "iron_ingot": 20
}
var camera: Camera3D
var pitch: float = 0.0
var mouse_captured: bool = true
var panel_open: bool = false

func _ready() -> void:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)
	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.fov = 78.0
	add_child(camera)
	camera.make_current()
	_set_mouse_capture(true)

func _physics_process(delta: float) -> void:
	if panel_open:
		velocity = Vector3.ZERO
		return
	var movement: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed: float = SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var direction: Vector3 = (transform.basis * Vector3(movement.x, 0.0, movement.y)).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, -1.48, 1.48)
		camera.rotation.x = pitch
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not mouse_captured:
		_set_mouse_capture(true)

func set_panel_open(is_open: bool) -> void:
	panel_open = is_open
	_set_mouse_capture(not is_open)

func _set_mouse_capture(captured: bool) -> void:
	mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

static func configure_input() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("sprint", KEY_SHIFT)
	_add_key_action("jump", KEY_SPACE)

static func _add_key_action(action_name: String, key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = key
	InputMap.action_add_event(action_name, key_event)
