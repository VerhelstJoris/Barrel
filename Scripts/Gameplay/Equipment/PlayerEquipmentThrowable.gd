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

@export var rigid_body : CollisionPhysicsBody
@export var hitboxes : Array[HitboxComponent]

@export var meshes : Array[MeshInstance3D]
@export var collision_shape_for_drop_test : CollisionShape3D

enum EThrowableEquipmentState{ Default, Aiming, Throwing} 

var current_throwable_state : EThrowableEquipmentState = EThrowableEquipmentState.Default
var current_calculated_throw_velocity = Vector3.ZERO
var debug_drawn : bool = false


const aiming_input_context_name : String = "Aiming"

signal on_throwable_state_changed(prev : EThrowableEquipmentState, new : EThrowableEquipmentState)

var gravity : Vector3 = Vector3(0,-9.8,0)

func _ready() -> void:
	super()
	drop_equipment_input.connect(_try_drop_equipment)
	
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity_vector") *  ProjectSettings.get_setting("physics/3d/default_gravity")
	print("gravity ", gravity)
	
func _physics_process(_delta: float) -> void:
	if(current_throwable_state == EThrowableEquipmentState.Aiming):
		var pos : Vector3 = _determine_throw_target()
	
	if(drop_queued):
		_drop()
		drop_queued = false
		
	if(throw_queued):
		var reset_transform : Transform3D = owner.get_global_transform()
		player.equipment_manager._remove_equipment_from_slot(slot)
		owner.reparent(get_tree().root, true)
		owner.set_global_transform(reset_transform)
		
		rigid_body.set_linear_velocity(current_calculated_throw_velocity)
		rigid_body.set_angular_velocity(current_calculated_throw_velocity)
		throw_queued = false
		
func _throw_projectile_from_anim() -> void:
	throw_queued = true
	pass
		

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
		
func _on_unequipped():
	for hitbox in hitboxes:
		hitbox._set_collisions_enabled(true)

	for mesh in meshes:
		mesh.set_layer_mask_value(1,true)
		mesh.set_layer_mask_value(2,false)
	super()
	
func _try_use_equipment(_event : InputEvent) -> void:
	match current_throwable_state:
		EThrowableEquipmentState.Default:
			if(_can_enter_aiming_mode(_event)):
				_change_throwable_state(EThrowableEquipmentState.Aiming)
		EThrowableEquipmentState.Aiming:
			if(_can_currently_throw(_event)):
				_throw()
		_:
			pass
				
func _throw() -> void:
	_change_throwable_state(EThrowableEquipmentState.Throwing)
	throw_queued = true
	#get all capsules on the player and add them to collision exception list for x amount of time
	#if(rigid_body):
		#for shape in player._get_all_collision_shapes():
			#rigid_body.add_collision_exception_with(shape)


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
	var prev = current_throwable_state
	current_throwable_state = new_state
	
	match current_throwable_state:
		EThrowableEquipmentState.Default:
			if(input_receiver):
				input_receiver._change_current_input_mapping_context(InputReceiver.default_mapping_context_name ,self, true)
		EThrowableEquipmentState.Aiming:
			if(input_receiver):
				input_receiver._change_current_input_mapping_context(aiming_input_context_name ,self, true)
		EThrowableEquipmentState.Throwing:
			# when throwing actually happens, already hide existing prompts
			if(input_receiver):
				input_receiver._enable_current_HUD_actions(self, false)
	
	on_throwable_state_changed.emit(prev, new_state)		
	
func _drop() -> void:
	if(!_decide_target_transform_for_drop()):
		return
	
	var params : PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	params.motion = Vector3.UP * 0.01
	params.from = drop_transform
	
	player.equipment_manager._remove_equipment_from_slot(slot)
	owner.reparent(get_tree().root, true)
	owner.set_global_transform(drop_transform)

func _determine_throw_target() -> Vector3:
	#perform a raycast looking forward, distance determined by throwable settings
	var space_state: PhysicsDirectSpaceState3D = owner.get_world_3d().get_direct_space_state()

	var world_cam : Camera3D = player.player_cam
	var cam_pos : Vector3 = world_cam.get_global_position()
	var dir : Vector3 = -world_cam.get_global_basis().z
	var end : Vector3 = cam_pos + (dir.normalized() * _determine_throw_target_length())
	
	var query := PhysicsRayQueryParameters3D.create(player.player_cam.get_global_position(), end)
	query.collide_with_bodies = true
		
	var ray_hit : Dictionary  = space_state.intersect_ray(query)
	if (ray_hit):
		end = ray_hit.position
		DebugDraw3D.draw_sphere(end,0.1,Color.RED, 0)
	else:
		DebugDraw3D.draw_sphere(end,0.1,Color.GREEN, 0)
	
	var result : Array = TrajectoryLib.fixed_target(owner.get_global_position(),throw_velocity,end, gravity)

	if(!result.is_empty()):
		var points: Array = TrajectoryLib.samples(owner.get_global_position(),result[0].velocity,gravity,result[0].time, 15 )
		current_calculated_throw_velocity = result[0].velocity
		for id in points.size() -1:
			DebugDraw3D.draw_line(points[id].position,points[id+1].position,Color.BLUE,0)

	return end

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