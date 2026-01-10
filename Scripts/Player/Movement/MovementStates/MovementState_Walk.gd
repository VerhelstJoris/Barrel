class_name Walk extends MovementState_Base


func _check_transitions() -> void:
	if(input_comp.sprint_down && input_comp.input_direction.y > 0):
		state_machine._transition_to(state_machine.EStateName.Sprint)
	elif(input_comp.crouch_down):
		state_machine._transition_to(state_machine.EStateName.Crouch)
		
func _on_physics_update_internal(_delta: float) -> void:
	super(_delta)
