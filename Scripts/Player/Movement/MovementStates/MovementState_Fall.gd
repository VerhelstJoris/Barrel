class_name Fall extends PlayerState

func _check_transitions() -> void:
	if mov_comp._is_on_floor():
		state_machine._transition_to(state_machine.E_StateName.Grounded)
		