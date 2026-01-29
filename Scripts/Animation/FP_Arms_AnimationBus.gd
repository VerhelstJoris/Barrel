class_name FPArmsAnimationBus extends AnimationTree

@export var colt_scene : Node3D
var pistol : PlayerEquipmentPistol
var mov_comp : PlayerMovementComponent
var input_receiver : PlayerInputReceiver
var equipment_manager : EquipmentManager

@onready var global_prop_bone : BoneAttachment3D = %GlobalPropBone
@onready var left_prop_bone : BoneAttachment3D = %LPropBone
@onready var right_prop_bone : BoneAttachment3D = %RPropBone

enum EPropBoneType{Left, Right, Global}
var pistol_prop_bone_offset : Vector3 = Vector3.ZERO

const anim_right_arm_sm_path : String = "parameters/SM_Right/"
const anim_left_arm_sm_path : String = "parameters/SM_Left/"

#pistol related
const anim_colt_sm_path : String = "SM_Colt/"

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
const anim_default_movement_blend_property : String = "/MoveSM/DefaultMoveSpace/blend_position"
const anim_crouch_movement_blend_property : String = "/MoveSM/CrouchMoveSpace/blend_position"

const anim_move_sprint_blend_property : String = "/WalkSprintBlend/blend_amount"
const anim_move_vertical_blend_property : String = "/VerticalMovementBlendSpace/blend_position"

const anim_crouch_enter_request: String = "/EnterCrouchOneShot/request"
const anim_crouch_exit_request: String = "/ExitCrouchOneShot/request"

const anim_fanning_condition_1 : String = "FanningSM/conditions/fanning1"
const anim_fanning_condition_2 : String = "FanningSM/conditions/fanning2"
const anim_fanning_condition_3 : String = "FanningSM/conditions/fanning3"

# these variables are checked by the state machine itself as an expression
var enter_reload_done : bool = false
var exit_reload_done : bool  = false
var colt_unholstered : bool  = false
var colt_fan_hammer : bool   = false
var fanning_hammer_anim_id : int = 1

var throwable_unholstered : bool = false
var throwable_aiming : bool = false
var throwable_thrown : bool = false

var sprinting : bool = false
var crouching : bool = false

var current_action : PlayerEquipmentPistol.EPistolActions = PlayerEquipmentPistol.EPistolActions.None

var anim_move_blend_add_amount_property : String = "parameters/MoveBlendAdd/add_amount"
var movement_blend_value : Vector2 = Vector2.ZERO
var movement_vertical_blend_value : float = 0
var prev_move_direction : Vector2 = Vector2.ZERO
var move_blend_tween : Tween
var sprint_move_blend_tween : Tween

var next_cyl_cont : bool = false
var prev_cyl_cont : bool = false

signal on_unholster_anim_finish(slot : EquipmentManager.EEquipmentSlot)
signal on_holster_anim_finish(slot : EquipmentManager.EEquipmentSlot)

@export_group("movement animation values")
@export var horizontal_movement_blend_rate : float = 2
@export var vertical_movement_blend_rate : float = 4
@export var vertical_movement_bounds : Vector2
@export var reload_movement_blend_value : float = 0.5
@export var reload_movement_blend_tween_time : float = 1.0
@export var reload_transition_movement_blend_value : float = 0.0
@export var reload_transition_movement_blend_tween_time : float = 0.2


@export_group("sprint settings")
@export var sprint_speed_anim_threshold : float = 4

const arms_anim_bus_node_name : String = "FPArmsAnimationBus"

func _enter_tree() -> void:
	NodeUtils._add_node_meta_to_owner(arms_anim_bus_node_name,self, self)
	
func _ready() -> void:
	await owner.ready
	set(anim_move_blend_add_amount_property, 1.0)
	
