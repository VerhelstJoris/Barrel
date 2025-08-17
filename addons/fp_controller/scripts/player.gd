class_name Player
extends CharacterBody3D


signal on_holster_started()
signal on_holster_finish()
signal on_unholster_started()
signal on_unholster_finished()
enum Holster_State {Hidden , Unholstering, Ready, Holstering}


@export_group("Controls map names")
@export var JUMP: String = "jump"
@export var SPRINT: String = "sprint"
@export var holster : String = "holster"
@export_group("Customizable player stats")


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
@export var input_receiver : InputReceiver
@onready var sub_viewport: SubViewport = %SubViewport
@onready var camera_pivot: Node3D = %CameraPivot
@onready var smooth_camera: Camera3D = %SmoothCamera
@onready var movement_component : PlayerMovementComponent = %PlayerMovementComponent

@onready var arms: FPArms = %FP_Arms

@onready var HUD_equipment_input : HUDEquipmentInput = %HUDEquipment

signal on_holster_input_received(event : InputEvent)
signal on_quick_unholster_input_received(event : InputEvent)

signal on_equipped(new_equipment : PlayerEquipment)
signal on_unequipped(old_equipment : PlayerEquipment)

var equipment_holster_state : Holster_State = Holster_State.Hidden:
	set = _change_holster_state

var current_equipment : PlayerEquipment = null:
	set = _change_equipment

# Dynamic values used for calculation
var input_direction: Vector2
var ledge_position: Vector3 = Vector3.ZERO
var mouse_motion: Vector2

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sub_viewport.size = DisplayServer.window_get_size()
	current_equipment = arms.pistol_equipment
	_setup_input_signals()
	_setup_animation_data()
	_change_holster_state(Holster_State.Hidden)

	
func _setup_animation_data() -> void:
	arms.arms_animation_bus._init_player_data(self)
	arms.arms_animation_bus.on_holster_anim_finish.connect(_on_holster_anim_finish)
	arms.arms_animation_bus.on_unholster_anim_finish.connect(_on_unholster_anim_finish)

func _setup_input_signals() -> void:
	on_holster_input_received.connect(_on_holster_input)
	on_quick_unholster_input_received.connect(_on_quick_unholster_input)
	
func _on_mouse_motion_input(event : InputEvent) -> void:
	mouse_motion = -event.relative * 0.001
	
func _process(_delta: float):
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Handling camera in '_process' so that camera movement is framerate independent
		_handle_camera_motion()

	arms._align_to_world_camera(smooth_camera)
	
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
	
func _change_equipment(new_equipment : PlayerEquipment) -> void:
	if(new_equipment == current_equipment):
		return
		
	_on_unequip(current_equipment)

	current_equipment = new_equipment
	
	_on_equip(current_equipment)
	
func _on_unequip(old_equipment : PlayerEquipment) -> void:
	if(old_equipment != null):
		old_equipment.input_receiver.on_available_equipment_actions_changed.disconnect(HUD_equipment_input._on_equipment_input_actions_changed)
		old_equipment.input_receiver.on_available_equipment_actions_cleared.disconnect(HUD_equipment_input._clear_current_input_details)
	on_unequipped.emit(old_equipment)	
	
func _on_equip(new_equipment : PlayerEquipment) -> void:
	if(new_equipment != null):
		new_equipment.input_receiver.on_available_equipment_actions_changed.connect(HUD_equipment_input._on_equipment_input_actions_changed)
		new_equipment.input_receiver.on_available_equipment_actions_cleared.connect(HUD_equipment_input._clear_current_input_details)
		new_equipment._on_equipped()
	on_equipped.emit(new_equipment)

func _on_quick_unholster_input(event : InputEvent) -> void:
	if(equipment_holster_state == Holster_State.Hidden):
		_change_holster_state(Holster_State.Unholstering)

func _on_holster_input(event : InputEvent) -> void:
	match equipment_holster_state:
		Holster_State.Hidden:
			_change_holster_state(Holster_State.Unholstering)
		Holster_State.Ready:
			if(_can_holster_equipment()):
				_change_holster_state(Holster_State.Holstering)
		_:
			pass

func _can_holster_equipment() -> bool:
	return equipment_holster_state == Holster_State.Ready && current_equipment._can_be_holstered()			
			
func _change_holster_state(new_state : Holster_State) -> void:
	if(current_equipment == null):
		return
	
	equipment_holster_state = new_state	
	match new_state:
		Holster_State.Holstering:
			on_holster_started.emit()
			current_equipment._on_start_holster()
		Holster_State.Unholstering:
			on_unholster_started.emit()
			current_equipment._on_start_unholster()
		Holster_State.Hidden:
			current_equipment.visible = false
		_:
			pass
			
func _on_holster_anim_finish() -> void:
	equipment_holster_state = Holster_State.Hidden
		
func _on_unholster_anim_finish() -> void:
	equipment_holster_state = Holster_State.Ready

func _can_use_equipment() -> bool:
	return equipment_holster_state == Holster_State.Ready
	