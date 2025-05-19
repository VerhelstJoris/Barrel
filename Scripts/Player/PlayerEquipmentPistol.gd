class_name PlayerEquipmentPistol extends "PlayerEquipment.gd"

enum E_Pistol_State{ReadyToFire, HammerUncocked, Reloading}
enum E_chamber_state{Empty, Ready, Fired}

@export_group("Equipment Input Details")
@export var ENTER_RELOAD: String = "enter_reload"
@export var RELOAD_NEXT_CHAMBER: String = "enter_reload"
@export var RELOAD_PREV_CHAMBER: String = "enter_reload"

@export_group("Pistol Details")
@export var bullet_scene: PackedScene


@onready var cylinder_bone_modifier: SkeletonRevolverCylinderModifier = %SkeletonRevolverCylinderModifier
@onready var bullet_attachment_point: Node3D = %BulletAttachmentPoint
@onready var bullet_reparent_point: Node3D = %BulletReparentPoint
@onready var cylinder_attachment: BoneAttachment3D = %CylinderAttachment

signal update_fire_action(new_value)
signal update_hammer_action(new_value)
signal change_reload_state(new_value)
signal reload_change_chamber(next)
signal reload_insert_shell()
signal reload_eject_shell()
signal bullet_spawned_for_inserting(new_bullet)

const log_pistol : String = "PlayerPistol" 
const anim_enter_reload_condition : String = "parameters/conditions/enter_reload"


var start_reload: bool = true;
var CurrentState: E_Pistol_State = E_Pistol_State.HammerUncocked
var can_proceed_state: bool = true;

var ChamberStates : Array[E_chamber_state]
var current_bullets: Array[Node3D]
var current_chamber_id :int = 0
const chamber_amount: int = 6

var temp_bullet

#Animation stuff
const cock_hammer_animation : String = "AL_Colt_SAA/A_Colt_Cock_Hammer"
const enter_reload_animation : String = "AL_Colt_SAA/A_Colt_Enter_Reload"
const reload_next_chamber_animation : String = "AL_Colt_SAA/A_Colt_Reload_Next_Chamber"
const reload_previous_chamber_animation : String = "AL_Colt_SAA/A_Colt_Reload_Previous_Chamber"
const reload_insert_shell_animation : String = "AL_Colt_SAA/A_Colt_Reload_Insert_Shell"

const anim_fire_request : String = "parameters/FireOneShot/request"
const anim_hammer_request : String = "parameters/HammerOneShot/request"
const anim_enter_reload_request : String = "parameters/EnterReloadOneShot/request"
const anim_reload_next_chamber_request : String = "parameters/NextChamberOneShot/request"
const anim_reload_previous_chamber_request : String = "parameters/PreviousChamberOneShot/request"
const anim_reload_insert_shell_request : String = "parameters/InsertShellOneShot/request"
const anim_reload_eject_shell_request : String = "parameters/EjectShellOneShot/request"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	anim_tree.animation_finished.connect(_on_animation_finished)
	#can fire all rounds
	ChamberStates.resize(chamber_amount)
	ChamberStates.fill(E_chamber_state.Empty)
	current_bullets.resize(chamber_amount)
	CurrentState = E_Pistol_State.HammerUncocked
	_log_chamber_states()
	

func _physics_process(_delta: float):
	super(_delta)

	if Input.is_action_just_pressed(ENTER_RELOAD):
		_try_reload()
	elif Input.is_action_just_pressed(RELOAD_NEXT_CHAMBER):
		_try_reload_move_cylinder(true)
	elif Input.is_action_just_pressed(RELOAD_PREV_CHAMBER):
		_try_reload_move_cylinder(false)

