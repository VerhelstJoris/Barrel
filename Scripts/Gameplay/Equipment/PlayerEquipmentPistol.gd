class_name PlayerEquipmentPistol extends PlayerEquipment 

enum EPistolState {ReadyToFire, HammerUncocked, Reloading}

enum EPistolActions {None, Fire, DryFire, CockHammer, EnterReload, EnterReloadUncock, ExitReload, CylinderNext, CylinderPrev, Eject, Insert, FanFire}

@export_group("Pistol Details")
@export var bullet_scene: PackedScene

@export var on_hit_effect_dictionary : PhysicsMatDictionary

@export var animation_bus : ColtAnimationBus
@export var bullet_attachment_point: Node3D
@export var bullet_reparent_point: Node3D
@export var cylinder_attachment: BoneAttachment3D 
@export var muzzle_point : Node3D


signal on_try_insert_input(event: InputEvent)
signal on_try_eject_input(event: InputEvent)
signal on_try_cylinder_next_input(event : InputEvent)
signal on_try_cylinder_prev_input(event : InputEvent)
signal on_try_enter_reload_input(event : InputEvent)
signal on_try_exit_reload_input(event : InputEvent)

signal bullet_spawned_for_inserting(new_bullet)
signal on_action_started(new_action)
signal on_current_action_interrupted(current_action, new_action)
signal on_fired()

var current_state : EPistolState = EPistolState.HammerUncocked

var current_action : EPistolActions = EPistolActions.None:
	set(new):
		on_action_started.emit(new)
		current_action = new

var can_proceed_state: bool                      = true
var can_interrupt_into_next_state: bool = false
var can_interrupt_fire : bool = false
var queued_fire : bool = false

var fire_queued : bool = false

var current_bullets: Array[ColtBullet]
const chamber_amount: int = 6

var current_action_cylinder_rotations : int = 0
var current_chamber_id :int = 0
@export var fan_hammer_max_delay : float = 0.2
var main_equipment_last_use_time : float = 0

@export var raycast_dist : float = 1500
@export var base_damage : float = 100

const reloading_input_context_name : String = "Reloading"

var DEBUG_always_fire : bool = false

var insert_chamber_id: int:
	get:
		return (current_chamber_id - 1 % chamber_amount)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	current_bullets.resize(chamber_amount)
	current_bullets.fill(null)
	current_state = EPistolState.HammerUncocked
	
	on_try_insert_input.connect(_try_insert_round)
	on_try_eject_input.connect(_try_eject_round)
	on_try_cylinder_next_input.connect(_try_cylinder_next)
	on_try_cylinder_prev_input.connect(_try_cylinder_prev)
	on_try_enter_reload_input.connect(_try_enter_reload)
	on_try_exit_reload_input.connect(_try_exit_reload)
	
	if(bullet_scene == null):
		push_error("No Bullet Scene Assigned on Colt!")

	if(on_hit_effect_dictionary == null):
		push_error("No Hit VFX Dictionary Assigned on Colt!")

func _physics_process(_delta: float) -> void:
	if(fire_queued):
		fire_queued = false
		_physics_fire_current_bullet()

func _try_insert_round(_event : InputEvent) -> void:
	if(current_state == EPistolState.Reloading):
		if(_can_insert_round()):
			_start_new_action(EPistolActions.Insert, current_state, 0)
			
func _try_eject_round(_event : InputEvent) -> void:
	if(current_state == EPistolState.Reloading):
		if(_can_eject_round()):
			_start_new_action( EPistolActions.Eject, current_state, 0)
		
func _try_cylinder_next(_event : InputEvent) -> void:
	if(_can_reload_rotate_cylinder()):
		_start_new_action(EPistolActions.CylinderNext, current_state, -1)
		
func _try_cylinder_prev(_event : InputEvent) -> void:
	if(_can_reload_rotate_cylinder()):
		_start_new_action(EPistolActions.CylinderPrev, current_state, 1)
		
func _can_reload_rotate_cylinder() -> bool:
	if(current_state != EPistolState.Reloading):
		return false

	if(!_can_proceed_state(true)):
		return false
		
	return true	

func _try_enter_reload(_event : InputEvent) -> void:
	if(_can_enter_reload()):
		_enter_reload_state()
		
func _try_exit_reload(_event : InputEvent) -> void:
	if(_can_exit_reload()):
		_exit_reload_state()	

