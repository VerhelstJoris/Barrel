class_name PlayerWorldCamera extends Camera3D

@export_range(1.0, 10.0) var camera_sensitivity: float = 2.0

@export_range(0.0, 0.5) var camera_start_deadzone: float = .2

@export_range(0.0, 0.5) var camera_end_deadzone: float = .1

@export var speed := 44.0

@onready var camera_pivot: Node3D = %CameraPivot

var player: Player

var mouse_motion : Vector2

func _ready() -> void:
	await owner.ready
	player = owner as Player

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if(get_compositor() && get_compositor().compositor_effects.size() > 0):
		get_compositor().compositor_effects[0].effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT


func _process(delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Handling camera in '_process' so that camera movement is framerate independent
		_handle_camera_motion()

	player.arms._align_to_world_camera(self)


func _physics_process(delta: float) -> void:
	var weight: float = clamp(speed * delta, 0.0, 1.0)
	
	global_transform = global_transform.interpolate_with(
		get_parent().global_transform, weight
	)
	
	global_position = get_parent().global_position

func _handle_camera_motion() -> void:
	player.rotate_y(mouse_motion.x * camera_sensitivity)
	camera_pivot.rotate_x(mouse_motion.y  * camera_sensitivity)

	camera_pivot.rotation_degrees.x = clampf(
		camera_pivot.rotation_degrees.x, -85.0, 85.0
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

func _on_mouse_motion_input(event : InputEvent) -> void:
	mouse_motion = -event.relative * 0.001
	

