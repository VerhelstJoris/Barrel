class_name PlayerEquipmentPistol extends PlayerEquipment 

@export_group("Pistol Details")
@export var bullet_scene: PackedScene

@onready var animation_bus : ColtAnimationBus = %AnimationTree
@onready var bullet_attachment_point: Node3D = %BulletAttachmentPoint
@onready var bullet_reparent_point: Node3D = %BulletReparentPoint
@onready var cylinder_attachment: BoneAttachment3D = %CylinderAttachment

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

var current_state: EPistolState.State = EPistolState.State.HammerUncocked
var current_action : EPistolState.Actions = EPistolState.Actions.None:
	set(new):
		on_action_started.emit(new)
		current_action = new

var can_proceed_state: bool = true;
var can_interrupt_into_next_state: bool = false;

var current_bullets: Array[ColtBullet]
const chamber_amount: int = 6

var current_action_cylinder_rotations : int = 0
var current_chamber_id :int = 0
@export var fan_hammer_max_delay : float = 0.2
var main_equipment_last_use_time : float = 0

var insert_chamber_id: int:
	get:
		return (current_chamber_id - 1 % chamber_amount)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	current_bullets.resize(chamber_amount)
	current_bullets.fill(null)
	current_state = EPistolState.State.HammerUncocked
	
	on_try_insert_input.connect(_try_insert_round)
	on_try_eject_input.connect(_try_eject_round)
	on_try_cylinder_next_input.connect(_try_cylinder_next)
	on_try_cylinder_prev_input.connect(_try_cylinder_prev)
	on_try_enter_reload_input.connect(_try_enter_reload)
	on_try_exit_reload_input.connect(_try_exit_reload)
	
func _try_insert_round(_event : InputEvent) -> void:
	if(current_state == EPistolState.State.Reloading):
		if(_can_insert_round()):
			_start_new_action(EPistolState.Actions.Insert, current_state, 0)
			
func _try_eject_round(_event : InputEvent) -> void:
	if(current_state == EPistolState.State.Reloading):
		if(_can_eject_round()):
			_start_new_action( EPistolState.Actions.Eject, current_state, 0)
		
func _try_cylinder_next(_event : InputEvent) -> void:
	if(_can_reload_rotate_cylinder()):
		_start_new_action(EPistolState.Actions.CylinderNext, current_state, -1)
		
func _try_cylinder_prev(_event : InputEvent) -> void:
	if(_can_reload_rotate_cylinder()):
		_start_new_action(EPistolState.Actions.CylinderPrev, current_state, 1)
		
func _can_reload_rotate_cylinder() -> bool:
	if(current_state != EPistolState.State.Reloading):
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
	var current_time : float = Time.get_unix_time_from_system()
	if(main_equipment_last_use_time + fan_hammer_max_delay >= current_time):
		if(_can_fan_fire()):
			_start_new_action(EPistolState.Actions.FanFire, EPistolState.State.ReadyToFire, 0)

	if _can_shoot():
		if(current_bullets[current_chamber_id] != null && current_bullets[current_chamber_id]._can_be_fired()):
			_start_new_action(EPistolState.Actions.Fire, EPistolState.State.HammerUncocked, 0)
		else:
			_start_new_action(EPistolState.Actions.DryFire, EPistolState.State.HammerUncocked, 0)
	elif(_can_cock_hammer()):
		_start_new_action(EPistolState.Actions.CockHammer, EPistolState.State.ReadyToFire , 1)

	main_equipment_last_use_time = current_time



func _on_equipped():
	super()
	
func _enable_interrupting_action() -> void:
	can_interrupt_into_next_state = true
		
func _fire_current_bullet() -> void:
	on_fired.emit()
	if(current_bullets[current_chamber_id] != null):
		current_bullets[current_chamber_id]._on_fired()
	else:
		printerr("Tried to properly fire when therer was no bullet at ID: ", current_chamber_id)
	
func _enter_reload_state() -> void:
	var action : EPistolState.Actions = EPistolState.Actions.None
	if(current_state == EPistolState.State.HammerUncocked):
		action = EPistolState.Actions.EnterReload
	else:
		action = EPistolState.Actions.EnterReloadUncock

	_start_new_action( action, EPistolState.State.Reloading ,1)
	
func _exit_reload_state() -> void:
	_start_new_action( EPistolState.Actions.ExitReload, EPistolState.State.ReadyToFire, 0)
	
func _start_new_action(new_action: EPistolState.Actions, new_state: EPistolState.State, cylinder_rotations : int) -> void:
	if(can_interrupt_into_next_state):
		on_current_action_interrupted.emit(current_action, new_action)
	
	current_action = new_action
	can_interrupt_into_next_state = false
	can_proceed_state = false
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
	_log_chamber_states()

func _enable_changing_states(enabled : bool) -> void:
	can_proceed_state = enabled
	can_interrupt_into_next_state = false
	current_action = EPistolState.Actions.None
	
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

func _can_proceed_state(allow_interrupt : bool = false) -> bool:
	if allow_interrupt:
		return can_proceed_state || can_interrupt_into_next_state
	else:
		return can_proceed_state
	
func _can_insert_round() -> bool:
	return current_state == EPistolState.State.Reloading && _can_proceed_state(true) && current_bullets[insert_chamber_id] == null

func _can_eject_round() -> bool:
	return current_state == EPistolState.State.Reloading && _can_proceed_state(true)

func _can_enter_reload() -> bool:
	return _can_proceed_state(true) && current_state != EPistolState.State.Reloading
	
func _can_exit_reload() -> bool:
	return _can_proceed_state(true) && current_state == EPistolState.State.Reloading
	
func _can_cock_hammer() -> bool:
	return current_state == EPistolState.State.HammerUncocked && _can_proceed_state(true)

func _can_fan_fire() -> bool:
	#can fan the hammer if we're in the ready state or already fanning
	return _can_proceed_state(true) && current_state == EPistolState.State.ReadyToFire

func _can_shoot() -> bool:
	return current_state == EPistolState.State.ReadyToFire && _can_proceed_state(true)

func _can_be_holstered() -> bool:
	return (current_state == EPistolState.State.ReadyToFire || current_state == EPistolState.State.HammerUncocked) && _can_proceed_state(false)

func _log_chamber_states() -> void:
	var builtStr : String = ""
	var index: int =  0
	for bullet in current_bullets:
		var bcurrent : bool = (index == current_chamber_id)
		if bcurrent:
			builtStr+="(" 
		else:
			builtStr+="["
		
		if(bullet == null):
			builtStr+="0"
		else:
			if(bullet._can_be_fired()):
				builtStr+="1"
			else:
				builtStr+="X"
		
		if bcurrent:
			builtStr+=")"
		else:
			builtStr+="]"
		index +=1
	print(builtStr, " ", current_chamber_id)
