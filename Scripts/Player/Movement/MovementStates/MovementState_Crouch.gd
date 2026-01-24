class_name Crouch extends MovementState_Base

@export_group("Shape Components")
var height_diff : float = 0
@export var camera_attach_node : Node3D

@export_group("Vignette")
@export var vignette : HUDVignette
@export var crouch_vignette_alpha: float = 0.1
@export var crouch_vignette_transition_time : float= 0.12

@export_group("Animation Components")
@export var first_person_anim_bus : FP_AnimationBus
@export var arms_anim_bus : FPArmsAnimationBus

@export_group("Transition Settings")
@export var standing_to_crouch_transition_time : float = 0.05
@export var crouch_to_standing_transition_time : float = 0.05

var camera_transition_tween : Tween
var entering : bool = false

func _ready() -> void:
	super()

	if(!vignette):
		push_error("No vignette found on crouch state")
		
	if(!first_person_anim_bus):
		push_error("No FP Anim Bus set on crouch state")
		


func _init_player_data(in_player : Player) -> void:
	super(in_player)
	arms_anim_bus = NodeUtils._retrieve_node_meta_from_self(FPArmsAnimationBus.arms_anim_bus_node_name, player.arms)

	if(!arms_anim_bus):
		push_error("No Arms Anim Bus set on crouch state")

	player.crouching_shape.disabled = true
	height_diff = (player.standing_shape.shape as CapsuleShape3D).height - (player.crouching_shape.shape as CapsuleShape3D).height


func _check_transitions() -> void:
	if(!input_comp.crouch_down && _can_currently_exit()):
		state_machine._transition_to(state_machine.EStateName.Walk)
	
func _on_enter_internal() -> void:
	player.crouching_shape.disabled = false
	player.standing_shape.disabled = true
	entering = true

	_start_transition(true)
	if(vignette):
		vignette._transition_vignette(crouch_vignette_alpha, crouch_vignette_transition_time)
		
	if(first_person_anim_bus):
		first_person_anim_bus._fire_crouch_oneshot(true)
		
	if(arms_anim_bus):
		arms_anim_bus._fire_crouch_oneshot(true)

func _on_exit_internal() -> void:
	player.crouching_shape.disabled = true
	player.standing_shape.disabled = false
	entering = false

	_start_transition(false)
	if(vignette):
		vignette._transition_vignette(vignette.default_alpha, crouch_vignette_transition_time)

	if(first_person_anim_bus):
		first_person_anim_bus._fire_crouch_oneshot(false)
		
	if(arms_anim_bus):
		arms_anim_bus._fire_crouch_oneshot(false)

func _can_currently_exit() -> bool:
	var translation_needed : Vector3 = Vector3(0,height_diff,0)

	if (!player.test_move(player.global_transform,translation_needed)):
		return true

	return false	

func _start_transition(to_crouch : bool) -> void:
	var current_time : float
	var next_time : float
	var node_to_lerp_to : Node3D

	if(to_crouch):
		current_time = crouch_to_standing_transition_time
		next_time = standing_to_crouch_transition_time
		node_to_lerp_to = player.crouching_camera_pivot
	else:
		current_time = standing_to_crouch_transition_time
		next_time = crouch_to_standing_transition_time
		node_to_lerp_to = player.standing_camera_pivot


	var transition_start_alpha : float = 0
	if(camera_transition_tween && camera_transition_tween.is_running()):
		transition_start_alpha = camera_transition_tween.get_total_elapsed_time() / current_time
		camera_transition_tween.stop()

	camera_transition_tween = create_tween()
	camera_transition_tween.tween_property(camera_attach_node,"position",node_to_lerp_to.position,next_time * (1-transition_start_alpha)).set_ease(Tween.EASE_OUT)

