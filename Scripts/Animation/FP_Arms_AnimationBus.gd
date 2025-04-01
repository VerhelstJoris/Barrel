extends Node

@onready var anim_tree : AnimationTree = %AnimationTree
@onready var pistol : PlayerEquipmentPistol = %FP_Colt

const anim_fire_condition : String = "parameters/Actions/conditions/try_fire"
const anim_pull_hammer_condition : String = "parameters/Actions/conditions/try_pull_hammer"

const anim_fire_request : String = "parameters/FireOneShot/request"
const anim_hammer_request : String = "parameters/HammerOneShot/request"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pistol.update_fire_action.connect(_oneshot_fire)
	pistol.update_hammer_action.connect(_oneshot_cock_hammer)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
	
func _oneshot_fire() -> void:
	anim_tree.set(anim_fire_request,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	pass
	
func _oneshot_cock_hammer() -> void:
	anim_tree.set(anim_hammer_request,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	pass
