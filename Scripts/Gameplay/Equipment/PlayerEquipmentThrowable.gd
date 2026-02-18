class_name PlayerEquipmentThrowable extends  PlayerEquipment

signal drop_equipment_input(event: InputEvent)
var drop_queued : bool = false
var throw_queued : bool = false
var drop_transform : Transform3D = Transform3D.IDENTITY

@export_group("Throw Settings")
@export var max_throw_distance : float = 12.5
@export var upward_throw_max_dist_mult : float = 0.4
@export var downward_throw_max_dist_mult : float = 1.4
@export var throw_velocity : float = 12.5
@export var temp_collisions_exceptions_time : float = 0.1
var target_ray : RayCast3D = null

@export_group("Trajectory Preview Settings")
@export var DEBUG_draw_target_path : bool = false
var trajectory_renderer : LineRenderer
@export var trajectory_renderer_scene : PackedScene
@export var check_trajectory_intersect : bool = true

const trajectory_alpha_shader_param : String = "Opacity"
var trajectory_alpha_tween : Tween
@export var max_trajectory_alpha : float = 0.4
@export var trajectory_preview_alpha_fadein_time : float = 0.25
@export var trajectory_preview_alpha_fadeout_time : float = 0.1

@export var trajectory_impact_scene : PackedScene
var trajectory_impact_effect : Node3D
var trajectory_impact_global_trans : Transform3D = Transform3D.IDENTITY
var trajectory_impact_alpha_tween : Tween
@export var max_trajectory_impact_alpha : float = 0.4
@export var trajectory_impact_alpha_tween_time : float = 0.25

#used to interpolate the trajectory on non-physics frames
var physics_ray_start_point : Vector3 = Vector3.ZERO
var physics_ray_end_point : Vector3 = Vector3.ZERO
var trajectory_impact_point : Node3D
var phys_traj_positions : Array[Vector3]

@export_group("Components")
@export var rigid_body : CollisionPhysicsBody
@export var hitboxes : Array[HitboxComponent]

@export var meshes : Array[MeshInstance3D]
@export var collision_shape_for_drop_test : CollisionShape3D

enum EThrowableEquipmentState{ Default, Aiming, Throwing} 

var temporary_collisions_exceptions_to_remove : Array[Node]
var collision_exception_timer : Timer

var current_throwable_state : EThrowableEquipmentState = EThrowableEquipmentState.Default
var current_calculated_throw_velocity : Vector3 = Vector3.ZERO
var current_target_is_collision : bool = false
var current_calculated_throw_target : Vector3 = Vector3.ZERO

const aiming_input_context_name : String = "Aiming"

signal on_throwable_state_changed(prev : EThrowableEquipmentState, new : EThrowableEquipmentState)

var gravity : Vector3 = Vector3(0,-9.8,0)

func _ready() -> void:
	super()
	drop_equipment_input.connect(_try_drop_equipment)
	
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity_vector") *  ProjectSettings.get_setting("physics/3d/default_gravity")
	
func _process(_delta: float) -> void:
	if(current_throwable_state == EThrowableEquipmentState.Aiming):
		trajectory_renderer.set_global_position(owner.get_global_position())
		trajectory_renderer.set_global_rotation(owner.get_global_rotation())
		_draw_throw_trajectory()
		
func _physics_process(_delta: float) -> void:
	if(current_throwable_state == EThrowableEquipmentState.Aiming):
		_determine_throw_target()
	else:
		if(trajectory_impact_effect):
			trajectory_impact_effect.visible = false
		
	if(drop_queued):
		_drop()
		drop_queued = false
		return
		
	if(throw_queued):
		_throw()
		throw_queued = false
		
func _throw() -> void:
	_add_collisions_exceptions()
	
	var reset_transform : Transform3D = owner.get_global_transform()
	player.equipment_manager._remove_equipment_from_slot(slot)
	owner.reparent(get_tree().root, true)
	owner.set_global_transform(reset_transform)
	
	rigid_body.set_linear_velocity(current_calculated_throw_velocity)
	rigid_body.set_angular_velocity(current_calculated_throw_velocity * 0.25)
	