func _init_player_data(player : Player) -> void:
	mov_comp = player.movement_component
	if(!mov_comp):
		push_error("No Movement component set on the FP Arms Anim Bus")
	input_receiver = player.input_receiver
	if(!input_receiver):
		push_error("No Input Receiver set on the FP Arms Anim Bus")
	equipment_manager = player.equipment_manager
	if(!equipment_manager):
		push_error("No Equipment Manager set on the FP Arms Anim Bus")
		
	equipment_manager.on_holster_started.connect(_on_equipmnent_start_holster)	
	equipment_manager.on_unholster_started.connect(_on_equipmnent_start_unholster)
	equipment_manager.on_equipped.connect(_on_equipped)
	equipment_manager.on_unequipped.connect(_on_unequipped)

func _on_equipmnent_start_holster(equipment : PlayerEquipment, _slot : EquipmentManager.EEquipmentSlot) -> void:
	_set_equipment_type_holster_value(equipment, false)
	
func _on_equipmnent_start_unholster(equipment : PlayerEquipment, _slot : EquipmentManager.EEquipmentSlot) -> void:
	_set_equipment_type_holster_value(equipment, true)
	
func _on_equipped(equipment : PlayerEquipment, _slot : EquipmentManager.EEquipmentSlot) -> void:
	var override_reparent_pos : Vector3 =Vector3.ZERO
	match typeof(equipment):
		_ when equipment is PlayerEquipmentThrowable:
			_connect_throwable_signals(equipment)
		_ when equipment is PlayerEquipmentPistol:
			pistol = equipment
			_connect_pistol_signals(equipment)
			override_reparent_pos = pistol_prop_bone_offset
		_:
			pass	

	match _slot:
		EquipmentManager.EEquipmentSlot.Left:
			_reparent_to_prop_bone(equipment.owner as Node3D, EPropBoneType.Left, true, override_reparent_pos)
		EquipmentManager.EEquipmentSlot.Right:
			_reparent_to_prop_bone(equipment.owner as Node3D, EPropBoneType.Right, true, override_reparent_pos)
		_:
			pass
	


func _on_unequipped(equipment : PlayerEquipment, _slot : EquipmentManager.EEquipmentSlot) -> void:
	_set_equipment_type_holster_value(equipment, false)

	match typeof(equipment):
		_ when equipment is PlayerEquipmentThrowable:
			_reset_throwable_data(equipment)
		_ when equipment is PlayerEquipmentPistol:
			_disconnect_pistol_signals(equipment)
			pistol = null
		_:
			pass

func _connect_throwable_signals(throwable : PlayerEquipmentThrowable) -> void:
	throwable.on_throwable_state_changed.connect(_on_throwable_equipment_state_changed)
	
func _reset_throwable_data(throwable : PlayerEquipmentThrowable) -> void:
	throwable.on_throwable_state_changed.disconnect(_on_throwable_equipment_state_changed)

	throwable_unholstered= false
	throwable_aiming  = false
	throwable_thrown = false
	
func _connect_pistol_signals(pistolequipment : PlayerEquipmentPistol) -> void:
	pistolequipment.on_action_started.connect(_on_pistol_action_started)
	pistolequipment.on_current_action_interrupted.connect(_on_pistol_action_interrupted)
	pistolequipment.bullet_spawned_for_inserting.connect(_on_bullet_spawned_for_inserting)
	
	if(pistol_prop_bone_offset == Vector3.ZERO):
		pistol_prop_bone_offset = pistolequipment.owner.get_position()
	
func _disconnect_pistol_signals(pistolequipment : PlayerEquipmentPistol) -> void:
	pistolequipment.on_action_started.disconnect(_on_pistol_action_started)
	pistolequipment.on_current_action_interrupted.disconnect(_on_pistol_action_interrupted)
	pistolequipment.bullet_spawned_for_inserting.disconnect(_on_bullet_spawned_for_inserting)

func _set_equipment_type_holster_value(equipment : PlayerEquipment, val : bool) -> void:
	match typeof(equipment):
		_ when equipment is PlayerEquipmentThrowable:
			throwable_unholstered = val
		_ when equipment is PlayerEquipmentPistol:
			colt_unholstered = val
		_:
			pass

func _set_equipment_oneshot_request(request_name : String, right_hand = true, two_handed = false,  request_type = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE):
	if(right_hand || two_handed):
		_set_anim_tree_oneshot_request(anim_right_arm_sm_path + request_name, request_type)
	if(!right_hand || two_handed):
		_set_anim_tree_oneshot_request(anim_left_arm_sm_path + request_name, request_type)

