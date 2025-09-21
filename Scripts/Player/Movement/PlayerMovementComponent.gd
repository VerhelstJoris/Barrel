@icon("res://DEBUG/Icons/Ico_Jump.png")
class_name PlayerMovementComponent extends Node

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_queued_velocity : Vector3 = Vector3.ZERO

signal on_movement_input_received(event: InputEvent)
signal on_sprint_input_received(event: InputEvent)
signal on_crouch_input_received(event : InputEvent)
signal on_jump_input_received(event : InputEvent)

signal on_player_movement_state_enter(new_state : PlayerStateMachine.E_StateName)
signal on_player_movement_state_leave(new_state : PlayerStateMachine.E_StateName)

@export_group("Movement Acceleration Settings")
@export var horizontal_velocity_acceleration : float = 6.0
var current_horizontal_velocity : Vector2 = Vector2.ZERO


@export_group("Gravity Settings")
@export var max_gravity_velocity : float = -18
@export var gravity_growth_curve : Curve
@export var time_reach_max_gravity_velocity : float = 1.5

var current_gravity_velocity : float = 0
var current_gravity_time : float = 0


const MOVE_FORWARD: String = "move_forward"
const MOVE_BACK: String = "move_back"
const MOVE_LEFT: String = "move_left"
const MOVE_RIGHT: String = "move_right"

@export_group("General Control Settings")
@export var movement_deadzone : Vector2 = Vector2(0.1,0.1)

var sprint_down : bool = false
var crouch_down : bool = false
var jump_down : bool = false
var input_direction: Vector2

@onready var state_machine: PlayerStateMachine = %BaseMovementStateMachine
var previous_state : PlayerState = null

var player: Player

signal on_player_movement(direction)
signal on_player_sprint_toggle(new_val)
signal on_player_crouch_toggle(new_val)
signal on_player_jump_toggle(new_val)

func _ready() -> void:
	await owner.ready
	player = owner as Player
	_connect_input_events()
	
func _connect_input_events():
	on_movement_input_received.connect(_on_movement_input)
	on_sprint_input_received.connect(_on_sprint_input)
	on_crouch_input_received.connect(_on_crouch_input)
	on_jump_input_received.connect(_on_jump_input)
	
func _process(delta: float) -> void:
	state_machine._update(delta)	

func _physics_process(_delta: float) -> void:
	player.velocity = current_queued_velocity
	current_queued_velocity = Vector3.ZERO
	state_machine._physics_update(_delta)
	var current_active_state : PlayerState = state_machine._get_current_active_state()
	_handle_player_move(_delta,current_active_state)
	_handle_gravity(_delta, current_active_state)
	player.move_and_slide()

func _on_movement_input(_event : InputEvent) -> void:
	if Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_BACK, MOVE_FORWARD):
		input_direction = Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_BACK, MOVE_FORWARD)
		if(abs(input_direction.x) < movement_deadzone.x):
			input_direction.x = 0
		if(abs(input_direction.y) < movement_deadzone.y):
			input_direction.y = 0
	else:
		input_direction = Vector2.ZERO

	on_player_movement.emit(input_direction)
	
func _on_sprint_input(_event: InputEvent) -> void:
	sprint_down = _event.is_pressed()
	on_player_sprint_toggle.emit(sprint_down)
	
func _on_crouch_input(_event : InputEvent) -> void:
	crouch_down = _event.is_pressed()
	on_player_crouch_toggle.emit(crouch_down)

func _on_jump_input(_event : InputEvent) -> void:
	var new_state : bool = _event.is_pressed()
	if(new_state != jump_down):
		jump_down = new_state
		on_player_jump_toggle.emit(jump_down)
	
func _handle_player_move(_delta : float, current_active_state : PlayerState):
	var new_horizontal_target :Vector2 = _calculate_target_velocity_for_state(current_active_state)
	if(current_active_state.accelerate_to_target_velocity):
		var velocity_acceleration : float = horizontal_velocity_acceleration
		if(current_active_state.override_velocity_acceleration):
			velocity_acceleration = current_active_state.override_velocity_acceleration
			
		var vel_this_frame : float = velocity_acceleration * _delta
		var vel_difference : float = current_horizontal_velocity.distance_to(new_horizontal_target)
		if(vel_difference != 0):
			current_horizontal_velocity = lerp(current_horizontal_velocity, new_horizontal_target, min(vel_this_frame/ vel_difference,1))
		else:
			current_horizontal_velocity = new_horizontal_target
	else:
		current_horizontal_velocity = new_horizontal_target
	
	var target_vel : Vector3 = (player.transform.basis * Vector3(current_horizontal_velocity.x, 0, -current_horizontal_velocity.y))
	_add_velocity(target_vel)
	
func _calculate_target_velocity_for_state(current_active_state : PlayerState) -> Vector2:
	var horizontal_target : Vector2 = Vector2.ZERO
	if(current_active_state.can_move):
		horizontal_target.x = input_direction.x * current_active_state.sideways_movement_speed
		if(input_direction.y < 0):
			horizontal_target.y = input_direction.y * current_active_state.backward_movement_speed
		else:
			horizontal_target.y = input_direction.y * current_active_state.forward_movement_speed
			
	return horizontal_target		
	
func _handle_gravity(_delta : float, current_active_state : PlayerState):
	if not player.is_on_floor() && current_active_state._get_affected_by_gravity():
		_add_gravity(_delta)
	else:
		_reset_gravity_vel()
		
func _add_velocity(added_vel : Vector3) -> void:
	current_queued_velocity += added_vel
	
func _add_gravity(_delta : float)	-> void:
	if(player.velocity.y <= 0):
		current_gravity_time += _delta
	var current_max_alpa : float = gravity_growth_curve.sample(current_gravity_time / time_reach_max_gravity_velocity)
	
	if(current_gravity_velocity > max_gravity_velocity):
		current_gravity_velocity = max_gravity_velocity * current_max_alpa
		current_gravity_velocity = max(current_gravity_velocity, max_gravity_velocity)
	_add_velocity( Vector3(0,current_gravity_velocity,0))
	pass
	
func _reset_gravity_vel() -> void:
	current_gravity_velocity = 0
	current_gravity_time = 0
	
func _is_current_movement_state(state : PlayerStateMachine.E_StateName) -> bool:
	var current_sm : PlayerStateMachine = state_machine._get_current_state_machine()
	if(current_sm.states_map.has(state)):
		return current_sm.states_map[state] == current_sm._get_current_active_state()
		
	return false	
