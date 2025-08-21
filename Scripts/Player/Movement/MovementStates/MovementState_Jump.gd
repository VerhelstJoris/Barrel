class_name Jump extends PlayerState

var init_state: int
var input_dir: Vector2
var move_speed: float

var has_direction: bool


func enter() -> void:
	move_speed = mov_comp.walk_back_speed
	has_direction = mov_comp.input_direction != Vector2.ZERO
	mov_comp.velocity.y = sqrt(mov_comp.jump_height * 2 * mov_comp.gravity)


func physics_update(_delta: float) -> void:
	if mov_comp.velocity.y < 0:
		state_machine._transition_to(
			state_machine.movement_state[state_machine.FALL]
		)
	
	input_dir = mov_comp.input_direction
	
	if not input_dir:
		init_state = state_machine.WALK
	
	var direction := (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# this gives some in-air control if jumping from standing still
	if (has_direction && mov_comp.velocity.length() < mov_comp.walk_back_speed) || !has_direction:
		if direction:
			mov_comp.velocity.x = direction.x * move_speed
			mov_comp.velocity.z = direction.z * move_speed
		else:
			mov_comp.velocity.x = move_toward(mov_comp.velocity.x, 0, move_speed)
			mov_comp.velocity.z = move_toward(mov_comp.velocity.z, 0, move_speed)
