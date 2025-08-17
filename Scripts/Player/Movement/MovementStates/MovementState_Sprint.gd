class_name Sprint extends PlayerState

var input_dir: Vector2
var move_speed: float


func enter(_msg := {}) -> void:
	pass
	

func physics_update(_delta: float) -> void:
	input_dir = mov_comp.input_direction
	var direction := (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if input_dir.y > 0:
		move_speed = mov_comp.walk_back_speed
	else:
		move_speed = mov_comp.sprint_speed
	
	if direction:
		mov_comp.velocity.x = direction.x * move_speed
		mov_comp.velocity.z = direction.z * move_speed
	else:
		state_machine.transition_to(state_machine.movement_state[state_machine.WALK])
		mov_comp.velocity.x = move_toward(mov_comp.velocity.x, 0, move_speed)
		mov_comp.velocity.z = move_toward(mov_comp.velocity.z, 0, move_speed)
		
	if mov_comp.velocity.y < 0:
		state_machine.transition_to(
			state_machine.movement_state[state_machine.FALL],
			{ state_machine.TO : state_machine.SPRINT }
		)
