class_name Idle extends PlayerState


func enter(_msg := {}) -> void:
	mov_comp.is_affected_by_gravity = true
	player.velocity = Vector3.ZERO
	
func physics_update(_delta: float) -> void:
	var input_dir := mov_comp.input_direction
	
	if input_dir:
		if Input.is_action_just_pressed(mov_comp.SPRINT):
			state_machine.transition_to(state_machine.movement_state[state_machine.SPRINT])
		else:
			state_machine.transition_to(state_machine.movement_state[state_machine.WALK])
