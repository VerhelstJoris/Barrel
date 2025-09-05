class_name PlayerState extends Node

var state_machine: PlayerStateMachine = null
var mov_comp: PlayerMovementComponent
var player: Player

@export var child_state_machine : PlayerStateMachine = null

@export_group("Input Direction Move")
@export var can_move : bool = true
@export var forward_movement_speed : float = 2.5
@export var sideways_movement_speed : float = 2.5
@export var backward_movement_speed : float = 1.5

@export var minimum_time_in_state : float = 0.0
var current_time_in_state : float = 0.0

@export var is_affected_by_gravity : bool = true

@export_group("Capsule Settings")


func _ready() -> void:
	await owner.ready
	if(child_state_machine != null):
		child_state_machine.owner_state = self
	player = owner as Player
	assert(player != null)
	mov_comp = player.movement_component
	assert(mov_comp != null)
	set_physics_process(false)
	set_process(false)

func _update(_delta : float)	-> void:
	if(child_state_machine != null):
		child_state_machine.current_state._check_transitions()
		child_state_machine.current_state._update(_delta)
	else:
		_on_update_internal(_delta)

#to be overriden by child classes to perform their regular update
func _on_update_internal(_delta: float) -> void:
	pass
	
func _get_affected_by_gravity() -> bool:
	return is_affected_by_gravity

func _physics_update(_delta: float) -> void:
	if(child_state_machine != null):
		child_state_machine.current_state._physics_update(_delta)
	else:
		_on_physics_update_internal(_delta)

#to be overriden by child classes to perform their physics update
func _on_physics_update_internal(_delta: float) -> void:
	pass
	
func _enter_state() -> void:
	current_time_in_state =0
	_on_enter_internal()
	if(child_state_machine):
		child_state_machine._enter_initial_state()

#to be overriden by child classes to perform enter logic
func _on_enter_internal() -> void:
	pass
	
func _exit_state() -> void:
	if(child_state_machine):
		child_state_machine.current_state._exit_state()
	
	_on_exit_internal()	

#to be overriden by child classes to perform exit logic
func _on_exit_internal() -> void:
	pass

#to be overriden by child classes to check which states to transition to
func _check_transitions() -> void:
	pass
