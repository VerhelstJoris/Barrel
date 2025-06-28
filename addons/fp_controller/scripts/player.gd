class_name Player
extends CharacterBody3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
signal player_movement_input(direction)

@export_group("Controls map names")
@export var MOVE_FORWARD: String = "move_forward"
@export var MOVE_BACK: String = "move_back"
@export var MOVE_LEFT: String = "move_left"
@export var MOVE_RIGHT: String = "move_right"
@export var JUMP: String = "jump"
@export var SPRINT: String = "sprint"
@export var holster : String = "holster"
@export_group("Customizable player stats")
@export var walk_back_speed: float = 1.5
@export var walk_speed: float = 2.5

#Is Sprint a hold or toggle input?
@export var sprint_toggle: bool = true
@export var sprint_speed: float = 5.0
@export var jump_height: float = 1.0
@export var acceleration: float = 10.0

@export_range(1.0, 10.0) var camera_sensitivity: float = 2.0

@export_range(0.0, 0.5) var camera_start_deadzone: float = .2

@export_range(0.0, 0.5) var camera_end_deadzone: float = .1
@export_group("Feature toggles")
@export var allow_sprint: bool = true

@export_group("Components")
@export var input_receiver : InputReceiver = %InputReceiverComponent
@onready var sub_viewport: SubViewport = %SubViewport
@onready var camera_pivot: Node3D = %CameraPivot
@onready var state_machine: PlayerStateMachine = %StateMachine
@onready var arms: FPArms = %FP_Arms

@onready var HUD_equipment_input : HUDEquipmentInput = %HUDEquipment

signal on_holster_changed(holstered : bool)
signal on_movement_input_received(event: InputEvent)

signal on_equipped(new_equipment : PlayerEquipment)
signal on_unequipped(old_equipment : PlayerEquipment)

var equipment_holstered : bool  = true:
	set = _holster

var current_equipment : PlayerEquipment = null:
	set = _change_equipment

# Dynamic values used for calculation
var input_direction: Vector2
var ledge_position: Vector3 = Vector3.ZERO
var mouse_motion: Vector2
# Player state values that are set by applying state
var is_affected_by_gravity: bool = true
var is_moving: bool = false
var can_jump: bool   = true
var can_sprint: bool = true

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sub_viewport.size = DisplayServer.window_get_size()
	player_movement_input.connect(arms.arms_animation_bus._on_player_movement_input)
	on_holster_changed.connect(arms.arms_animation_bus._on_holster_state_changed)
	current_equipment = arms.pistol_equipment
	on_movement_input_received.connect(_on_movement_input)
		
func _on_movement_input(event : InputEvent) -> void:	
	if Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_BACK, MOVE_FORWARD):
		input_direction = Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_BACK, MOVE_FORWARD)
	else:
		input_direction = Vector2.ZERO
	
	player_movement_input.emit(input_direction)

func _on_mouse_motion_input(event : InputEvent) -> void:
	mouse_motion = -event.relative * 0.001


func _physics_process(delta: float) -> void:

	# Add the gravity.
	if not is_on_floor() && is_affected_by_gravity:
		velocity.y -= gravity * delta

	move_and_slide()
	
func _process(_delta: float):
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Handling camera in '_process' so that camera movement is framerate independent
		_handle_camera_motion()
		
func _handle_camera_motion() -> void:
	rotate_y(mouse_motion.x * camera_sensitivity)
	camera_pivot.rotate_x(mouse_motion.y  * camera_sensitivity)

	camera_pivot.rotation_degrees.x = clampf(
		camera_pivot.rotation_degrees.x, -89.0, 89.0
	)

	mouse_motion = Vector2.ZERO
	
func _handle_joy_camera_motion() -> void:
	var x_axis : float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var y_axis : float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)

	if abs(x_axis) < camera_start_deadzone:
		x_axis = 0
	if abs(x_axis) > 1 - camera_end_deadzone:
		if x_axis < 0:
			x_axis = camera_end_deadzone - 1
		else:
			x_axis = 1 - camera_end_deadzone


	if abs(y_axis) < camera_start_deadzone:
		y_axis = 0
	if abs(y_axis) > 1 - camera_end_deadzone:
		if y_axis < 0:
			y_axis = camera_end_deadzone - 1
		else:
			y_axis = 1 - camera_end_deadzone

	var resulting_vector: Vector2 = Vector2(x_axis, y_axis)
	var normalized_resulting_vector: Vector2 = resulting_vector.normalized()
	var action_strength: float = resulting_vector.length()
	print(camera_sensitivity)
	rotate_y(-deg_to_rad(camera_sensitivity * normalized_resulting_vector.x * action_strength))
	camera_pivot.rotate_x(-deg_to_rad(camera_sensitivity * normalized_resulting_vector.y * action_strength))

	camera_pivot.rotation_degrees.x = clampf(
		camera_pivot.rotation_degrees.x, -89.0, 89.0
	)

func _change_equipment(new_equipment : PlayerEquipment) -> void:
	if(new_equipment == current_equipment):
		return
		
	_on_unequip(current_equipment)

	current_equipment = new_equipment
	
	_on_equip(current_equipment)
	
func _on_unequip(old_equipment : PlayerEquipment) -> void:
	if(old_equipment != null):
		old_equipment.on_available_equipment_actions_changed.disconnect(HUD_equipment_input._on_equipment_input_actions_changed)
		old_equipment.on_available_equipment_actions_cleared.disconnect(HUD_equipment_input._on_equipment_input_actions_cleared)
	on_unequipped.emit(old_equipment)	
	
func _on_equip(new_equipment : PlayerEquipment) -> void:
	if(new_equipment != null):
		new_equipment.on_available_equipment_actions_changed.connect(HUD_equipment_input._on_equipment_input_actions_changed)
		new_equipment.on_available_equipment_actions_cleared.connect(HUD_equipment_input._on_equipment_input_actions_cleared)
		new_equipment._on_equipped()
	on_equipped.emit(new_equipment)

func _holster(new_value : bool) -> void:
	if(new_value == equipment_holstered):
		return

	equipment_holstered = new_value
	on_holster_changed.emit(equipment_holstered)
	
func _can_use_equipment() -> bool:
	return true
	