func _set_equipment_anim_variable(variable  : String, new_value : bool, right_hand = true, two_handed = false) -> void:
	if(right_hand || two_handed):
		set(anim_right_arm_sm_path + variable, new_value)
	if(!right_hand || two_handed):
		set(anim_left_arm_sm_path + variable, new_value)
		
func _set_anim_tree_oneshot_request(request_name, request_type = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE):
	set( request_name, request_type)
	
func _on_pistol_action_started(new_action : PlayerEquipmentPistol.EPistolActions) -> void:
	_finish_prev_pistol_action()
	var two_handed : bool = pistol._is_two_handed_action(new_action)
	var right_handed : bool = pistol._is_right_handed()
	match new_action:
		PlayerEquipmentPistol.EPistolActions.Fire:
			_set_equipment_oneshot_request(anim_colt_sm_path+ anim_fire_request, right_handed, two_handed )
		PlayerEquipmentPistol.EPistolActions.DryFire:
			_set_equipment_oneshot_request(anim_colt_sm_path+ anim_dry_fire_request, right_handed, two_handed)
		PlayerEquipmentPistol.EPistolActions.CockHammer:
			_set_equipment_oneshot_request(anim_colt_sm_path+ anim_hammer_request, right_handed, two_handed)
		PlayerEquipmentPistol.EPistolActions.EnterReload:
			_on_reload_change(true,false,false)
		PlayerEquipmentPistol.EPistolActions.EnterReloadUncock:
			_on_reload_change(false,true,false)
		PlayerEquipmentPistol.EPistolActions.ExitReload:
			_on_reload_change(false,false,true)
		PlayerEquipmentPistol.EPistolActions.CylinderNext:
			if(next_cyl_cont):
				_set_equipment_oneshot_request(anim_colt_sm_path+ anim_reload_next_chamber_cont_request, right_handed, two_handed)
				next_cyl_cont = false
			else:
				_set_equipment_oneshot_request(anim_colt_sm_path+ anim_reload_next_chamber_request, right_handed, two_handed)
		PlayerEquipmentPistol.EPistolActions.CylinderPrev:
			if(prev_cyl_cont):
				_set_equipment_oneshot_request(anim_colt_sm_path+ anim_reload_previous_chamber_cont_request, right_handed, two_handed)
				prev_cyl_cont = false
			else:
				_set_equipment_oneshot_request(anim_colt_sm_path+ anim_reload_previous_chamber_request, right_handed, two_handed)
		PlayerEquipmentPistol.EPistolActions.Insert:
			_set_equipment_oneshot_request(anim_colt_sm_path+ anim_reload_insert_shell_request, right_handed, two_handed)
		PlayerEquipmentPistol.EPistolActions.Eject:
			_set_equipment_oneshot_request(anim_colt_sm_path+ anim_reload_eject_shell_request, right_handed, two_handed)
		PlayerEquipmentPistol.EPistolActions.FanFire:
			_enter_fanning()
		_:
			pass
	current_action = new_action

func _finish_prev_pistol_action()->void:
	if(current_action == PlayerEquipmentPistol.EPistolActions.EnterReload || current_action == PlayerEquipmentPistol.EPistolActions.EnterReloadUncock):
		enter_reload_done = true
		_tween_move_blend_amount(reload_movement_blend_value, reload_movement_blend_tween_time)
		return
	elif (current_action == PlayerEquipmentPistol.EPistolActions.ExitReload):
		exit_reload_done = true
		return	
	
	colt_fan_hammer = false	
	exit_reload_done = false
	enter_reload_done = false

