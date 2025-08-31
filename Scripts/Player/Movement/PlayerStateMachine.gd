@icon("res://DEBUG/Icons/Ico_StateMachine.png")
class_name PlayerStateMachine extends Node

signal transitioned(state: PlayerState)

var owner_state : PlayerState = null

enum E_StateName {None, Grounded, Walk, Sprint, Fall, Jump}

@export var states_map : Dictionary[E_StateName, PlayerState]

@export var initial_state : E_StateName = E_StateName.None

var current_state: PlayerState

func _ready() -> void:
	await owner.ready
	_init_child_states()
			
	_enter_initial_state()
			
func _enter_initial_state() -> void:
	if(initial_state != E_StateName.None):
		if(states_map.has(initial_state)):
			_transition_to(initial_state)
		else:
			push_error("State Machine  \"" + name + "\" has a starting state but this state does not appear in the map")
	else:
		push_error("State Machine  \"" + name + "\" has no starting state")
	
func _init_child_states()	 -> void:		
	for child in get_children():
		if(child is PlayerState):
			child.state_machine = self

func _process(delta: float) -> void:
	current_state._check_transitions()		
	current_state._update_internal(delta)
	
func _physics_process(delta: float) -> void:
	current_state._physics_update_internal(delta)
	
func _transition_to(target_state: E_StateName) -> void:
	var target_state_name : String = E_StateName.keys()[target_state]
	if(!states_map.has(target_state)):
		push_error("No target node \"" +target_state_name + "\" found")
		return
	
	if(current_state):
		print("Exit ", current_state.name, " on ", name)
		current_state._exit_state()
	current_state = states_map[target_state]
	print("Enter ", current_state.name, " on ", name)
	current_state._enter_state()
	emit_signal("transitioned", current_state)
