extends Node

@onready var anim_tree : AnimationTree = %AnimationTree
@onready var pistol : PlayerEquipmentPistol = %FP_Colt


const anim_fire_request : String = "parameters/FireOneShot/request"
const anim_hammer_request : String = "parameters/HammerOneShot/request"

const anim_movement_blend : String = "parameters/MoveBlendSpace/blend_position"

var movement_blend_value : Vector2 = Vector2.ZERO

var prev_delta : float = 0
#deltatime to forever blend towards the movement we're doing
const movement_blend_rate : float = 15

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pistol.update_fire_action.connect(_oneshot_fire)
	pistol.update_hammer_action.connect(_oneshot_cock_hammer)
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


func _on_player_player_movement_input(direction:Vector2) -> void:
	direction.y *= -1 #flip published Y as -1 is forward
	movement_blend_value = movement_blend_value.lerp(direction, movement_blend_rate * prev_delta);
	anim_tree.set(anim_movement_blend,movement_blend_value)
	pass # Replace with function body.
