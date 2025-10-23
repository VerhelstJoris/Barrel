class_name MovementStateGrounded extends MovementState_Base

var jump_queued : bool = false

func _on_enter_internal() -> void:
	input_comp.on_player_jump_toggle.connect(_on_jump_down)
	
func _on_jump_down(new_val : bool) -> void:
	if(new_val && mov_comp._is_on_floor()):
		jump_queued= true
	
func _on_exit_internal() -> void:
	input_comp.on_player_jump_toggle.disconnect(_on_jump_down)	

func _check_transitions() -> void:
	if(!mov_comp._is_on_floor()):
		state_machine._transition_to(state_machine.E_StateName.Fall)
		
	if(jump_queued):
		jump_queued = false
		state_machine._transition_to(state_machine.E_StateName.Jump)
