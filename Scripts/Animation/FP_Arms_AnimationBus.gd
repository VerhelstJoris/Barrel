class_name FPArmsAnimationBus extends Node

@onready var anim_tree : AnimationTree = %AnimationTree
@onready var pistol : PlayerEquipmentPistol = %FP_Colt

@onready var global_prop_bone : BoneAttachment3D = %GlobalPropBone
@onready var left_prop_bone : BoneAttachment3D = %LPropBone
@onready var right_prop_bone : BoneAttachment3D = %RPropBone

enum E_prop_bone_type{Left, Right, Global}

const anim_fire_request : String = "parameters/SM_Colt/ReadyBlendTree/FireOneShot/request"
const anim_dry_fire_request : String = "parameters/SM_Colt/ReadyBlendTree/DryFireOneShot/request"
const anim_hammer_request : String = "parameters/SM_Colt/ReadyBlendTree/HammerOneShot/request"

const anim_enter_reload_condition : String = "parameters/SM_Colt/conditions/enter_reload"
const anim_enter_reload_uncock_condition : String = "parameters/SM_Colt/conditions/enter_reload_uncock"
const anim_exit_reload_condition : String = "parameters/SM_Colt/conditions/exit_reload"

const anim_reload_next_chamber_request : String = "parameters/SM_Colt/ReloadingBlendTree/NextChamberOneShot/request"
const anim_reload_previous_chamber_request : String = "parameters/SM_Colt/ReloadingBlendTree/PreviousChamberOneShot/request"
const anim_reload_insert_shell_request : String = "parameters/SM_Colt/ReloadingBlendTree/InsertShellOneShot/request"
const anim_reload_eject_shell_request : String = "parameters/SM_Colt/ReloadingBlendTree/EjectShellOneShot/request"

const anim_movement_blend : String = "parameters/SM_Colt/ReadyBlendTree/MoveBlendSpace/blend_position"
const reload_movement_blend : String = "parameters/SM_Colt/ReloadingBlendTree/MoveBlendSpace/blend_position"


var current_action : String = ""

var movement_blend_value : Vector2 = Vector2.ZERO

var prev_delta : float = 0
#deltatime to forever blend towards the movement we're doing
const movement_blend_rate : float = 4

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pistol.on_action_started.connect(_on_action_started)
	pistol.bullet_spawned_for_inserting.connect(_on_bullet_spawned_for_inserting)
	pistol.on_current_action_interrupted.connect(_on_action_interrupted)


func _set_anim_tree_oneshot_request(request_name):
	set(request_name, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	current_action = request_name

func _on_action_started(new_action : EPistolState.Actions) -> void:
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
			_set_anim_tree_oneshot_request(anim_reload_next_chamber_request)
		EPistolState.Actions.CylinderPrev:
			_set_anim_tree_oneshot_request(anim_reload_previous_chamber_request)
		EPistolState.Actions.Insert:
			_set_anim_tree_oneshot_request(anim_reload_insert_shell_request)
		EPistolState.Actions.Eject:
			_set_anim_tree_oneshot_request(anim_reload_eject_shell_request)
		_:
			pass


func _on_action_interrupted(_prev : EPistolState.Actions, _new : EPistolState.Actions) -> void:
	if (current_action == ""):
		return
		
	#only do this with a select few actions that are incoming?
	if(_prev == EPistolState.Actions.Insert || _prev == EPistolState.Actions.Eject):
		match _new:
			EPistolState.Actions.Insert, EPistolState.Actions.Eject:
				set(current_action, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
			_:
				pass
	
	current_action = ""

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	prev_delta = _delta
	
func _on_reload_change(enter : bool, enter_unock : bool, exit : bool)-> void:
	anim_tree[anim_enter_reload_condition] = enter
	anim_tree[anim_enter_reload_uncock_condition] = enter_unock
	anim_tree[anim_exit_reload_condition] = exit
		
func _on_bullet_spawned_for_inserting(_new_bullet : Node3D) -> void:		
	right_prop_bone.add_child(_new_bullet)
	
func _on_player_movement_input(direction:Vector2) -> void:
	movement_blend_value = movement_blend_value.lerp(direction, movement_blend_rate * prev_delta);
	set(anim_movement_blend,movement_blend_value)
	set(reload_movement_blend,movement_blend_value)
	
func _reparent_gun_to_prop_bone(new_parent : E_prop_bone_type) -> void:
	var bone_to_reparent_to : BoneAttachment3D
	match (new_parent):
		E_prop_bone_type.Left:
			bone_to_reparent_to = left_prop_bone
		E_prop_bone_type.Right:
			bone_to_reparent_to = right_prop_bone
		E_prop_bone_type.Global:
			bone_to_reparent_to = global_prop_bone
		
	pistol.reparent(bone_to_reparent_to,true)
