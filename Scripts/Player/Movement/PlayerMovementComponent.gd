@icon("res://DEBUG/Icons/Ico_Jump.png")
class_name PlayerMovementComponent extends Node

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_queued_velocity : Vector3 = Vector3.ZERO

signal on_player_movement_state_enter(new_state : PlayerStateMachine.EStateName)
signal on_player_movement_state_leave(new_state : PlayerStateMachine.EStateName)

@export_group("Movement Acceleration Settings")
@export var horizontal_velocity_acceleration : float = 6.0
var current_horizontal_velocity : Vector2 = Vector2.ZERO

@export_group("Step Height Settings")
@export var max_step_up_height : float = 0.26
@onready var step_below_ray : RayCast3D = %StepBelowRay
@onready var step_in_front_ray : RayCast3D = %StepInFrontRay
var _stepped_last_frame : bool = false

var _draw_step_debug : bool = false

@export_group("Gravity Settings")
@export var max_gravity_velocity : float = -18
@export var gravity_growth_curve : Curve
@export var time_reach_max_gravity_velocity : float = 1.5

var current_gravity_velocity : float = 0
var current_gravity_time : float = 0

@export_group("Collision Settings")
@export var impulse_applied_on_rb_collision : float = 1.0

@onready var state_machine: PlayerStateMachine = %BaseMovementStateMachine

var previous_state : MovementState_Base = null

var player: Player

func _ready() -> void:
	await owner.ready
	player = owner as Player
			
func _process(delta: float) -> void:
	state_machine._update(delta)	

func _is_on_floor() -> bool:
	return player.is_on_floor() || _stepped_last_frame

func _physics_process(_delta: float) -> void:
	current_queued_velocity = Vector3.ZERO
	state_machine._physics_update(_delta)
	var current_active_state : MovementState_Base = state_machine._get_current_active_state()
	_handle_player_move(_delta,current_active_state)
	_handle_gravity(_delta, current_active_state)

	var stepped_up : bool = _try_stair_step_up(_delta)
	var stepped_down : bool = false
	if(!stepped_up):
		player.velocity = current_queued_velocity
		player.move_and_slide()
		stepped_down = _try_stair_step_down(_delta)
		for id in player.get_slide_collision_count():
			_on_collided_with(player.get_slide_collision(id), id)


	_stepped_last_frame = stepped_up || stepped_down