func _add_collisions_exceptions() -> void:
	if(rigid_body == null):
		return
		
	rigid_body.add_collision_exception_with(player)
		
	temporary_collisions_exceptions_to_remove = [player]	
	
	if(collision_exception_timer == null):
		collision_exception_timer = Timer.new()
		owner.add_child(collision_exception_timer)
	
	collision_exception_timer.wait_time = temp_collisions_exceptions_time
	collision_exception_timer.one_shot = true
	
	collision_exception_timer.timeout.connect(_on_collision_exception_timer_timeout)
	collision_exception_timer.start()
	
func _on_collision_exception_timer_timeout() -> void:
	if(rigid_body != null):
		for exception in temporary_collisions_exceptions_to_remove:
			if(exception != null):
				rigid_body.remove_collision_exception_with(exception)
				
func _can_be_holstered() -> bool:
	return false
	
func _on_equipped(_player : Player) -> void:
	super(_player)
	set_physics_process(true)
	owner.set_rotation(Vector3.ZERO)
	owner.set_position(Vector3.ZERO)

	for hitbox in hitboxes:
		hitbox._set_collisions_enabled(false)
		
	for mesh in meshes:
		mesh.set_layer_mask_value(1,false)
		mesh.set_layer_mask_value(2,true)
		
	_change_throwable_state(EThrowableEquipmentState.Default)	
	
	if(trajectory_renderer_scene):
		trajectory_renderer = trajectory_renderer_scene.instantiate()
		_set_trajectory_alpha(0)
		player.player_cam.add_child.call_deferred(trajectory_renderer)
		
	if(trajectory_impact_scene):
		trajectory_impact_effect = trajectory_impact_scene.instantiate()
		_set_trajectory_impact_alpha(0)
		player.player_cam.add_child.call_deferred(trajectory_impact_effect)
		trajectory_impact_effect.visible = false

	target_ray = _player.throwable_ray
		
func _on_unequipped():
	for hitbox in hitboxes:
		hitbox._set_collisions_enabled(true)

	for mesh in meshes:
		mesh.set_layer_mask_value(1,true)
		mesh.set_layer_mask_value(2,false)
		
	if(trajectory_renderer):
		trajectory_renderer.queue_free()

	target_ray.enabled = false
	target_ray = null
		
	super()
	
func _try_use_equipment(_event : InputEvent) -> void:
	match current_throwable_state:
		EThrowableEquipmentState.Default:
			if(_can_enter_aiming_mode(_event)):
				_change_throwable_state(EThrowableEquipmentState.Aiming)
		EThrowableEquipmentState.Aiming:
			if(_can_currently_throw(_event)):
				_change_throwable_state(EThrowableEquipmentState.Throwing)
		_:
			pass
			
func _proceed_with_action_from_animation() -> void:
	if(current_throwable_state == EThrowableEquipmentState.Throwing):
		throw_queued = true
		return

func _can_enter_aiming_mode( _event : InputEvent) -> bool:
	if(current_throwable_state != EThrowableEquipmentState.Default):
		return false
	
	if(_event.is_released()):
		return false
		
	return true	
		
func _can_currently_throw(_event : InputEvent) -> bool:
	if(current_throwable_state != EThrowableEquipmentState.Aiming):
		return false
	
	if(_event.is_released()):
		return true
		
	return false	
	
func _try_drop_equipment(_event : InputEvent) -> void:
	match current_throwable_state:
		EThrowableEquipmentState.Default:
			if(_can_be_dropped()):
				drop_queued = true
		EThrowableEquipmentState.Aiming:
			if(_can_exit_aiming()):
				_change_throwable_state(EThrowableEquipmentState.Default)
		_:
			#exit out of aiming	
			pass
			
func _can_be_dropped() -> bool:
	if(current_throwable_state != EThrowableEquipmentState.Default):
		return false
		
	return true
	
func _can_exit_aiming() -> bool:
	return true

