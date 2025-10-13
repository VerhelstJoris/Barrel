class_name Crouch extends PlayerState

@export_group("Components")
@export var standing_shape : CollisionShape3D
@export var standing_camera_pivot : Node3D

@export var crouching_shape : CollisionShape3D
@export var crouching_camera_pivot : Node3D

var height_diff : float = 0
@export var camera_attach_node : Node3D

@export_group("Transition Settings")
@export var standing_to_crouch_transition_time : float = 0.05
@export var crouch_to_standing_transition_time : float = 0.05

var camera_transition_tween : Tween
var entering : bool = false

func _ready() -> void:
	super()
	crouching_shape.disabled = true
	height_diff = (standing_shape.shape as CapsuleShape3D).height - (crouching_shape.shape as CapsuleShape3D).height

func _check_transitions() -> void:
	if(!mov_comp.crouch_down && _can_currently_exit()):
		state_machine._transition_to(state_machine.E_StateName.Walk)
	
func _on_enter_internal() -> void:
	crouching_shape.disabled = false
	standing_shape.disabled = true
	entering = true

	_start_transition(true)

func _on_exit_internal() -> void:
	crouching_shape.disabled = true
	standing_shape.disabled = false
	entering = false

	_start_transition(false)

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
		node_to_lerp_to = crouching_camera_pivot
	else:
		current_time = standing_to_crouch_transition_time
		next_time = crouch_to_standing_transition_time
		node_to_lerp_to = standing_camera_pivot


	var transition_start_alpha : float = 0
	if(camera_transition_tween && camera_transition_tween.is_running()):
		transition_start_alpha = camera_transition_tween.get_total_elapsed_time() / current_time
		camera_transition_tween.stop()
		
	camera_transition_tween = create_tween()
	camera_transition_tween.tween_property(camera_attach_node,"position",node_to_lerp_to.position,next_time * (1-transition_start_alpha))
	

			