class_name Fall extends PlayerState

## Variable for storing the state prior to falling
var init_state: int

func _check_transitions() -> void:
	if player.is_on_floor():
		state_machine._transition_to(state_machine.E_StateName.Grounded)
		