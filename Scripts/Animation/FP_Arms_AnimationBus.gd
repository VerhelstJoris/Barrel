class_name FPArmsAnimationBus extends AnimationTree

@onready var pistol : PlayerEquipmentPistol = %FP_Colt
var mov_comp : PlayerMovementComponent 

@onready var global_prop_bone : BoneAttachment3D = %GlobalPropBone
@onready var left_prop_bone : BoneAttachment3D = %LPropBone
@onready var right_prop_bone : BoneAttachment3D = %RPropBone

enum E_prop_bone_type{Left, Right, Global}
var right_prop_bone_pos : Vector3 = Vector3.ZERO


#pistol related
const anim_colt_state_machine_path : String  = "parameters/SM_Player/SM_Colt/"

const anim_fire_request : String = "ReadyBlendTree/FireOneShot/request"
const anim_dry_fire_request : String = "ReadyBlendTree/DryFireOneShot/request"
const anim_hammer_request : String = "ReadyBlendTree/HammerOneShot/request"

const anim_enter_reload_condition : String = "conditions/enter_reload"
const anim_exit_reload_condition : String = "conditions/exit_reload"

const anim_enter_reload_uncock_request : String = "EnterReloadBT/EnterUncockOneShot/request"
const anim_enter_reload_request : String = "EnterReloadBT/EnterReloadOneShot/request"
const anim_reload_next_chamber_request : String = "ReloadingBlendTree/NextChamberOneShot/request"
const anim_reload_next_chamber_cont_request : String = "ReloadingBlendTree/NextChamberContOneShot/request"
const anim_reload_previous_chamber_request : String = "ReloadingBlendTree/PreviousChamberOneShot/request"
const anim_reload_previous_chamber_cont_request : String = "ReloadingBlendTree/PreviousChamberContOneShot/request"
const anim_reload_insert_shell_request : String = "ReloadingBlendTree/InsertShellOneShot/request"
const anim_reload_eject_shell_request : String = "ReloadingBlendTree/EjectShellOneShot/request"

#movement related
const anim_move_state_machine_path : String = "parameters/SM_Movement/BlendTree"
const anim_movement_blend_property : String = "/MovementBlendSpace/blend_position"
const anim_move_sprint_blend_property : String = "/WalkSprintBlend/blend_amount"
const anim_move_vertical_blend_property : String = "/VerticalMovementBlendSpace/blend_position"

const anim_crouch_enter_request: String = "/EnterCrouchOneShot/request"
const anim_crouch_exit_request: String = "/ExitCrouchOneShot/request"

const anim_fanning_condition_1 : String = "FanningSM/conditions/fanning1"
const anim_fanning_condition_2 : String = "FanningSM/conditions/fanning2"
const anim_fanning_condition_3 : String = "FanningSM/conditions/fanning3"

# these variables are checked by the state machine itself as an expression
var enter_reload_done : bool = false
var exit_reload_done : bool = false
var colt_unholstered : bool = false
var colt_fan_hammer : bool = false
var fanning_hammer_anim_id : int = 1

var current_action : EPistolState.Actions = EPistolState.Actions.None

var anim_move_blend_add_amount_property : String = "parameters/MoveBlendAdd/add_amount"
var movement_blend_value : Vector2 = Vector2.ZERO
var movement_vertical_blend_value : float = 0
var prev_move_direction : Vector2 = Vector2.ZERO
var move_blend_tween : Tween
var sprint_move_blend_tween : Tween

var next_cyl_cont : bool = false
var prev_cyl_cont : bool = false

signal on_unholster_anim_finish()
signal on_holster_anim_finish()

var prev_delta : float = 0
@export_group("movement animation values")
@export var horizontal_movement_blend_rate : float = 2
@export var vertical_movement_blend_rate : float = 4
@export var vertical_movement_bounds : Vector2
@export var reload_movement_blend_value : float = 0.5
@export var reload_movement_blend_tween_time : float = 1.0
@export var reload_transition_movement_blend_value : float = 0.0
@export var reload_transition_movement_blend_tween_time : float = 0.2


@export_group("sprint settings")
@export var sprint_blend_speed : float = 0.15
@export var sprint_speed_anim_threshold : float = 4
var sprint_blend_target : float = 0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pistol.on_action_started.connect(_on_pistol_action_started)
	pistol.on_current_action_interrupted.connect(_on_pistol_action_interrupted)
	pistol.bullet_spawned_for_inserting.connect(_on_bullet_spawned_for_inserting)
	right_prop_bone_pos = pistol.get_position()
	set(anim_move_blend_add_amount_property, 1.0)
	
