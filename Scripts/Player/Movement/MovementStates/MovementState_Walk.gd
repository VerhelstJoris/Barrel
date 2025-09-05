class_name Walk extends PlayerState


func _check_transitions() -> void:
	if(mov_comp.sprint_down && mov_comp.input_direction.y > 0):
		state_machine._transition_to(state_machine.E_StateName.Sprint)

func _on_physics_update_internal(_delta: float) -> void:
	super(_delta)