func _try_use_equipment(_event : InputEvent) -> void:
	# only care about the press, not the release
	if(_event.is_released()):
		return
		
	var started_action : bool = false
	var current_time : float = Time.get_unix_time_from_system()
	var within_fan_time_margin : bool = current_time - main_equipment_last_use_time <= fan_hammer_max_delay
	if( within_fan_time_margin):
		if(_can_fan_fire()):
			_start_new_action(EPistolActions.FanFire, EPistolState.ReadyToFire, 0)
			started_action = true
	
	if(!started_action):
		if _can_shoot():
			if((current_bullets[current_chamber_id] != null && current_bullets[current_chamber_id]._can_be_fired())|| DEBUG_always_fire):
				_start_new_action(EPistolActions.Fire, EPistolState.HammerUncocked, 0)
			else:
				_start_new_action(EPistolActions.DryFire, EPistolState.HammerUncocked, 0)
			started_action = true
		elif(_can_cock_hammer()):
			_start_new_action(EPistolActions.CockHammer, EPistolState.ReadyToFire , 1)
			started_action = true

	if(!started_action && within_fan_time_margin):
		queued_fire = true
	else:
		main_equipment_last_use_time = current_time
		
#used as anim notify	
func _enable_interrupting_action() -> void:
	can_interrupt_into_next_state = true
	if(queued_fire && player.equipment_manager._can_enter_two_handed_action(slot)):
		_start_new_action(EPistolActions.FanFire, EPistolState.ReadyToFire, 0)

#used as anim notify		
func _enable_interrupting_for_next_fire() -> void:
	can_interrupt_fire = true
	if(queued_fire && player.equipment_manager._can_enter_two_handed_action(slot)):
		_start_new_action(EPistolActions.FanFire, EPistolState.ReadyToFire, 0)

#used as anim notify
func _fire_current_bullet() -> void:
	fire_queued = true
	
#region Firing	
func _physics_fire_current_bullet() -> void:
	var valid_bullet : bool = current_bullets[current_chamber_id] != null && current_bullets[current_chamber_id]._can_be_fired()
	if(valid_bullet || DEBUG_always_fire):
		if(valid_bullet):
			current_bullets[current_chamber_id]._on_fired()
		on_fired.emit()
		_damage_target(_find_target_hit())
		
func _find_target_hit() -> Dictionary:
	var world_cam : Camera3D = player.player_cam
	var cam_pos : Vector3 = world_cam.get_global_position()
	var dir : Vector3 = -world_cam.get_global_basis().z
	var end : Vector3 = cam_pos + (dir.normalized() * raycast_dist)

	#first perform a raycast from the camera center straight forward
	var inital_hit : Dictionary = _ray_for_hit_target(cam_pos, end)

	if inital_hit:
		end = inital_hit.position

	# now perform a ray from the muzzle position towards that position
	var second_hit : Dictionary = _ray_for_hit_target(muzzle_point.global_position, end)
	if second_hit:
		return second_hit
		
	if(inital_hit):
		return inital_hit
	
	var dict : Dictionary	
	return dict

func _ray_for_hit_target(origin :Vector3 , end :Vector3 ) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = owner.get_world_3d().get_direct_space_state()

	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collide_with_bodies = true

	return space_state.intersect_ray(query)	

func _damage_target(hit : Dictionary) -> void:
	if(!hit):
		return
		
	if hit.collider.has_user_signal(HitboxComponent.damaged_signal_name):
		hit.collider.emit_signal(HitboxComponent.damaged_signal_name, hit, _calculate_damage(hit))
		
	_spawn_on_hit_vfx(hit)
		
func _spawn_on_hit_vfx(hit : Dictionary) -> void:
	var hit_body : PhysicsBody3D = hit.collider as PhysicsBody3D
	var scene_found : PackedScene = on_hit_effect_dictionary._find_scene_from_physicsbody(hit_body)

	if(scene_found):
		var created_effect : VFXInstance = scene_found.instantiate()
		get_tree().root.add_child(created_effect)
		created_effect.set_global_position(hit.position)
		created_effect.quaternion = Quaternion(Vector3.UP, hit.normal)
		
func _calculate_damage(_hit : Dictionary) -> float:
	return base_damage
#endregion

func _enter_reload_state() -> void:
	var action : EPistolActions = EPistolActions.None
	if(current_state == EPistolState.HammerUncocked):
		action = EPistolActions.EnterReload
	else:
		action = EPistolActions.EnterReloadUncock
	
	if(input_receiver):
		input_receiver._change_current_input_mapping_context(reloading_input_context_name,self , false)
		input_receiver._enable_current_HUD_actions(self, false)

	_start_new_action( action, EPistolState.Reloading ,1)
	
func _exit_reload_state() -> void:
	if(input_receiver):
		input_receiver._change_current_input_mapping_context(InputReceiver.default_mapping_context_name,self , false)
		input_receiver._enable_current_HUD_actions(self, false)


	_start_new_action( EPistolActions.ExitReload, EPistolState.ReadyToFire, 0)
	
func _start_new_action(new_action: EPistolActions, new_state: EPistolState, cylinder_rotations : int) -> void:
	if(can_interrupt_into_next_state):
		on_current_action_interrupted.emit(current_action, new_action)
	
	current_action = new_action
	can_interrupt_into_next_state = false
	can_interrupt_fire = false
	can_proceed_state = false
	queued_fire = false
	current_state = new_state
	_update_action_cylinder_increment_amount(cylinder_rotations)

