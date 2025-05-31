class_name Fall extends PlayerState

## Variable for storing the state prior to falling
var init_state: int


func enter(msg := {}) -> void:
	player.is_affected_by_gravity = true
	if msg:
		init_state = msg[state_machine.TO]


func physics_update(_delta: float) -> void:
	if player.is_on_floor():
		state_machine.transition_to(state_machine.movement_state[init_state])
	
	if not player.input_direction:
		init_state = state_machine.WALK
		