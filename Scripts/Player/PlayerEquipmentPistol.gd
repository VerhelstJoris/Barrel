class_name PlayerEquipmentPistol extends PlayerEquipment

enum E_Pistol_State{ReadyToFire, HammerUncocked, Reloading}

@export_group("Equipment Input Details")
@export var reload_enter_input : EquipmentInputInfo
@export var reload_exit_input : EquipmentInputInfo
@export var reload_cycle_next_input : EquipmentInputInfo
@export var reload_cycle_prev_input : EquipmentInputInfo
@export var reload_insert_input : EquipmentInputInfo
@export var reload_eject_input : EquipmentInputInfo

@export var ready_state_input_details : Array[EquipmentInputInfo]
@export var reload_state_input_details : Array[EquipmentInputInfo]

@export_group("Pistol Details")
@export var bullet_scene: PackedScene

@onready var animation_bus : ColtAnimationBus = %AnimationTree
@onready var cylinder_bone_modifier: SkeletonRevolverCylinderModifier = %SkeletonRevolverCylinderModifier
@onready var bullet_attachment_point: Node3D = %BulletAttachmentPoint
@onready var bullet_reparent_point: Node3D = %BulletReparentPoint
@onready var cylinder_attachment: BoneAttachment3D = %CylinderAttachment

signal on_fire_action()
signal on_dry_fire_action()
signal on_cock_hammer_action(new_value)
signal change_reload_state(new_value)
signal reload_change_chamber(next)
signal reload_insert_shell()
signal reload_eject_shell()
signal bullet_spawned_for_inserting(new_bullet)

var CurrentState: E_Pistol_State = E_Pistol_State.HammerUncocked
var can_proceed_state: bool = true;

var current_bullets: Array[ColtBullet]
var current_chamber_id :int = 0
const chamber_amount: int = 6

var insert_chamber_id: int:
	get:
		return (current_chamber_id - 1 % chamber_amount)

#Animation stuff
const cock_hammer_animation : String = "AL_Colt_SAA/A_Colt_Cock_Hammer"
const enter_reload_animation : String = "AL_Colt_SAA/A_Colt_Enter_Reload"
const exit_reload_animation : String = "AL_Colt_SAA/A_Colt_Exit_Reload"
const reload_next_chamber_animation : String = "AL_Colt_SAA/A_Colt_Reload_Next_Chamber"
const reload_previous_chamber_animation : String = "AL_Colt_SAA/A_Colt_Reload_Previous_Chamber"
const reload_insert_shell_animation : String = "AL_Colt_SAA/A_Colt_Reload_Insert_Shell"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animation_bus._initialize(self)
	#can fire all rounds
	current_bullets.resize(chamber_amount)
	current_bullets.fill(null)
	CurrentState = E_Pistol_State.HammerUncocked
	_log_chamber_states()
	
		
func _input(event: InputEvent) -> void:
	super(event)
	if CurrentState == E_Pistol_State.Reloading:
		if event.is_action_pressed(reload_cycle_next_input.input_string):
			_try_reload_move_cylinder(true)
		elif event.is_action_pressed(reload_cycle_prev_input.input_string):
			_try_reload_move_cylinder(false)
		elif event.is_action_pressed(reload_exit_input.input_string):
			_try_reload()
	else:	
		if event.is_action_pressed(reload_enter_input.input_string):
			_try_reload()
			
func _try_use_equipment():
	if(CurrentState == E_Pistol_State.Reloading):
		if(_can_insert_round()):
			print("Inserting Shell")
			_enable_changing_states(false)
			reload_insert_shell.emit()
	else:
		if _can_shoot():
			print("shooting")
			_proceed_to_state(E_Pistol_State.HammerUncocked)
			if(current_bullets[current_chamber_id] != null && current_bullets[current_chamber_id]._can_be_fired()):
				on_fire_action.emit()
				current_bullets[current_chamber_id]._on_fired()
			else:
				on_dry_fire_action.emit()

		elif(_can_cock_hammer()):
			print("cocking hammer")
			_proceed_to_state(E_Pistol_State.ReadyToFire)
			on_cock_hammer_action.emit()
			
func _try_use_equipment_secondary():
	if(CurrentState == E_Pistol_State.Reloading):
		if(_can_try_eject()):
			print("Ejecting Shell")
			_enable_changing_states(false)
			reload_eject_shell.emit()
		
func _on_equipped():
	super()
	on_available_equipment_actions_changed.emit(ready_state_input_details)

func _try_reload():
	#if we're not already reloading, try to get into it
	if(CurrentState != E_Pistol_State.Reloading):
		if(_can_enter_reload()):
			_enter_reload_state()
	else:
		if(_can_exit_reload()):
			_exit_reload_state()
			

func _enter_reload_state() -> void:
		_proceed_to_state(E_Pistol_State.Reloading)
		change_reload_state.emit(true)
		on_available_equipment_actions_cleared.emit()
	
func _exit_reload_state() -> void:
		_proceed_to_state(E_Pistol_State.ReadyToFire)
		change_reload_state.emit(false)
		on_available_equipment_actions_cleared.emit()

func _try_reload_move_cylinder(next: bool) -> void:
	if(CurrentState != E_Pistol_State.Reloading):
		return
		
	if(!_can_proceed_state()):
		return

	can_proceed_state = false
	reload_change_chamber.emit(next)
	
func _proceed_to_state(new_state: E_Pistol_State) -> void:
	can_proceed_state = false
	CurrentState = new_state
	
func _increase_cylinder_rotations(amount : int) -> void:
	var to_add : int = amount %6
	cylinder_bone_modifier.increment_cylinder_rotations(to_add)
	current_chamber_id = (current_chamber_id + to_add)%6
	if(current_chamber_id < 0):
		current_chamber_id = 6 + current_chamber_id
	_log_chamber_states()


func _enable_changing_states(b_enabled : bool) -> void:
	can_proceed_state = b_enabled
	
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

func _can_proceed_state() -> bool:
	return can_proceed_state
	
func _can_insert_round() -> bool:
	print("Try inserting round")
	return CurrentState == E_Pistol_State.Reloading && _can_proceed_state() && current_bullets[insert_chamber_id] == null

func _can_try_eject() -> bool:
	print("Try ejecting shell")
	return CurrentState == E_Pistol_State.Reloading && _can_proceed_state()

func _can_enter_reload() -> bool:
	print("Try enter reload")
	return _can_proceed_state()
	
func _can_exit_reload() -> bool:
	print("Try exit reload")
	return _can_proceed_state() && CurrentState == E_Pistol_State.Reloading
	
func _can_cock_hammer() -> bool:
	print("Try cocking hammer")
	return CurrentState == E_Pistol_State.HammerUncocked && _can_proceed_state()

func _can_shoot() -> bool:
	print("Try shooting")
	return CurrentState == E_Pistol_State.ReadyToFire && _can_proceed_state()
	
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