func _try_use_equipment():
	if(CurrentState == E_Pistol_State.Reloading):
		if(_can_insert_round()):
			print("Inserting Shell")
			_enable_changing_states(false)
			anim_tree.set(anim_reload_insert_shell_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			reload_insert_shell.emit()
	else:
		if _can_shoot():
			print("shooting")
			_proceed_to_state(E_Pistol_State.HammerUncocked)
			anim_tree.set(anim_fire_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			update_fire_action.emit()
		elif(_can_cock_hammer()):
			print("cocking hammer")
			_proceed_to_state(E_Pistol_State.ReadyToFire)
			anim_tree.set(anim_hammer_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			update_hammer_action.emit()
			
func _try_use_equipment_secondary():
	if(CurrentState == E_Pistol_State.Reloading):
		if(_can_try_eject()):
			print("Ejecting Shell")
			_enable_changing_states(false)
			#_reparent_bullet_to_ejector()
			anim_tree.set(anim_reload_eject_shell_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			reload_eject_shell.emit()
		
func _try_reload():
	#if we're not already reloading, try to get into it
	if(CurrentState != E_Pistol_State.Reloading):
		if(_can_enter_reload()):
			print("start reload")
			_proceed_to_state(E_Pistol_State.Reloading)
			change_reload_state.emit(true)
			anim_tree.set(anim_enter_reload_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		if(_can_exit_reload()):
			print("exit reload")
			_proceed_to_state(E_Pistol_State.HammerUncocked)
		
func _try_reload_move_cylinder(next: bool) -> void:
	if(CurrentState != E_Pistol_State.Reloading):
		return
		
	if(!_can_proceed_state()):
		return

	can_proceed_state = false
	print("try move cylinder")	
	reload_change_chamber.emit(next)

	if(next):
		anim_tree.set(anim_reload_next_chamber_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		anim_tree.set(anim_reload_previous_chamber_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)



func _on_animation_finished(animation_name : String) -> void:
	print(animation_name)
	_enable_changing_states(true)
	match animation_name:
		cock_hammer_animation:
			_increase_cylinder_rotations(1)
		reload_previous_chamber_animation:
			_increase_cylinder_rotations(1)
		reload_next_chamber_animation:
			_increase_cylinder_rotations(-1)
			
			
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
		print("Spawning bullet")
		var new_bullet: Node3D = bullet_scene.instantiate()
		bullet_spawned_for_inserting.emit(new_bullet)
		current_bullets[current_chamber_id] = new_bullet
		ChamberStates[current_chamber_id] = E_chamber_state.Ready
	
func _reparent_bullet_to_ejector() -> void:		
	print("reparent to ejector")
	current_bullets[current_chamber_id].reparent(bullet_attachment_point,true)
	current_bullets[current_chamber_id].set_global_transform(bullet_reparent_point.get_global_transform())


func _on_insert_finished() -> void:
	print("insert finished")
	current_bullets[current_chamber_id].reparent(bullet_reparent_point,true)
	current_bullets[current_chamber_id].set_global_transform(bullet_reparent_point.get_global_transform())
	current_bullets[current_chamber_id].reparent(cylinder_attachment,true)


func _delete_bullet_from_chamber()-> void:
	current_bullets[current_chamber_id].queue_free()
	current_bullets[current_chamber_id] = null
	ChamberStates[current_chamber_id] = E_chamber_state.Empty
	
func _can_proceed_state() -> bool:
	return can_proceed_state
	
func _can_insert_round() -> bool:
	print("Try inserting round")
	return CurrentState == E_Pistol_State.Reloading && _can_proceed_state() && ChamberStates[current_chamber_id] == E_chamber_state.Empty

func _can_try_eject() -> bool:
	print("Try ejecting shell")
	return CurrentState == E_Pistol_State.Reloading && _can_proceed_state() && ChamberStates[current_chamber_id] != E_chamber_state.Empty

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
	for chamber in ChamberStates:
		var bcurrent : bool = (index == current_chamber_id)
		if bcurrent:
			builtStr+="(" 
		else:
			builtStr+="["
		match chamber:
			E_chamber_state.Ready:
				builtStr+="1"
			E_chamber_state.Empty:
				builtStr+="0"
			E_chamber_state.Fired:
				builtStr+="X"
		if bcurrent:
			builtStr+=")"
		else:
			builtStr+="]"
		index +=1
	print(builtStr, " ", current_chamber_id)
