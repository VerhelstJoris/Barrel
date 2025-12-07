class_name Player extends CharacterBody3D

@export_range(1.0, 10.0) var camera_sensitivity: float = 2.0

@export_range(0.0, 0.5) var camera_start_deadzone: float = .2

@export_range(0.0, 0.5) var camera_end_deadzone: float = .1

@export_group("Components")
@export var input_receiver : PlayerInputReceiver
@onready var camera_pivot: Node3D = %CameraPivot
@onready var player_cam: Camera3D = %SmoothCamera
@onready var movement_component : PlayerMovementComponent = %PlayerMovementComponent
@onready var equipment_manager : EquipmentManager = %EquipmentManager

@onready var arms: FPArms = %FP_Arms

var mouse_motion: Vector2

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_animation_data()
	
func _setup_animation_data() -> void:
	arms.arms_animation_bus._init_player_data(self)
	
func _on_mouse_motion_input(event : InputEvent) -> void:
	mouse_motion = -event.relative * 0.001
	
func _process(_delta: float):
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Handling camera in '_process' so that camera movement is framerate independent
		_handle_camera_motion()

	arms._align_to_world_camera(player_cam)
	
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
	rotate_y(-deg_to_rad(camera_sensitivity * normalized_resulting_vector.x * action_strength))
	camera_pivot.rotate_x(-deg_to_rad(camera_sensitivity * normalized_resulting_vector.y * action_strength))

	camera_pivot.rotation_degrees.x = clampf(
		camera_pivot.rotation_degrees.x, -89.0, 89.0
	)
	
