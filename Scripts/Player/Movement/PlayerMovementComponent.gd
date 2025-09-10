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

@export_group("Gravity Settings")
@export var max_gravity_velocity : float = -18
@export var gravity_growth_curve : Curve
@export var time_reach_max_gravity_velocity : float = 1.5

var current_gravity_velocity : float = 0
var current_gravity_time : float = 0

@export_group("Controls map names")
@export var MOVE_FORWARD: String = "move_forward"
@export var MOVE_BACK: String = "move_back"
@export var MOVE_LEFT: String = "move_left"
@export var MOVE_RIGHT: String = "move_right"

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
	var horizontal_target : Vector2 = _calculate_target_velocity_for_state(current_active_state)
	var final_target : Vector2 = _calculate_potential_lerped_target_velocity(current_active_state, horizontal_target)
	var target_vel : Vector3 = (player.transform.basis * Vector3(final_target.x, 0, -final_target.y))

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

func _calculate_potential_lerped_target_velocity(current_active_state : PlayerState, new_target_velocity : Vector2) -> Vector2:
	if(current_active_state.velocity_decay_to_current_state_time <= 0 || previous_state == null || current_active_state.current_time_in_state > current_active_state.velocity_decay_to_current_state_time):
		return new_target_velocity

	var prev_state_target : Vector2 = _calculate_target_velocity_for_state(previous_state)
	
	return lerp(prev_state_target, new_target_velocity, current_active_state.current_time_in_state / current_active_state.velocity_decay_to_current_state_time)

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