func _init_player_data(player : Player) -> void:
	mov_comp = player.movement_component
	mov_comp.on_player_movement.connect(_on_player_movement_input)
	mov_comp.on_player_movement_state_leave.connect(_on_player_exit_movement_state)
	mov_comp.on_player_movement_state_enter.connect(_on_player_enter_movement_state)
	
	player.on_holster_started.connect(_on_player_holster_started)
	player.on_unholster_started.connect(_on_player_unholster_started)

func _set_anim_tree_oneshot_request(request_name):
	set( request_name, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _on_pistol_action_started(new_action : EPistolState.Actions) -> void:
	_finish_prev_pistol_action()
	match new_action:
		EPistolState.Actions.Fire:
			_set_anim_tree_oneshot_request(anim_colt_state_machine_path+ anim_fire_request)
		EPistolState.Actions.DryFire:
			_set_anim_tree_oneshot_request(anim_colt_state_machine_path+ anim_dry_fire_request)
		EPistolState.Actions.CockHammer:
			_set_anim_tree_oneshot_request(anim_colt_state_machine_path+ anim_hammer_request)
		EPistolState.Actions.EnterReload:
			_on_reload_change(true,false,false)
		EPistolState.Actions.EnterReloadUncock:
			_on_reload_change(false,true,false)
		EPistolState.Actions.ExitReload:
			_on_reload_change(false,false,true)
		EPistolState.Actions.CylinderNext:
			if(next_cyl_cont):
				_set_anim_tree_oneshot_request(anim_colt_state_machine_path+ anim_reload_next_chamber_cont_request)
				next_cyl_cont = false
			else:		
				_set_anim_tree_oneshot_request(anim_colt_state_machine_path+ anim_reload_next_chamber_request)
		EPistolState.Actions.CylinderPrev:
			if(prev_cyl_cont):
				_set_anim_tree_oneshot_request(anim_colt_state_machine_path+ anim_reload_previous_chamber_cont_request)
				prev_cyl_cont = false
			else:
				_set_anim_tree_oneshot_request(anim_colt_state_machine_path+ anim_reload_previous_chamber_request)
		EPistolState.Actions.Insert:
			_set_anim_tree_oneshot_request(anim_colt_state_machine_path+ anim_reload_insert_shell_request)
		EPistolState.Actions.Eject:
			_set_anim_tree_oneshot_request(anim_colt_state_machine_path+ anim_reload_eject_shell_request)
		EPistolState.Actions.FanFire:
			_on_fanning_entered()
		_:
			pass
	current_action = new_action

func _finish_prev_pistol_action()->void:
	if(current_action == EPistolState.Actions.EnterReload || current_action == EPistolState.Actions.EnterReloadUncock):
		enter_reload_done = true
		_tween_move_blend_amount(reload_movement_blend_value, reload_movement_blend_tween_time)
	elif (current_action == EPistolState.Actions.ExitReload):
		exit_reload_done = true
	else:
		exit_reload_done = false
		enter_reload_done = false

func _on_pistol_action_interrupted(_prev : EPistolState.Actions, _new : EPistolState.Actions) -> void:
	if (_prev == EPistolState.Actions.None):
		return
		
	#specific edge cases to compensate for hand going forward/back
	if(_prev == EPistolState.Actions.Insert && _new == EPistolState.Actions.Eject):
		set(anim_reload_insert_shell_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)

	elif(_prev == EPistolState.Actions.Eject && _new == EPistolState.Actions.Insert):
		set(anim_reload_eject_shell_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
			
	if(_prev == EPistolState.Actions.CylinderNext && _new == EPistolState.Actions.CylinderNext):
		set(anim_reload_next_chamber_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		set(anim_reload_next_chamber_cont_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		next_cyl_cont = true

	if(_prev == EPistolState.Actions.CylinderPrev && _new == EPistolState.Actions.CylinderPrev):
		set(anim_reload_previous_chamber_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		set(anim_reload_previous_chamber_cont_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		prev_cyl_cont = true


	elif(_prev == EPistolState.Actions.EnterReloadUncock || _prev == EPistolState.Actions.EnterReload):
		_on_enter_reload_interrupted()
		
	elif(_prev == EPistolState.Actions.ExitReload):
		_on_exit_reload_interrupted()
		
func _on_enter_reload_interrupted() -> void:
	enter_reload_done = true

func _on_exit_reload_interrupted() -> void:
	exit_reload_done = true
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	_update_movement_blend_values(_delta)
	colt_fan_hammer = false
	prev_delta = _delta

func _on_fanning_entered() -> void:
	colt_fan_hammer = true

	fanning_hammer_anim_id = randi() %3 +1
	set(anim_colt_state_machine_path + anim_fanning_condition_1,fanning_hammer_anim_id == 1)
	set(anim_colt_state_machine_path + anim_fanning_condition_2,fanning_hammer_anim_id == 2)
	set(anim_colt_state_machine_path + anim_fanning_condition_3,fanning_hammer_anim_id == 3)

func _on_reload_change(enter : bool, enter_uncock : bool, exit : bool)-> void:
	if(enter || enter_uncock):
		if(enter):
			_set_anim_tree_oneshot_request(anim_colt_state_machine_path+anim_enter_reload_request)
		elif(enter_uncock):
			_set_anim_tree_oneshot_request(anim_colt_state_machine_path+ anim_enter_reload_uncock_request)

		enter_reload_done = false
	elif(exit):
		exit_reload_done = false

	_tween_move_blend_amount(reload_transition_movement_blend_value, reload_transition_movement_blend_tween_time)
	set(anim_colt_state_machine_path + anim_enter_reload_condition, enter || enter_uncock)
	set(anim_colt_state_machine_path + anim_exit_reload_condition,  exit)
	
func _on_bullet_spawned_for_inserting(_new_bullet : Node3D) -> void:
	right_prop_bone.add_child(_new_bullet)
	
func _on_player_holster_started():
	colt_unholstered = false

func _holster_anim_finished():
	on_holster_anim_finish.emit()
	
func _on_player_unholster_started():
	colt_unholstered = true
	
func _toggle_equipment_visible(visible : bool) -> void:
	pistol.visible = visible

func _unholster_anim_finished():
	on_unholster_anim_finish.emit()

func _on_player_movement_input(direction:Vector2) -> void:
	prev_move_direction = direction
	
func _update_movement_blend_values(delta : float) -> void:
	var horizontal_move : float = mov_comp.current_horizontal_velocity.length()
	if horizontal_move > sprint_speed_anim_threshold:
		_check_transition_sprint(true)
	else:
		_check_transition_sprint(false)
		_update_horizontal_move_blend(delta)

	_update_vertical_move_blend(delta)

func _update_horizontal_move_blend(delta : float) -> void:
	movement_blend_value = movement_blend_value.lerp( prev_move_direction, horizontal_movement_blend_rate * delta);
	set(anim_move_state_machine_path + anim_movement_blend_property, movement_blend_value)

func _update_vertical_move_blend(delta : float) -> void:
	var yvel : float = mov_comp.player.velocity.y
	var target_val : float =0
	if(yvel > 0):
		target_val = remap(yvel,vertical_movement_bounds.x,0.0,-1,0.0)
	else:
		target_val = remap(yvel,0.0,vertical_movement_bounds.y,0.0,1.0)

	target_val = clamp(target_val, -1 , 1)
	movement_vertical_blend_value = lerpf(movement_vertical_blend_value, target_val ,vertical_movement_blend_rate * delta )
	set(anim_move_state_machine_path + anim_move_vertical_blend_property, movement_vertical_blend_value)
	
func _on_player_enter_movement_state(_state_entered: PlayerStateMachine.E_StateName) -> void:
	if(_state_entered == PlayerStateMachine.E_StateName.Crouch):
		_set_anim_tree_oneshot_request(anim_move_state_machine_path + anim_crouch_enter_request)
	pass

func _on_player_exit_movement_state(_state_exited: PlayerStateMachine.E_StateName) -> void:
	if(_state_exited == PlayerStateMachine.E_StateName.Crouch):
		_set_anim_tree_oneshot_request(anim_move_state_machine_path + anim_crouch_exit_request)
	pass
	

func _check_transition_sprint(try_enter : bool) -> void:
	var target_blend : float = try_enter
	
	if(sprint_blend_target != target_blend):
		_tween_anim_property(sprint_move_blend_tween,  anim_move_state_machine_path+ anim_move_sprint_blend_property,target_blend,sprint_blend_speed)
		sprint_blend_target = target_blend
		
func _reparent_gun_to_prop_bone(new_parent : E_prop_bone_type) -> void:
	var bone_to_reparent_to : BoneAttachment3D
	var new_pos : Vector3 = Vector3.ZERO;
	
	match (new_parent):
		E_prop_bone_type.Left:
			bone_to_reparent_to = left_prop_bone
		E_prop_bone_type.Right:
			bone_to_reparent_to = right_prop_bone
			new_pos = right_prop_bone_pos
		E_prop_bone_type.Global:
			bone_to_reparent_to = global_prop_bone
		
	pistol.reparent(bone_to_reparent_to,true)
	pistol.set_position(new_pos)

#called by some anim notifies
func _tween_move_blend_amount(new_val : float, duration : float) -> void:
	_tween_anim_property(move_blend_tween, anim_move_blend_add_amount_property, new_val, duration)
	

func _tween_anim_property(tween: Tween, blend_property : String ,new_value : float, time : float) -> void:
	if(tween && tween.is_running()):
		tween.stop()
		
	tween = create_tween()
	tween.tween_property(self, blend_property, new_value,time)