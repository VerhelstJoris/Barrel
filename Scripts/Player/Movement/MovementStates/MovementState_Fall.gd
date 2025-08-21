class_name Fall extends PlayerState

## Variable for storing the state prior to falling
var init_state: int


func physics_update(_delta: float) -> void:
	if player.is_on_floor():
		state_machine._transition_to(state_machine.movement_state[init_state])
	
	if not mov_comp.input_direction:
		init_state = state_machine.WALK
		