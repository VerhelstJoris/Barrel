class_name FP_AnimationBus extends AnimationTree

var player: Player

func _ready() -> void:
	await owner.ready
	player = owner as Player
	
const anim_fp_crouch_request : String = "parameters/CrouchOneShot/request"
const anim_fp_uncrouch_request : String = "parameters/UnCrouchOneShot/request"


func _fire_crouch_oneshot(entering : bool) -> void:
	if(entering):
		set(anim_fp_crouch_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		set(anim_fp_uncrouch_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	else:
		set(anim_fp_uncrouch_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		set(anim_fp_crouch_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
