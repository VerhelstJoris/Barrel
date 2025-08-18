class_name Walk extends PlayerState

var move_speed: float
@export var walk_back_speed: float = 1.5
@export var walk_speed: float = 2.5

func enter(_msg := {}) -> void:
	pass
	
	
func physics_update(_delta: float) -> void:
	var input_dir : Vector2 = mov_comp.input_direction
	var direction := (player.transform.basis * Vector3(input_dir.x, 0, -input_dir.y)).normalized()

	if input_dir.y < 0:
		move_speed = walk_back_speed
	else:
		move_speed = walk_speed
	
	if direction:
		player.velocity.x = direction.x * move_speed
		player.velocity.z = direction.z * move_speed
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, move_speed)
		player.velocity.z = move_toward(player.velocity.z, 0, move_speed)
	

	if player.velocity.y < 0:
		state_machine.transition_to(
			state_machine.movement_state[state_machine.FALL],
			{ state_machine.TO : state_machine.WALK }
		)
