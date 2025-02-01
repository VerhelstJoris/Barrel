class_name PlayerEquipmentPistol extends "PlayerEquipment.gd"

enum E_Pistol_State{ReadyToFire, HammerUncocked, Reloading}

@export_group("Equipment Input Details")
@export var ENTER_RELOAD: String = "enter_reload"

const log_pistol : String = "PlayerPistol" 
const anim_fire_condition : String = "parameters/conditions/try_fire"
const anim_pull_hammer_condition : String = "parameters/conditions/try_pull_hammer"
const anim_enter_reload_condition : String = "parameters/conditions/enter_reload"
const anim_exit_reload_condition : String = "parameters/conditions/exit_reload"
const anim_eject_condition : String = "parameters/conditions/eject_shell"


var start_reload: bool = true;
var CurrentState: E_Pistol_State = E_Pistol_State.HammerUncocked
var can_proceed_state: bool = true;

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func _physics_process(_delta: float):
	super(_delta)
	if Input.is_action_just_pressed(ENTER_RELOAD):
		_try_reload()

	var state_machine: AnimationNodeStateMachinePlayback = anim_tree["parameters/playback"]
	# Debug each frame you need to
	var current_animation = state_machine.get_current_node()
	Logging.warning(current_animation)


func _try_use_equipment():

	if _can_shoot():
		Logging.info("shooting")
		_proceed_to_state(E_Pistol_State.HammerUncocked)
		anim_tree[anim_fire_condition] = true
	elif(_can_cock_hammer()):
		Logging.info("cocking hammer")
		_proceed_to_state(E_Pistol_State.ReadyToFire)
		anim_tree[anim_pull_hammer_condition] = true
	#elif(_can_try_eject()):
	#	Logging.info("Try Ejecting Shell")
	#	anim_tree[anim_eject_condition] = true



func _try_reload():
	return
	#if(start_reload):
	#	CurrentState = Pistol_State.Reloading
	#	Logging.info("Try entering reload")
	#	anim_tree[anim_enter_reload_condition] = true
	#	anim_tree[anim_exit_reload_condition] = false
	#else:
	#	CurrentState = Pistol_State.HammerUncocked
	#	Logging.info("Try exiting reload")
	#	anim_tree[anim_enter_reload_condition] = false
	#	anim_tree[anim_exit_reload_condition] = true
	#start_reload = !StandardMaterial3D

func _proceed_to_state(new_state: E_Pistol_State) -> void:
	can_proceed_state = false
	CurrentState = new_state
	

func _enable_changing_states(b_enabled : bool) -> void:
	#reset animation variables
	anim_tree[anim_fire_condition] = false
	anim_tree[anim_pull_hammer_condition] = false
	can_proceed_state = b_enabled


func _can_try_eject() -> bool:
	return CurrentState == E_Pistol_State.Reloading

func _can_cock_hammer() -> bool:
	Logging.info("Try cocking hammer")
	return CurrentState == E_Pistol_State.HammerUncocked && can_proceed_state

func _can_shoot() -> bool:
	Logging.info("try shooting")
	return CurrentState == E_Pistol_State.ReadyToFire && can_proceed_state
	


