class_name Sprint extends PlayerState

var input_dir: Vector2
var move_speed: float


func _check_transitions() -> void:
	if(!mov_comp.sprint_down || mov_comp.input_direction.y <= 0):
		state_machine._transition_to(state_machine.movement_state[state_machine.WALK])