func _is_surface_too_steep(normal : Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > player.floor_max_angle

func _try_stair_step_up(_delta : float) -> bool:
	if (!_is_on_floor()):
		return false

	if(player.velocity.y > 0):
		return false
		
	# Not moving or attempting to move, skip stair check
	if (current_queued_velocity.is_zero_approx() && player.input_receiver.input_direction.is_zero_approx()):
		return false
		
	var expected_move_motion : Vector3 = Vector3(current_queued_velocity.x, 0, current_queued_velocity.z) * _delta
	var step_transform_with_clearance: Transform3D = player.global_transform.translated(expected_move_motion + Vector3(0,max_step_up_height,0))

	# Run a body_test_motion slightly above the pos we expect to move to, towards the floor.
	#  We give some clearance above to ensure there's ample room for the player.
	#  If it hits a step <= max_step_up_height, we can teleport the player on top of the step
	#  along with their intended motion forward.
	var down_check_result = KinematicCollision3D.new()
	
	
	if (!player.test_move(step_transform_with_clearance, Vector3(0,-max_step_up_height *2,0), down_check_result)):
		return	false# didn't hit anything abort

	if(!_can_step_on_object(down_check_result)):
		return false

	if(_draw_step_debug):
		DebugDraw3D.draw_sphere(down_check_result.get_position(),0.05, Color(0,1,0))

	#check if the found step is too hight	
	var found_step_height : float = ((step_transform_with_clearance.origin + down_check_result.get_travel()) - player.global_position).y
	if(found_step_height > max_step_up_height || found_step_height < 0.01):
		return false

	#did the collision happen low enough to our current ground	
	if( (down_check_result.get_position() - player.global_position).y > max_step_up_height):
		return false

	#check if the surface we are went to step on is too step	
	step_in_front_ray.global_position = down_check_result.get_position() + Vector3(0,max_step_up_height,0) + (expected_move_motion.normalized() *0.05)
	if(_draw_step_debug):
		DebugDraw3D.draw_sphere(step_in_front_ray.global_position,0.05,Color(1,0,1))
		DebugDraw3D.draw_line(step_in_front_ray.global_position , step_in_front_ray.global_position + (down_check_result.get_normal() * 0.25),Color(1,0,1),0.05)

	step_in_front_ray.force_raycast_update()
	if(step_in_front_ray.is_colliding() and !_is_surface_too_steep(step_in_front_ray.get_collision_normal())):
		if(_draw_step_debug):
			DebugDraw3D.draw_sphere(step_transform_with_clearance.origin + down_check_result.get_travel(),0.05,Color(1,0,0))
		player.global_position = step_transform_with_clearance.origin + down_check_result.get_travel()
		player.apply_floor_snap()
		return true
	return false
	
func _can_step_on_object(result : KinematicCollision3D) -> bool:
	if(result.get_collider() is RigidBody3D):
		return false
	return true

func _try_stair_step_down(_delta : float) -> bool:
	if(!_is_on_floor()):
		return false
		
	#we are moving up, do not snap us down	
	if(player.velocity.y > 0):
		return false
		
	if (current_queued_velocity.is_zero_approx() && player.input_receiver.input_direction.is_zero_approx()):
		return false
		
	#move and slide was already called so ray needs updating
	step_below_ray.force_update_transform()
	var floor_below : bool = step_below_ray.is_colliding() && !_is_surface_too_steep(step_below_ray.get_collision_normal())
	if(!floor_below):
		return false
	
	var body_test_result = KinematicCollision3D.new()
	if !player.test_move(player.global_transform, Vector3(0,-max_step_up_height,0), body_test_result):
		return false

	if(!_can_step_on_object(body_test_result)):
		return false

	player.position.y += body_test_result.get_travel().y
	player.apply_floor_snap()
	return true
	
func _handle_player_move(_delta : float, current_active_state : MovementState_Base):
	var new_horizontal_target :Vector2 = _calculate_target_velocity_for_state(current_active_state)
	if(current_active_state.accelerate_to_target_velocity):
		var velocity_acceleration : float = horizontal_velocity_acceleration
		if(current_active_state.override_velocity_acceleration):
			velocity_acceleration = current_active_state.override_velocity_acceleration
			
		var vel_this_frame : float = velocity_acceleration * _delta
		var vel_difference : float = current_horizontal_velocity.distance_to(new_horizontal_target)
		if(vel_difference != 0):
			current_horizontal_velocity = lerp(current_horizontal_velocity, new_horizontal_target, min(vel_this_frame/ vel_difference,1))
		else:
			current_horizontal_velocity = new_horizontal_target
	else:
		current_horizontal_velocity = new_horizontal_target
	
	#print("new_horizontal_target " , current_horizontal_velocity)
	var target_vel : Vector3 = (player.transform.basis * Vector3(current_horizontal_velocity.x, 0, -current_horizontal_velocity.y))
	_add_velocity(target_vel)
	
func _calculate_target_velocity_for_state(current_active_state : MovementState_Base) -> Vector2:
	var horizontal_target : Vector2 = Vector2.ZERO
	var input_dir : Vector2 = player.input_receiver.input_direction
	if(current_active_state.can_move):
		horizontal_target.x = input_dir.x * current_active_state.sideways_movement_speed
		if(input_dir.y < 0):
			horizontal_target.y = input_dir.y * current_active_state.backward_movement_speed
		else:
			horizontal_target.y = input_dir.y * current_active_state.forward_movement_speed
			
	return horizontal_target		
	
func _handle_gravity(_delta : float, current_active_state : MovementState_Base):
	if !_is_on_floor() && current_active_state._get_affected_by_gravity():
		_add_gravity(_delta)
	else:
		_reset_gravity_vel()
		
func _add_velocity(added_vel : Vector3) -> void:
	current_queued_velocity += added_vel
	
func _add_gravity(_delta : float)	-> void:
	if(player.velocity.y <= 0):
		current_gravity_time += _delta
	var current_max_alpa : float = gravity_growth_curve.sample(current_gravity_time / time_reach_max_gravity_velocity)
	
	if(current_gravity_velocity > max_gravity_velocity):
		current_gravity_velocity = max_gravity_velocity * current_max_alpa
		current_gravity_velocity = max(current_gravity_velocity, max_gravity_velocity)
	_add_velocity( Vector3(0,current_gravity_velocity,0))
	pass
	
func _reset_gravity_vel() -> void:
	current_gravity_velocity = 0
	current_gravity_time = 0
	
func _is_current_movement_state(state : PlayerStateMachine.EStateName) -> bool:
	var current_sm : PlayerStateMachine = state_machine._get_current_state_machine()
	if(current_sm.states_map.has(state)):
		return current_sm.states_map[state] == current_sm._get_current_active_state()
		
	return false	

func _on_collided_with(collision: KinematicCollision3D, _index : int) -> void:
	var rb : RigidBody3D = collision.get_collider() as RigidBody3D
	if(rb):
		rb.apply_impulse( -collision.get_normal(0) * impulse_applied_on_rb_collision ,collision.get_position(0))
