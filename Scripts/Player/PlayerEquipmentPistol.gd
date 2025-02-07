class_name PlayerEquipmentPistol extends "PlayerEquipment.gd"

enum E_Pistol_State{ReadyToFire, HammerUncocked, Reloading}
enum E_chamber_state{Empty, Ready, Fired}

@export_group("Equipment Input Details")
@export var ENTER_RELOAD: String = "enter_reload"

@export_group("Pistol Details")
@export var bullet_scene: PackedScene


@onready var cylinder_bone_modifier: SkeletonRevolverCylinderModifier = %SkeletonRevolverCylinderModifier
@onready var bullet_attachment_point: Node3D = %BulletAttachmentPoint
@onready var cylinder_attachment: BoneAttachment3D = %CylinderAttachment


const log_pistol : String = "PlayerPistol" 
const anim_fire_condition : String = "parameters/conditions/try_fire"
const anim_pull_hammer_condition : String = "parameters/conditions/try_pull_hammer"
const anim_enter_reload_condition : String = "parameters/conditions/enter_reload"
const anim_exit_reload_condition : String = "parameters/conditions/exit_reload"
const anim_eject_condition : String = "parameters/conditions/eject_shell"
const anim_insert_round_condition : String = "parameters/conditions/insert_round"


var start_reload: bool = true;
var CurrentState: E_Pistol_State = E_Pistol_State.HammerUncocked
var can_proceed_state: bool = true;
var cylinder_is_rotating: bool = false;

var ChamberStates : Array[E_chamber_state]
var current_bullets: Array[Node3D]
var current_chamber :int = 0
const chamber_amount: int = 6

var temp_bullet

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	cylinder_bone_modifier.finished_rotating.connect(_cylinder_finished_rotating)
	#can fire all rounds
	ChamberStates.resize(chamber_amount)
	ChamberStates.fill(E_chamber_state.Empty)
	current_bullets.resize(chamber_amount)
	_log_chamber_states()
	pass # Replace with function body.

func _physics_process(_delta: float):
	super(_delta)
	if Input.is_action_just_pressed(ENTER_RELOAD):
		_try_reload()


func _try_use_equipment():
	if(CurrentState == E_Pistol_State.Reloading):
		if(_can_insert_round()):
			print("Inserting Shell")
			_enable_changing_states(false)
			anim_tree[anim_insert_round_condition] = true
	else:
		if _can_shoot():
			print("shooting")
			_proceed_to_state(E_Pistol_State.HammerUncocked)
			anim_tree[anim_fire_condition] = true
		elif(_can_cock_hammer()):
			print("cocking hammer")
			_proceed_to_state(E_Pistol_State.ReadyToFire)
			anim_tree[anim_pull_hammer_condition] = true
			
func _try_use_equipment_secondary():
	if(CurrentState == E_Pistol_State.Reloading):
		if(_can_try_eject()):
			print("Ejecting Shell")
			anim_tree[anim_eject_condition] = true
			can_proceed_state = false
		
func _try_reload():
	#if we're not already reloading, try to get into it
	if(CurrentState != E_Pistol_State.Reloading):
		if(_can_enter_reload()):
			print("start reload")
			_proceed_to_state(E_Pistol_State.Reloading)
			anim_tree[anim_enter_reload_condition] = true
	else:
		if(_can_exit_reload()):
			print("exit reload")
			_proceed_to_state(E_Pistol_State.HammerUncocked)
			anim_tree[anim_exit_reload_condition] = true
		

func _proceed_to_state(new_state: E_Pistol_State) -> void:
	can_proceed_state = false
	CurrentState = new_state
	

func _enable_changing_states(b_enabled : bool) -> void:
	#reset animation variables
	anim_tree[anim_fire_condition] = false
	anim_tree[anim_pull_hammer_condition] = false
	anim_tree[anim_eject_condition] = false
	anim_tree[anim_enter_reload_condition] = false
	anim_tree[anim_exit_reload_condition] = false
	anim_tree[anim_insert_round_condition] = false
	can_proceed_state = b_enabled
	
	
func _spawn_bullet_for_chamber() -> void:
	if(bullet_scene.can_instantiate()):
		print("Spawning bullet")
		var new_bullet: Node3D = bullet_scene.instantiate()
		bullet_attachment_point.add_child(new_bullet)
		current_bullets[current_chamber] = new_bullet
		ChamberStates[current_chamber] = E_chamber_state.Ready
		
	
func _reparent_new_bullet_to_cylinder() -> void:
	var old_transform: Transform3D = current_bullets[current_chamber].global_transform
	bullet_attachment_point.remove_child(current_bullets[current_chamber])
	cylinder_attachment.add_child(current_bullets[current_chamber])
	current_bullets[current_chamber].global_transform = old_transform
	pass
	
func _rotate_cylinder_over_time(_chamber_amount : int, time:float, curve: Curve)->void:
	cylinder_bone_modifier._rotate_over_time(_chamber_amount * 60, time, curve)
	cylinder_is_rotating=true

func _cylinder_finished_rotating(_rotated: float) -> void:
	cylinder_is_rotating = false
	var chambers_rotated: int = _rotated / 60
	current_chamber = (current_chamber + chambers_rotated) % chamber_amount
	_log_chamber_states()

func _can_proceed_state() -> bool:
	return can_proceed_state && !cylinder_is_rotating
	
func _can_insert_round() -> bool:
	print("try inserting round")
	return CurrentState == E_Pistol_State.Reloading && _can_proceed_state() && ChamberStates[current_chamber] == E_chamber_state.Empty

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
	print("try shooting")
	return CurrentState == E_Pistol_State.ReadyToFire && _can_proceed_state()
	
func _log_chamber_states() -> void:
	var builtStr : String = ""
	var index: int =  0
	for chamber in ChamberStates:
		var bcurrent : bool = (index == current_chamber)
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
	print(builtStr)
