@icon("res://DEBUG/Icons/Ico_Jump.png")
class_name PlayerMovementComponent extends Node

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_gravity_velocity : Vector3 = Vector3.ZERO

signal on_movement_input_received(event: InputEvent)
signal on_sprint_input_received(event: InputEvent)

@export_group("Controls map names")
@export var MOVE_FORWARD: String = "move_forward"
@export var MOVE_BACK: String = "move_back"
@export var MOVE_LEFT: String = "move_left"
@export var MOVE_RIGHT: String = "move_right"
@export var JUMP: String = "jump"
@export var SPRINT: String = "sprint"

@export_group("General Control Settings")
@export var movement_deadzone : Vector2 = Vector2(0.1,0.1)


var sprint_down : bool = false
var input_direction: Vector2

@onready var state_machine: PlayerStateMachine = %BaseMovementStateMachine
var player: Player

signal on_player_movement(direction)
signal on_player_sprint_toggle(new_val)

func _ready() -> void:
	await owner.ready
	player = owner as Player
	on_movement_input_received.connect(_on_movement_input)
	on_sprint_input_received.connect(_on_sprint_input)
	#state_machine.set_physics_process(true)
	#state_machine.set_process(true)
	
func _physics_process(_delta: float) -> void:
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

func _set_velocity(new_vel : Vector3) -> void:
	player.velocity = new_vel
	
func _add_velocity(added_vel : Vector3) -> void:
	player.velocity += added_vel
	
func _add_gravity(_delta : float)	-> void:
	current_gravity_velocity = current_gravity_velocity.move_toward(Vector3(0, player.velocity.y - gravity, 0), gravity * _delta)
	_add_velocity(current_gravity_velocity)
	
func _reset_gravity_vel() -> void:
	current_gravity_velocity = Vector3.ZERO