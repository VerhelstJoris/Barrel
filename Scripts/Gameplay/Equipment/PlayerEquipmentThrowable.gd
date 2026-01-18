class_name PlayerEquipmentThrowable extends  PlayerEquipment

signal drop_equipment_input(event: InputEvent)
var drop_queued : bool = false
var drop_transform : Transform3D = Transform3D.IDENTITY

@export var rigid_body : CollisionPhysicsBody
@export var hitboxes : Array[HitboxComponent]

@export var meshes : Array[MeshInstance3D]
@export var collision_shape_for_drop_test : CollisionShape3D

enum EThrowableEquipmentState{ Default, Aiming, Throwing} 

var current_throwable_state : EThrowableEquipmentState = EThrowableEquipmentState.Default

func _ready() -> void:
	super()
	drop_equipment_input.connect(_try_drop_equipment)
	
func _physics_process(_delta: float) -> void:
	if(drop_queued):
		_drop()
		drop_queued = false

func _on_start_unholster():
	super()
	player.arms.arms_animation_bus.throwable_unholstered = true
	#if(input_receiver):
		#input_receiver._change_HUD_available_actions(input_receiver.input_dictionary.keys(), self)
		
func _on_start_holster():
	super()
	player.arms.arms_animation_bus.throwable_unholstered = false
	
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
		
func _on_unequipped():
	input_receiver.on_available_equipment_actions_cleared.emit(slot)
	player.arms.arms_animation_bus.throwable_unholstered = false
	
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
				player.arms.arms_animation_bus.throwable_aiming = true
				#enter aiming
				pass
		EThrowableEquipmentState.Aiming:
			if(_can_currently_throw(_event)):
				player.arms.arms_animation_bus.throwable_aiming = false
				#actually throw
				pass
				
func _can_enter_aiming_mode( _event : InputEvent) -> bool:
	if(_event.is_released()):
		return false
		
	return true	
		
func _can_currently_throw(_event : InputEvent) -> bool:
	if(_event.is_pressed()):
		return false
		
	return true	
	
func _try_drop_equipment(_event : InputEvent) -> void:
	match current_throwable_state:
		EThrowableEquipmentState.Default:
			drop_queued = true
		_:
			#exit out of aiming	
			pass
			
func _change_throwable_state( new_state : EThrowableEquipmentState) -> void:
	current_throwable_state = new_state
	
func _drop() -> void:
	if(!_decide_target_transform_for_drop()):
		return
	
	var params : PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	params.motion = Vector3.UP * 0.01
	params.from = drop_transform
	
	player.equipment_manager._remove_equipment_from_slot(slot)
	owner.reparent(get_tree().root, true)
	owner.set_global_transform(drop_transform)

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