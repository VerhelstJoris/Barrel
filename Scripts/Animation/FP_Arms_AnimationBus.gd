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

const anim_movement_blend : String = "parameters/SM_Colt/ReadyBlendTree/MoveBlendSpace/blend_position"




var movement_blend_value : Vector2 = Vector2.ZERO

var prev_delta : float = 0
#deltatime to forever blend towards the movement we're doing
const movement_blend_rate : float = 4

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pistol.update_fire_action.connect(_oneshot_fire)
	pistol.update_hammer_action.connect(_oneshot_cock_hammer)
	pistol.change_reload_state.connect(_on_reload_state_change)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	prev_delta = _delta
	pass
	
func _oneshot_fire() -> void:
	anim_tree.set(anim_fire_request,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	pass
	
func _oneshot_cock_hammer() -> void:
	anim_tree.set(anim_hammer_request,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	pass

func _on_reload_state_change(_new_value:bool) -> void:
	anim_tree[anim_enter_reload_condition] = _new_value
	#if(_new_value):
		#pistol.reparent(global_prop_bone)


func _on_player_movement_input(direction:Vector2) -> void:
	movement_blend_value = movement_blend_value.lerp(direction, movement_blend_rate * prev_delta);
	anim_tree.set(anim_movement_blend,movement_blend_value)
	pass # Replace with function body.
	

func _reparent_gun_to_prop_bone(new_parent : E_prop_bone_type) -> void:
	print("reparent gun")
	pass
	match (new_parent):
		E_prop_bone_type.Left:
			pistol.reparent(left_prop_bone,false)
		E_prop_bone_type.Right:
			pistol.reparent(right_prop_bone,false)
		E_prop_bone_type.Global:
			pistol.reparent(global_prop_bone,false)
	pass
