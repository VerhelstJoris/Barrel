class_name Jump extends PlayerState

@export var max_jump_down_time : float = 0.5
var current_jump_down_time : float = 0
@export var target_jump_velocity : float = 400
@export var jump_add_multiplier_curve : Curve

var current_taper_timer : float = 0
@export var post_hold_taper_time : float = 0.1

func _on_enter_internal() -> void:
	current_jump_down_time = 0
	current_taper_timer = 0
	super()
	
func _on_exit_internal() -> void:
	super()
	
func _check_transitions() -> void:
	if(player.is_on_floor()):
		state_machine._transition_to(state_machine.E_StateName.Grounded)
	elif (player.velocity.y < 0 && current_taper_timer < post_hold_taper_time):
		state_machine._transition_to(state_machine.E_StateName.Fall)

func _on_physics_update_internal(_delta: float) -> void:
	var current_alpha: float = current_jump_down_time / max_jump_down_time
	var current_mult : float = jump_add_multiplier_curve.sample(current_alpha)

	var added_force : float
	if(mov_comp.jump_down && current_alpha < 1):
		added_force = target_jump_velocity * current_mult * _delta
		current_jump_down_time += _delta
	elif(current_taper_timer < post_hold_taper_time):
		current_taper_timer += _delta
		#taper the force that's added to prevent dropping like a brick
		added_force = lerp(target_jump_velocity * current_mult * _delta, 0.0, current_taper_timer / post_hold_taper_time)

	mov_comp._add_velocity(Vector3(0,added_force,0))
	super(_delta)

	