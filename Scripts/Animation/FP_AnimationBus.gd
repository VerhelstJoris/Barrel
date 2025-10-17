class_name FP_AnimationBus extends AnimationTree

var player: Player

func _ready() -> void:
	await owner.ready
	player = owner as Player
	
	player.movement_component.on_player_movement_state_enter.connect(_on_player_enter_movement_state)
	player.movement_component.on_player_movement_state_leave.connect(_on_player_leave_movement_state)

const anim_fp_crouch_request : String = "parameters/CrouchOneShot/request"
const anim_fp_uncrouch_request : String = "parameters/UnCrouchOneShot/request"

func _on_player_enter_movement_state(_state_entered: PlayerStateMachine.E_StateName) -> void:
	if(_state_entered == PlayerStateMachine.E_StateName.Crouch):
		set(anim_fp_crouch_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		set(anim_fp_uncrouch_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		
func _on_player_leave_movement_state(_state_exited: PlayerStateMachine.E_StateName) -> void:
	if(_state_exited == PlayerStateMachine.E_StateName.Crouch):
		set(anim_fp_uncrouch_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		set(anim_fp_crouch_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
