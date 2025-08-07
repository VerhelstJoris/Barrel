class_name FPArmsAnimationBus extends Node

@onready var anim_tree : AnimationTree = %AnimationTree
@onready var pistol : PlayerEquipmentPistol = %FP_Colt

@onready var global_prop_bone : BoneAttachment3D = %GlobalPropBone
@onready var left_prop_bone : BoneAttachment3D = %LPropBone
@onready var right_prop_bone : BoneAttachment3D = %RPropBone

enum E_prop_bone_type{Left, Right, Global}
var right_prop_bone_pos : Vector3 = Vector3.ZERO

const anim_colt_state_machine_path : String  = "parameters/SM_Player/SM_Colt/"

const anim_fire_request : String = "ReadyBlendTree/FireOneShot/request"
const anim_dry_fire_request : String = "ReadyBlendTree/DryFireOneShot/request"
const anim_hammer_request : String = "ReadyBlendTree/HammerOneShot/request"

const anim_enter_reload_condition : String = "conditions/enter_reload"
const anim_exit_reload_condition : String = "conditions/exit_reload"

const anim_enter_reload_uncock_request : String = "EnterReloadBT/EnterUncockOneShot/request"
const anim_enter_reload_request : String = "EnterReloadBT/EnterReloadOneShot/request"
const anim_reload_next_chamber_request : String = "ReloadingBlendTree/NextChamberOneShot/request"
const anim_reload_next_chamber_cont_request : String = "ReloadingBlendTree/NextChamberContOneShot/request"
const anim_reload_previous_chamber_request : String = "ReloadingBlendTree/PreviousChamberOneShot/request"
const anim_reload_previous_chamber_cont_request : String = "ReloadingBlendTree/PreviousChamberContOneShot/request"
const anim_reload_insert_shell_request : String = "ReloadingBlendTree/InsertShellOneShot/request"
const anim_reload_eject_shell_request : String = "ReloadingBlendTree/EjectShellOneShot/request"

const anim_movement_blend : String = "parameters/MoveBlendSpace/blend_position"
const reload_movement_blend_value : float = 0.1


# these variables are checked by the state machine itself as an expression
var enter_reload_done : bool = false
var exit_reload_done : bool = false
var colt_unholstered : bool = false
var colt_fan_hammer : bool = false

var current_action : EPistolState.Actions = EPistolState.Actions.None

var anim_move_blend_add_amount : String = "parameters/MoveBlendAdd/add_amount"
var movement_blend_value : Vector2 = Vector2.ZERO
var prev_move_direction : Vector2 = Vector2.ZERO
var move_blend_tween : Tween

var next_cyl_cont : bool = false
var prev_cyl_cont : bool = false

signal on_unholster_anim_finish()
signal on_holster_anim_finish()

var prev_delta : float = 0
#deltatime to forever blend towards the movement we're doing
const movement_blend_rate : float = 4

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pistol.on_action_started.connect(_on_action_started)
	pistol.on_current_action_interrupted.connect(_on_action_interrupted)
	pistol.bullet_spawned_for_inserting.connect(_on_bullet_spawned_for_inserting)
	right_prop_bone_pos = pistol.get_position()
	
func _init_player_data(player : Player) -> void:
	player.player_movement_input.connect(_on_player_movement_input)
	player.on_holster_started.connect(_on_player_holster_started)
	player.on_unholster_started.connect(_on_player_unholster_started)