func _change_throwable_state( new_state : EThrowableEquipmentState) -> void:
	var prev_state = current_throwable_state
	match current_throwable_state:
		EThrowableEquipmentState.Aiming:
			trajectory_alpha_tween = create_tween()
			trajectory_alpha_tween.tween_method(_set_trajectory_alpha, _get_trajectory_current_alpha(), 0.0, trajectory_preview_alpha_fadeout_time)
	
	current_throwable_state = new_state
	
	match new_state:
		EThrowableEquipmentState.Default:
			if(input_receiver):
				input_receiver._change_current_input_mapping_context(InputReceiver.default_mapping_context_name ,self, true)
		EThrowableEquipmentState.Aiming:
			if(input_receiver):
				input_receiver._change_current_input_mapping_context(aiming_input_context_name ,self, true)
			trajectory_alpha_tween = create_tween()
			trajectory_alpha_tween.tween_method(_set_trajectory_alpha, _get_trajectory_current_alpha(), max_trajectory_alpha, trajectory_preview_alpha_fadein_time)
		EThrowableEquipmentState.Throwing:
			# when throwing actually happens, already hide existing prompts
			if(input_receiver):
				input_receiver._enable_current_HUD_actions(self, false)
	
	on_throwable_state_changed.emit(prev_state, new_state)		

func _set_trajectory_alpha(value : float) -> void:
	if(trajectory_renderer):
		trajectory_renderer.set_instance_shader_parameter(trajectory_alpha_shader_param, value)

func _get_trajectory_current_alpha() -> float:
	if(trajectory_renderer):
		return trajectory_renderer.get_instance_shader_parameter(trajectory_alpha_shader_param)

	return 0.0
	
func _set_trajectory_impact_alpha(value : float) -> void:
	if(trajectory_impact_effect):
		for child in trajectory_impact_effect.get_children():
			if child is MeshInstance3D:
				child.set_instance_shader_parameter(trajectory_alpha_shader_param, value)


func _drop() -> void:
	if(!_decide_target_transform_for_drop()):
		return
	
	var params : PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	params.motion = Vector3.UP * 0.01
	params.from = drop_transform
	
	player.equipment_manager._remove_equipment_from_slot(slot)
	owner.reparent(get_tree().root, true)
	owner.set_global_transform(drop_transform)

func _determine_throw_target() -> void:
	if(!target_ray):
		push_error("Cannot determine a throw target without a ray to check on ", owner.name)
		return
		
	var ray_length : float = _determine_throw_target_length()

	target_ray.target_position.y = ray_length
	target_ray.force_raycast_update()

	var world_cam : Camera3D = player.player_cam
	var cam_pos : Vector3 = world_cam.get_global_position()
	var dir : Vector3 = -world_cam.get_global_basis().z
	physics_ray_end_point = cam_pos + (dir.normalized() * ray_length)
	
	if (target_ray.is_colliding()):
		current_calculated_throw_target = target_ray.get_collision_point()
		trajectory_impact_global_trans.origin = current_calculated_throw_target
		trajectory_impact_global_trans.basis = Basis.from_euler(Quaternion(Vector3.UP, target_ray.get_collision_normal()).get_euler())
		if(DEBUG_draw_target_path):
			DebugDraw3D.draw_sphere(current_calculated_throw_target,0.1,Color.RED, 0)
	else:
		#set the target point at the end of the ray
		current_calculated_throw_target = physics_ray_end_point
		trajectory_impact_global_trans = Transform3D.IDENTITY
		if DEBUG_draw_target_path:
			DebugDraw3D.draw_sphere(current_calculated_throw_target,0.1,Color.GREEN, 0)
	
	_calculate_trajectory_path_points()
		
func _calculate_trajectory_path_points() -> void:
	var result : Array = TrajectoryLib.fixed_target(owner.get_global_position(),throw_velocity,current_calculated_throw_target, gravity)
	physics_ray_start_point = owner.get_global_position()
	
	if(result.is_empty()):
		push_error("Was not able to calculate path from ", owner.get_global_position(), " to ", current_calculated_throw_target)
		return
		
	var sampled_data: Array = TrajectoryLib.samples(owner.get_global_position(),result[0].velocity,gravity,result[0].time, 15)
	current_calculated_throw_velocity = result[0].velocity
	if(DEBUG_draw_target_path):
		for id in sampled_data.size() -1:
			DebugDraw3D.draw_line(sampled_data[id].position, sampled_data[id+1].position,Color.BLUE,0)	


	phys_traj_positions.clear()

	if(!check_trajectory_intersect):
		phys_traj_positions.resize(sampled_data.size())

		for id in sampled_data.size() - 1:
			phys_traj_positions[id] = sampled_data[id].position

		phys_traj_positions[sampled_data.size()-1] = current_calculated_throw_target
	else:
		var space_state: PhysicsDirectSpaceState3D = owner.get_world_3d().get_direct_space_state()
		
		for id in sampled_data.size() - 1:
			var query := PhysicsRayQueryParameters3D.create(sampled_data[id].position, sampled_data[id +1].position)
			query.collide_with_bodies = true
			query.collide_with_areas = false
			query.hit_from_inside = true
			query.hit_back_faces = true
		
			var ray_hit : Dictionary  = space_state.intersect_ray(query)
			#if we hit that's the final result of our path, if not, keep going
			if(ray_hit):
				phys_traj_positions.append(ray_hit.position)
				trajectory_impact_global_trans.origin = ray_hit.position
				trajectory_impact_global_trans.basis = Basis.from_euler(Quaternion(Vector3.UP, ray_hit.normal).get_euler())
				return
			else:
				phys_traj_positions.append(sampled_data[id].position)
				
		phys_traj_positions.append(current_calculated_throw_target)
		
