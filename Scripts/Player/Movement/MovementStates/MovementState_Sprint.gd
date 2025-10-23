class_name Sprint extends MovementState_Base

var input_dir: Vector2
var move_speed: float


func _check_transitions() -> void:
	if(!input_comp.sprint_down || mov_comp.input_direction.y <= 0):
		state_machine._transition_to(state_machine.E_StateName.Walk)