class_name PlayerEquipmentThrowable extends  PlayerEquipment

signal drop_equipment_input(event: InputEvent)

@export var rigid_body : CollisionPhysicsBody
@export var hitboxes : Array[HitboxComponent]

@export var meshes : Array[MeshInstance3D]

const distance_to_drop_to : float = 1.0

enum EThrowableEquipmentState{ Default, Aiming, Throwing} 

var current_throwable_state : EThrowableEquipmentState = EThrowableEquipmentState.Default

func _ready() -> void:
	super()
	drop_equipment_input.connect(_try_drop_equipment)
	
func _on_start_unholster():
	super()
	player.arms.arms_animation_bus.throwable_unholstered = true
	if(input_receiver):
		input_receiver._change_HUD_available_actions(input_receiver.input_dictionary.keys(), self)
		
func _on_start_holster():
	super()
	player.arms.arms_animation_bus.throwable_unholstered = false
	

func _can_be_holstered() -> bool:
	return false
	
func _on_equipped(_player : Player) -> void:
	super(_player)
	if(rigid_body):
		rigid_body.set_transform(Transform3D.IDENTITY)
		
	for hitbox in hitboxes:
		hitbox._set_collisions_enabled(false)
		
	for mesh in meshes:
		mesh.set_layer_mask_value(1,false)
		mesh.set_layer_mask_value(2,true)
		
func _on_unequipped():
	super()
	
	input_receiver.on_available_equipment_actions_cleared.emit(slot)
	player.arms.arms_animation_bus.throwable_unholstered = false
	
	for hitbox in hitboxes:
		hitbox._set_collisions_enabled(true)

	for mesh in meshes:
		mesh.set_layer_mask_value(1,true)
		mesh.set_layer_mask_value(2,false)

func _try_use_equipment(_event : InputEvent) -> void:
	match current_throwable_state:
		EThrowableEquipmentState.Default:
			if(_can_enter_aiming_mode(_event)):
				#enter aiming
				pass
		EThrowableEquipmentState.Aiming:
			if(_can_currently_throw(_event)):
				#actually throw
				pass


	print("Try Use throwable")

func _can_enter_aiming_mode( _event : InputEvent) -> bool:
	if(_event.is_released()):
		return false
		
	return true	
		
func _can_currently_throw(_event : InputEvent) -> bool:
	if(_event.is_pressed()):
		return false
		
	return true	
	
func _can_currently_drop(_event : InputEvent) -> bool:
	if(_event.is_pressed() && Input.is_action_just_pressed(_event.get_name())):
		return true
		
	return false	

func _try_drop_equipment(_event : InputEvent) -> void:
	match current_throwable_state:
		EThrowableEquipmentState.Default:
			if(_can_currently_drop):
				_drop()
		_:
			#exit out of aiming	
			pass
	
	
func _change_throwable_state( new_state : EThrowableEquipmentState) -> void:
	current_throwable_state = new_state
	
func _drop() -> void:
	print("DROP")
	player.equipment_manager._remove_equipment_from_slot(slot)
	self.reparent(get_tree().root, true)
	set_global_transform(_decide_target_transform_for_drop())
	
func _decide_target_transform_for_drop() -> Transform3D:
	var new_transform : Transform3D = Transform3D.IDENTITY

	# if the player's interactor raycast has hit something, put it there based on the normal of the hit
	if(player.interactor.interact_ray.is_colliding()):
		new_transform.origin = player.interactor.interact_ray.get_collision_point()
	else:
		#else just put it at the end of the interactor ray
		new_transform.origin = player.interactor.interact_ray.get_global_position() + (player.interactor.interact_ray.get_global_rotation() * player.interactor.interact_ray.get_target_position())
		pass
	
	return new_transform