func _set_anim_tree_oneshot_request(request_name):
	set( anim_colt_state_machine_path + request_name, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _on_action_started(new_action : EPistolState.Actions) -> void:
	_finish_prev_action()
	match new_action:
		EPistolState.Actions.Fire:
			_set_anim_tree_oneshot_request(anim_fire_request)
		EPistolState.Actions.DryFire:
			_set_anim_tree_oneshot_request(anim_dry_fire_request)
		EPistolState.Actions.CockHammer:
			_set_anim_tree_oneshot_request(anim_hammer_request)
		EPistolState.Actions.EnterReload:
			_on_reload_change(true,false,false)
		EPistolState.Actions.EnterReloadUncock:
			_on_reload_change(false,true,false)
		EPistolState.Actions.ExitReload:
			_on_reload_change(false,false,true)
		EPistolState.Actions.CylinderNext:
			if(next_cyl_cont):
				_set_anim_tree_oneshot_request(anim_reload_next_chamber_cont_request)
				next_cyl_cont = false
			else:		
				_set_anim_tree_oneshot_request(anim_reload_next_chamber_request)
		EPistolState.Actions.CylinderPrev:
			if(prev_cyl_cont):
				_set_anim_tree_oneshot_request(anim_reload_previous_chamber_cont_request)
				prev_cyl_cont = false
			else:
				_set_anim_tree_oneshot_request(anim_reload_previous_chamber_request)
		EPistolState.Actions.Insert:
			_set_anim_tree_oneshot_request(anim_reload_insert_shell_request)
		EPistolState.Actions.Eject:
			_set_anim_tree_oneshot_request(anim_reload_eject_shell_request)
		EPistolState.Actions.FanFire:
			colt_fan_hammer = true
		_:
			pass
	current_action = new_action

func _finish_prev_action()->void:
	if(current_action == EPistolState.Actions.EnterReload || current_action == EPistolState.Actions.EnterReloadUncock):
		enter_reload_done = true
		_tween_move_blend_amount(reload_movement_blend_value, 0.1)
	elif (current_action == EPistolState.Actions.ExitReload):
		exit_reload_done = true
	else:
		exit_reload_done = false
		enter_reload_done = false

func _on_action_interrupted(_prev : EPistolState.Actions, _new : EPistolState.Actions) -> void:
	if (_prev == EPistolState.Actions.None):
		return
		
	#specific edge cases to compensate for hand going forward/back
	if(_prev == EPistolState.Actions.Insert && _new == EPistolState.Actions.Eject):
		set(anim_reload_insert_shell_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)

	elif(_prev == EPistolState.Actions.Eject && _new == EPistolState.Actions.Insert):
		set(anim_reload_eject_shell_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
			
	if(_prev == EPistolState.Actions.CylinderNext && _new == EPistolState.Actions.CylinderNext):
		set(anim_reload_next_chamber_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		set(anim_reload_next_chamber_cont_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		next_cyl_cont = true

	if(_prev == EPistolState.Actions.CylinderPrev && _new == EPistolState.Actions.CylinderPrev):
		set(anim_reload_previous_chamber_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		set(anim_reload_previous_chamber_cont_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		prev_cyl_cont = true


	elif(_prev == EPistolState.Actions.EnterReloadUncock || _prev == EPistolState.Actions.EnterReload):
		_on_enter_reload_interrupted()
		
	elif(_prev == EPistolState.Actions.ExitReload):
		_on_exit_reload_interrupted()
		
func _on_enter_reload_interrupted() -> void:
	enter_reload_done = true

func _on_exit_reload_interrupted() -> void:
	exit_reload_done = true
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	prev_delta = _delta
	movement_blend_value = movement_blend_value.lerp( prev_move_direction, movement_blend_rate * 0.5 * prev_delta);
	_update_movement_blend_values()
	colt_fan_hammer = false
	
func _on_reload_change(enter : bool, enter_uncock : bool, exit : bool)-> void:
	if(enter || enter_uncock):
		if(enter):
			_set_anim_tree_oneshot_request(anim_enter_reload_request)
		elif(enter_uncock):
			_set_anim_tree_oneshot_request(anim_enter_reload_uncock_request)

		enter_reload_done = false
		_tween_move_blend_amount(reload_movement_blend_value , 0.1)
	elif(exit):
		exit_reload_done = false


	anim_tree[anim_colt_state_machine_path + anim_enter_reload_condition] = enter || enter_uncock
	anim_tree[anim_colt_state_machine_path + anim_exit_reload_condition] = exit
	
func _on_bullet_spawned_for_inserting(_new_bullet : Node3D) -> void:
	right_prop_bone.add_child(_new_bullet)
	
func _on_player_holster_started():
	colt_unholstered = false

func _holster_anim_finished():
	on_holster_anim_finish.emit()
	
func _on_player_unholster_started():
	colt_unholstered = true
	
func _toggle_equipment_visible(visible : bool) -> void:
	pistol.visible = visible

func _unholster_anim_finished():
	on_unholster_anim_finish.emit()

func _on_player_movement_input(direction:Vector2) -> void:
	prev_move_direction = direction
	
func _update_movement_blend_values() -> void:	
	anim_tree[anim_movement_blend] = movement_blend_value
	
func _reparent_gun_to_prop_bone(new_parent : E_prop_bone_type) -> void:
	var bone_to_reparent_to : BoneAttachment3D
	var new_pos : Vector3 = Vector3.ZERO;
	
	match (new_parent):
		E_prop_bone_type.Left:
			bone_to_reparent_to = left_prop_bone
		E_prop_bone_type.Right:
			bone_to_reparent_to = right_prop_bone
			new_pos = right_prop_bone_pos
		E_prop_bone_type.Global:
			bone_to_reparent_to = global_prop_bone
		
	pistol.reparent(bone_to_reparent_to,true)
	pistol.set_position(new_pos)

func _tween_move_blend_amount(new_value : float, time : float) -> void:
	if(move_blend_tween && move_blend_tween.is_running()):
		move_blend_tween.stop()
		
	move_blend_tween = create_tween()
	move_blend_tween.tween_property(anim_tree, anim_move_blend_add_amount, new_value,time)