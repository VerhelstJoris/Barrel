class_name MovementStateGrounded extends PlayerState

func _check_transitions() -> void:
	if(!player.is_on_floor()):
		state_machine._transition_to(state_machine.E_StateName.Fall)
		
	if(player.is_on_floor() && mov_comp.jump_down):
		state_machine._transition_to(state_machine.E_StateName.Jump)
