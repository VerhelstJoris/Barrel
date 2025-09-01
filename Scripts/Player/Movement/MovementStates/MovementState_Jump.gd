class_name Jump extends PlayerState

@export var max_jump_down_time : float = 0.5
var current_jump_down_time : float = 0
@export var target_jump_velocity : float = 400
@export var jump_add_multiplier_curve : Curve

func _on_enter_internal() -> void:
	current_jump_down_time = 0
	super()
	
func _check_transitions() -> void:
	if(player.is_on_floor()):
		state_machine._transition_to(state_machine.E_StateName.Grounded)
	elif (player.velocity.y < 0):
		state_machine._transition_to(state_machine.E_StateName.Fall)

func _physics_update_internal(_delta: float) -> void:
	var current_alpha: float = current_jump_down_time / max_jump_down_time

	if(mov_comp.jump_down && current_alpha < 1):
		var current_mult : float = jump_add_multiplier_curve.sample(current_alpha)
		var added_force : float = target_jump_velocity * current_mult * _delta
		mov_comp._add_velocity(Vector3(0,added_force,0))
	current_jump_down_time += _delta