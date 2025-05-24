extends Node

@onready var anim_tree : AnimationTree = %AnimationTree
@onready var pistol : PlayerEquipmentPistol = %FP_Colt

@onready var global_prop_bone : BoneAttachment3D = %GlobalPropBone
@onready var left_prop_bone : BoneAttachment3D = %LPropBone
@onready var right_prop_bone : BoneAttachment3D = %RPropBone

enum E_prop_bone_type{Left, Right, Global}

const anim_fire_request : String = "parameters/SM_Colt/ReadyBlendTree/FireOneShot/request"
const anim_hammer_request : String = "parameters/SM_Colt/ReadyBlendTree/HammerOneShot/request"

const anim_enter_reload_condition : String = "parameters/SM_Colt/conditions/enter_reload"
const anim_exit_reload_condition : String = "parameters/SM_Colt/conditions/exit_reload"

const anim_reload_next_chamber_request : String = "parameters/SM_Colt/ReloadingBlendTree/NextChamberOneShot/request"
const anim_reload_previous_chamber_request : String = "parameters/SM_Colt/ReloadingBlendTree/PreviousChamberOneShot/request"
const anim_reload_insert_shell_request : String = "parameters/SM_Colt/ReloadingBlendTree/InsertShellOneShot/request"
const anim_reload_eject_shell_request : String = "parameters/SM_Colt/ReloadingBlendTree/EjectShellOneShot/request"


const anim_movement_blend : String = "parameters/SM_Colt/ReadyBlendTree/MoveBlendSpace/blend_position"
const reload_movement_blend : String = "parameters/SM_Colt/ReloadingBlendTree/MoveBlendSpace/blend_position"


var movement_blend_value : Vector2 = Vector2.ZERO

var prev_delta : float = 0
#deltatime to forever blend towards the movement we're doing
const movement_blend_rate : float = 4

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pistol.update_fire_action.connect(_oneshot_fire)
	pistol.update_hammer_action.connect(_oneshot_cock_hammer)
	pistol.change_reload_state.connect(_on_reload_state_change)
	pistol.reload_change_chamber.connect(_on_reload_change_chamber)
	pistol.reload_insert_shell.connect(_on_reload_insert_shell)
	pistol.reload_eject_shell.connect(_on_reload_eject_shell)
	pistol.bullet_spawned_for_inserting.connect(_on_bullet_spawned_for_inserting)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	prev_delta = _delta
	
func _oneshot_fire() -> void:
	anim_tree.set(anim_fire_request,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	
func _oneshot_cock_hammer() -> void:
	anim_tree.set(anim_hammer_request,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _on_reload_state_change(_new_value:bool) -> void:
	if _new_value:
		anim_tree[anim_enter_reload_condition] = true
		anim_tree[anim_exit_reload_condition] = false
	else:	
		anim_tree[anim_exit_reload_condition] = true
		anim_tree[anim_enter_reload_condition] = false
		
func _on_reload_change_chamber(_next_chamber: bool) -> void:
	print("cylinder signal")
	if _next_chamber:
		anim_tree.set(anim_reload_next_chamber_request,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		anim_tree.set(anim_reload_previous_chamber_request,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	
func _on_bullet_spawned_for_inserting(_new_bullet : Node3D) -> void:		
	right_prop_bone.add_child(_new_bullet)
	

func _on_reload_insert_shell() -> void:
	anim_tree.set(anim_reload_insert_shell_request,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	
func _on_reload_eject_shell() -> void:
	anim_tree.set(anim_reload_eject_shell_request,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _on_player_movement_input(direction:Vector2) -> void:
	movement_blend_value = movement_blend_value.lerp(direction, movement_blend_rate * prev_delta);
	anim_tree.set(anim_movement_blend,movement_blend_value)
	anim_tree.set(reload_movement_blend,movement_blend_value)
	

func _reparent_gun_to_prop_bone(new_parent : E_prop_bone_type) -> void:
	print("reparent gun")
	var bone_to_reparent_to : BoneAttachment3D
	match (new_parent):
		E_prop_bone_type.Left:
			bone_to_reparent_to = left_prop_bone
		E_prop_bone_type.Right:
			bone_to_reparent_to = right_prop_bone
		E_prop_bone_type.Global:
			bone_to_reparent_to = global_prop_bone
		
	pistol.reparent(bone_to_reparent_to,true)
	var pistolNode : Node3D = pistol.get_owner() as Node3D 
	pistolNode.set_global_transform(bone_to_reparent_to.get_global_transform())
