@icon("res://DEBUG/Icons/Ico_StateMachine.png")
class_name PlayerStateMachine extends Node

signal transitioned(state: MovementState_Base)

var owner_state : MovementState_Base = null

enum EStateName {None, Grounded, Walk, Sprint, Fall, Jump, Crouch}

@export var states_map : Dictionary[EStateName, MovementState_Base]

@export var initial_state : EStateName = EStateName.None

var current_state: MovementState_Base

func _ready() -> void:
	await owner.ready
	_init_child_states()
	_enter_initial_state()
	set_physics_process(false)
	set_process(false)
			
func _enter_initial_state() -> void:
	if(initial_state != EStateName.None):
		if(states_map.has(initial_state)):
			_transition_to(initial_state)
		else:
			push_error("State Machine  \"" + name + "\" has a starting state but this state does not appear in the map")
	else:
		push_error("State Machine  \"" + name + "\" has no starting state")
	
func _init_child_states()	 -> void:		
	for key in states_map:
		if(states_map[key] is MovementState_Base):
			states_map[key].state_machine = self
			states_map[key].state_type = key
		else:
			push_error("State \"" + states_map[key].name + "\" Is not a valid state!")

#called externally			
func _update(delta: float) -> void:
	current_state._update(delta)

#called externally				
func _physics_update(delta: float) -> void:
	current_state.current_time_in_state += delta
	if(current_state.current_time_in_state > current_state.minimum_time_in_state):
		current_state._check_transitions()
	current_state._physics_update(delta)
	
func _transition_to(target_state: EStateName) -> void:
	var target_state_name : String = EStateName.keys()[target_state]
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
	
func _get_current_active_state() -> MovementState_Base:
	if(current_state.child_state_machine):
		return current_state.child_state_machine._get_current_active_state()
	
	return current_state	

func _get_current_state_machine() -> PlayerStateMachine:
	if(current_state.child_state_machine):
		return current_state.child_state_machine._get_current_state_machine()

	return self	