func _determine_throw_target_length() -> float:
	var world_cam : Camera3D = player.player_cam
	var dir : Vector3 = -world_cam.get_global_basis().z
	var dot : float = dir.dot(Vector3.UP)

	var mult : float = 1.0
	#if the dot product is negative, we are looking down and extend the distance we can throw if needed
	if(dot < 0):
		mult =  lerp(1.0, downward_throw_max_dist_mult, abs(dot))
	else:
		mult =  lerp(1.0, upward_throw_max_dist_mult, abs(dot))
	
	#if the dot product is positive, we are looking up and reduce the distance we can throw
	return max_throw_distance * mult
	
func _draw_throw_trajectory() -> void:
	if(trajectory_renderer):
		trajectory_renderer.points = phys_traj_positions
		
	if(trajectory_impact_effect != null):
		if(trajectory_impact_global_trans != Transform3D.IDENTITY):
			if( !trajectory_impact_effect.visible && (trajectory_impact_alpha_tween == null || !trajectory_impact_alpha_tween.is_running()) ):
				trajectory_impact_alpha_tween = create_tween()
				trajectory_impact_alpha_tween.tween_method(_set_trajectory_impact_alpha, 0.0, max_trajectory_impact_alpha,  trajectory_impact_alpha_tween_time)
			trajectory_impact_effect.visible = true
			trajectory_impact_effect.set_global_transform(trajectory_impact_global_trans)
		else:
			trajectory_impact_effect.visible = false
			
func _decide_target_transform_for_drop() -> bool:
	drop_transform = Transform3D.IDENTITY
	if(player == null):
		return false
		
	# if the player's interactor raycast has hit something, put it there based on the normal of the hit
	if(player.interactor.interact_ray.is_colliding()):
		#TODO: check if the angle compared to the UP is not too big?
		drop_transform = drop_transform.looking_at(player.interactor.interact_ray.get_collision_normal(),Vector3.UP,true )
		drop_transform.origin = player.interactor.interact_ray.get_collision_point()
	else:
		#else just put it at the end of the interactor ray, pointing up
		var forward_offset : Vector3 = (-player.interactor.interact_ray.get_global_basis().y * player.interactor.interact_ray.get_target_position().length())
		drop_transform = drop_transform.looking_at(Vector3.UP,Vector3.UP,true)
		drop_transform.origin = player.interactor.interact_ray.get_global_position() + forward_offset
	
	if(_intersects_with_invalid(drop_transform, true)):
		#add to forward and try again
		var player_offset : Vector3 = (-player.get_global_transform().basis.z * 0.45)
		drop_transform.origin = drop_transform.origin + player_offset
		if(_intersects_with_invalid(drop_transform, false)):
			return false

	return true
	
func _intersects_with_invalid(trans: Transform3D, player_only_intersect_check : bool) -> bool:
	if(collision_shape_for_drop_test == null):
		return false

	var space: PhysicsDirectSpaceState3D = collision_shape_for_drop_test.get_world_3d().direct_space_state
	if(space == null):
		return false
	
	var params : PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.transform = trans
	params.motion = Vector3.UP * 0.01
	params.shape_rid = collision_shape_for_drop_test.get_shape().get_rid()
	params.collide_with_areas = false
	params.collide_with_bodies = true
	
	var result: Array[Dictionary] = space.intersect_shape(params,1)
	if(result.size() != 0 && (result[0].collider == player || !player_only_intersect_check)):
		return true
		
	return false	