func _update_action_cylinder_increment_amount(cylinder_rotations : int) -> void:
	current_action_cylinder_rotations = cylinder_rotations
	_increase_cylinder_rotations(current_action_cylinder_rotations)
	
func _increase_cylinder_rotations(amount : int) -> void:
	var to_add : int = amount % chamber_amount
	current_chamber_id = (current_chamber_id + to_add) % chamber_amount
	if(current_chamber_id < 0):
		current_chamber_id = chamber_amount + current_chamber_id

func _enable_changing_states(enabled : bool) -> void:
	can_proceed_state = enabled
	can_interrupt_into_next_state = false
	can_interrupt_fire = false
	_on_previous_action_finished(current_action)
	current_action = EPistolActions.None
	
func _on_previous_action_finished(action: EPistolActions)-> void:
	match action:
		EPistolActions.EnterReload, EPistolActions.EnterReloadUncock, EPistolActions.ExitReload:
			if(input_receiver):
				input_receiver._enable_current_HUD_actions(self, true)
		_:
			pass
	
func _spawn_bullet_for_chamber() -> void:
	if(bullet_scene.can_instantiate()):
		var new_bullet: ColtBullet = bullet_scene.instantiate()
		bullet_spawned_for_inserting.emit(new_bullet)
		current_bullets[insert_chamber_id] = new_bullet
	
func _reparent_bullet_to_ejector() -> void:		
	if(current_bullets[insert_chamber_id] != null):
		current_bullets[insert_chamber_id].reparent(bullet_attachment_point,true)
		current_bullets[insert_chamber_id].set_global_transform(bullet_reparent_point.get_global_transform())
	
func _on_insert_finished() -> void:
	current_bullets[insert_chamber_id].reparent(bullet_reparent_point,true)
	current_bullets[insert_chamber_id].set_global_transform(bullet_reparent_point.get_global_transform())
	current_bullets[insert_chamber_id].reparent(cylinder_attachment,true)

func _delete_bullet_from_chamber()-> void:
	if(current_bullets[insert_chamber_id] != null):
		current_bullets[insert_chamber_id].queue_free()
		current_bullets[insert_chamber_id] = null
	
func _can_current_bullet_fire() -> bool:
	if(current_bullets[insert_chamber_id] != null):
		return current_bullets[insert_chamber_id]._can_be_fired()
	return false

func _can_proceed_state(allow_general_interrupt : bool = false, allow_interrupt_fire : bool = false) -> bool:
	var ret : bool = can_proceed_state
	
	if(allow_interrupt_fire):
		ret = ret || can_interrupt_fire
	if allow_general_interrupt:
		ret = ret || can_interrupt_into_next_state
		
	return ret	
	
func _can_insert_round() -> bool:
	return current_state == EPistolState.Reloading && _can_proceed_state(true) && current_bullets[insert_chamber_id] == null

func _can_eject_round() -> bool:
	return current_state == EPistolState.Reloading && _can_proceed_state(true)

func _can_enter_reload() -> bool:
	return _can_proceed_state(true) && current_state != EPistolState.Reloading && player.equipment_manager._can_enter_two_handed_action(slot)
	
func _can_exit_reload() -> bool:
	return _can_proceed_state(true) && current_state == EPistolState.Reloading
	
func _can_cock_hammer() -> bool:
	return current_state == EPistolState.HammerUncocked && _can_proceed_state(true)

func _can_fan_fire() -> bool:
	#can fan the hammer if we're in the ready state or already fanning
	return _can_proceed_state(true, true) && (current_state == EPistolState.ReadyToFire || current_state == EPistolState.HammerUncocked) && player.equipment_manager._can_enter_two_handed_action(slot)

func _can_shoot() -> bool:
	return current_state == EPistolState.ReadyToFire && _can_proceed_state(true)

func _can_be_holstered() -> bool:
	return (current_state == EPistolState.ReadyToFire || current_state == EPistolState.HammerUncocked) && _can_proceed_state(false)
	
func _on_start_holster():
	super()
	player.arms.arms_animation_bus.colt_unholstered = false
	if(input_receiver):
		input_receiver._change_HUD_available_actions([],self)
		
func _on_start_unholster():
	super()
	player.arms.arms_animation_bus.colt_unholstered = true
	if(input_receiver):
		input_receiver._change_current_input_mapping_context(InputReceiver.default_mapping_context_name,self)
		
func _is_currently_using_both_hands() -> bool:
	return _is_two_handed_action(current_action)

func _is_two_handed_action(action : EPistolActions) -> bool:
	match action:
		EPistolActions.EnterReload, EPistolActions.EnterReloadUncock, EPistolActions.CylinderNext, EPistolActions.CylinderPrev,	EPistolActions.Insert,EPistolActions.Eject,	EPistolActions.ExitReload, EPistolActions.FanFire:
			return true
		_:
			pass
	
	if(current_state == EPistolState.Reloading):
		return true
		
	return false	