extends ColorRect

@export var default_alpha : float = 0.1
@export var crouched_alpha : float = 0.2
@export var transition_time : float = 0.12

var player: Player

var vignette_crouch_tween : Tween

const shader_alpha : String = "shader_parameter/alpha"

func _ready() -> void:
	await owner.ready
	player = owner as Player
	
	player.movement_component.on_player_movement_state_enter.connect(_on_player_enter_movement_state)
	player.movement_component.on_player_movement_state_leave.connect(_on_player_leave_movement_state)
	material.set(shader_alpha, default_alpha)
	pass

func _on_player_enter_movement_state(_state_entered: PlayerStateMachine.E_StateName) -> void:
	if(_state_entered == PlayerStateMachine.E_StateName.Crouch):
		_start_transition(true)

func _on_player_leave_movement_state(_state_exited: PlayerStateMachine.E_StateName) -> void:
	if(_state_exited == PlayerStateMachine.E_StateName.Crouch):
		_start_transition(false)
		
func _start_transition(to_crouch: bool) -> void:
	var target_alpha : float =0
	if(to_crouch):
		target_alpha = crouched_alpha
	else:
		target_alpha = default_alpha

	var transition_start_alpha : float = 0
	if(vignette_crouch_tween && vignette_crouch_tween.is_running()):
		transition_start_alpha = vignette_crouch_tween.get_total_elapsed_time() / transition_time
		vignette_crouch_tween.stop()

	vignette_crouch_tween = create_tween()
	vignette_crouch_tween.tween_property(material,shader_alpha,target_alpha,transition_time * (1-transition_start_alpha))
	
		