func _on_pistol_action_interrupted(_prev : PlayerEquipmentPistol.EPistolActions, _new : PlayerEquipmentPistol.EPistolActions) -> void:
	if (_prev == PlayerEquipmentPistol.EPistolActions.None):
		return
		
	var two_handed : bool = pistol._is_two_handed_action(_prev)	
	var right_handed : bool = pistol._is_right_handed()
	#specific edge cases to compensate for hand going forward/back
	if(_prev == PlayerEquipmentPistol.EPistolActions.Insert && _new == PlayerEquipmentPistol.EPistolActions.Eject):
		_set_equipment_oneshot_request(anim_colt_sm_path + anim_reload_insert_shell_request, right_handed, two_handed,AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	elif(_prev == PlayerEquipmentPistol.EPistolActions.Eject && _new == PlayerEquipmentPistol.EPistolActions.Insert):
		_set_equipment_oneshot_request(anim_colt_sm_path + anim_reload_eject_shell_request, right_handed, two_handed,AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	
	if(_prev == PlayerEquipmentPistol.EPistolActions.CylinderNext && _new == PlayerEquipmentPistol.EPistolActions.CylinderNext):
		_set_equipment_oneshot_request(anim_colt_sm_path + anim_reload_next_chamber_request, right_handed, two_handed,AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_set_equipment_oneshot_request(anim_colt_sm_path + anim_reload_next_chamber_cont_request, right_handed, two_handed,AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		next_cyl_cont = true

	if(_prev == PlayerEquipmentPistol.EPistolActions.CylinderPrev && _new == PlayerEquipmentPistol.EPistolActions.CylinderPrev):
		_set_equipment_oneshot_request(anim_colt_sm_path + anim_reload_previous_chamber_request, right_handed, two_handed,AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_set_equipment_oneshot_request(anim_colt_sm_path + anim_reload_previous_chamber_cont_request, right_handed, two_handed,AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		prev_cyl_cont = true
	elif(_prev == PlayerEquipmentPistol.EPistolActions.EnterReloadUncock || _prev == PlayerEquipmentPistol.EPistolActions.EnterReload):
		_on_enter_reload_interrupted()
	elif(_prev == PlayerEquipmentPistol.EPistolActions.ExitReload):
		_on_exit_reload_interrupted()
		
func _on_enter_reload_interrupted() -> void:
	enter_reload_done = true

func _on_exit_reload_interrupted() -> void:
	exit_reload_done = true
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	_update_movement_blend_values(_delta)
	colt_fan_hammer = false

func _enter_fanning() -> void:
	colt_fan_hammer = true
	_set_equipment_oneshot_request(anim_colt_sm_path+ anim_fire_request, pistol._is_right_handed(), false,AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT )
	
	fanning_hammer_anim_id = randi() %3 +1
	_set_equipment_anim_variable( anim_colt_sm_path + anim_fanning_condition_1,fanning_hammer_anim_id == 1, true, true)
	_set_equipment_anim_variable(anim_colt_sm_path + anim_fanning_condition_2,fanning_hammer_anim_id == 2, true, true)
	_set_equipment_anim_variable(anim_colt_sm_path + anim_fanning_condition_3,fanning_hammer_anim_id == 3,true, true)

func _on_reload_change(enter : bool, enter_uncock : bool, exit : bool)-> void:
	if(enter || enter_uncock):
		if(enter):
			_set_equipment_oneshot_request(anim_colt_sm_path+ anim_enter_reload_request, pistol._is_right_handed(), pistol._is_two_handed_action(PlayerEquipmentPistol.EPistolActions.EnterReload))
		elif(enter_uncock):
			_set_equipment_oneshot_request(anim_colt_sm_path+ anim_enter_reload_request, pistol._is_right_handed(), pistol._is_two_handed_action(PlayerEquipmentPistol.EPistolActions.EnterReloadUncock))
		enter_reload_done = false
	elif(exit):
		exit_reload_done = false

	_tween_move_blend_amount(reload_transition_movement_blend_value, reload_transition_movement_blend_tween_time)
	_set_equipment_anim_variable(anim_colt_sm_path + anim_enter_reload_condition, enter || enter_uncock, true, true)
	_set_equipment_anim_variable(anim_colt_sm_path + anim_exit_reload_condition,  exit, true, true)
	
func _on_bullet_spawned_for_inserting(_new_bullet : Node3D) -> void:
	right_prop_bone.add_child(_new_bullet)

#called as anim notify
func _holster_anim_finished(slot : EquipmentManager.EEquipmentSlot):
	on_holster_anim_finish.emit(slot)
	
#called as anim notify
func _toggle_equipment_visible(visible : bool) -> void:
	pistol.owner.visible = visible

func current_right_equipment_two_handed() -> bool:
	if(pistol == null):
		return false
	return pistol._is_currently_using_both_hands()

#called as anim notify	
func _unholster_anim_finished(slot : EquipmentManager.EEquipmentSlot):
	on_unholster_anim_finish.emit(slot)
	
func _proceed_current_equipment_action(_slot : EquipmentManager.EEquipmentSlot):
	if(equipment_manager.current_equipment[_slot] != null):
		equipment_manager.current_equipment[_slot]._proceed_with_action_from_animation()

func _update_movement_blend_values(delta : float) -> void:
	var horizontal_move : float = mov_comp.current_horizontal_velocity.length()
	sprinting = horizontal_move > sprint_speed_anim_threshold
	_update_horizontal_move_blend(delta)
	_update_vertical_move_blend(delta)
	prev_move_direction = input_receiver.input_direction

func _update_horizontal_move_blend(delta : float) -> void:
	movement_blend_value = movement_blend_value.lerp( prev_move_direction, horizontal_movement_blend_rate * delta);
	set(anim_move_state_machine_path + anim_default_movement_blend_property, movement_blend_value)
	set(anim_move_state_machine_path + anim_crouch_movement_blend_property, movement_blend_value)

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
	
func _fire_crouch_oneshot(enter : bool) -> void:
	if(enter):
		_set_anim_tree_oneshot_request(anim_move_state_machine_path + anim_crouch_enter_request)
		_set_anim_tree_oneshot_request(anim_move_state_machine_path + anim_crouch_exit_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	else:
		_set_anim_tree_oneshot_request(anim_move_state_machine_path + anim_crouch_exit_request)
		_set_anim_tree_oneshot_request(anim_move_state_machine_path + anim_crouch_enter_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	
	crouching = enter	
	
func _on_throwable_equipment_state_changed(_prev : PlayerEquipmentThrowable.EThrowableEquipmentState, _new : PlayerEquipmentThrowable.EThrowableEquipmentState) -> void:
	match _new:
		PlayerEquipmentThrowable.EThrowableEquipmentState.Default:
			throwable_aiming = false
		PlayerEquipmentThrowable.EThrowableEquipmentState.Aiming:
			throwable_aiming = true
		PlayerEquipmentThrowable.EThrowableEquipmentState.Throwing:
			throwable_thrown = true

func _reparent_to_prop_bone(node: Node3D,  new : EPropBoneType, reset_pos : bool, override_pos : Vector3 = Vector3.ZERO ) -> void:
	if(node == null):
		return

	var bone_to_reparent_to : BoneAttachment3D
	var new_pos : Vector3 = Vector3.ZERO;
	
	match (new):
		EPropBoneType.Left:
			bone_to_reparent_to = left_prop_bone
		EPropBoneType.Right:
			bone_to_reparent_to = right_prop_bone
		EPropBoneType.Global:
			bone_to_reparent_to = global_prop_bone

	new_pos = override_pos

	node.reparent(bone_to_reparent_to,true)
	if(reset_pos):
		node.set_position(new_pos)
	else:
		node.position = Vector3.ZERO
		node.rotation = Vector3.ZERO

# called by anim notifies	
func _reparent_gun_to_prop_bone(new_parent : EPropBoneType) -> void:
	_reparent_to_prop_bone(pistol.owner, new_parent, true, pistol_prop_bone_offset)

#called by some anim notifies
func _tween_move_blend_amount(new_val : float, duration : float) -> void:
	_tween_anim_property(move_blend_tween, anim_move_blend_add_amount_property, new_val, duration)

func _tween_anim_property(tween: Tween, blend_property : String ,new_value : float, time : float) -> void:
	if(tween && tween.is_running()):
		tween.stop()
		
	tween = create_tween()
	tween.tween_property(self, blend_property, new_value,time)