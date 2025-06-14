class_name ColtAnimationBus extends Node


@onready var cylinder_bone_modifier: SkeletonRevolverCylinderModifier = %SkeletonRevolverCylinderModifier
@onready var bullet_attachment_point: Node3D = %BulletAttachmentPoint
@onready var bullet_reparent_point: Node3D = %BulletReparentPoint
@onready var cylinder_attachment: BoneAttachment3D = %CylinderAttachment
@onready var anim_tree : AnimationTree = %AnimationTree

var colt_equipment : PlayerEquipmentPistol = null

var current_action : String = ""

const anim_fire_request : String = "parameters/FireOneShot/request"
const anim_dry_fire_request : String = "parameters/DryFireOneShot/request"
const anim_hammer_request : String = "parameters/HammerOneShot/request"
const anim_enter_reload_request : String = "parameters/EnterReloadOneShot/request"
const anim_enter_reload_uncock_request : String = "parameters/EnterReloadUncockOneShot/request"
const anim_exit_reload_request : String = "parameters/ExitReloadOneShot/request"
const anim_reload_next_chamber_request : String = "parameters/NextChamberOneShot/request"
const anim_reload_previous_chamber_request : String = "parameters/PreviousChamberOneShot/request"
const anim_reload_insert_shell_request : String = "parameters/InsertShellOneShot/request"
const anim_reload_eject_shell_request : String = "parameters/EjectShellOneShot/request"

func _initialize( pistol : PlayerEquipmentPistol)-> void:
	colt_equipment = pistol
	pistol.reload_insert_shell.connect(_insert_shell)
	pistol.reload_eject_shell.connect(_eject_shell)
	pistol.on_fire_action.connect(_on_fire)
	pistol.on_dry_fire_action.connect(_on_dry_fire)
	pistol.on_cock_hammer_action.connect(_on_cock_hammer)
	pistol.change_reload_state.connect(_on_reload_state_changed)
	pistol.reload_change_chamber.connect(_on_reload_cycle_cylinder)
	pistol.on_current_action_interrupted.connect(_interrupt_current_action)
	anim_tree.animation_finished.connect(_on_animation_finished)
	
func _set_anim_tree_oneshot_request(request_name):
	anim_tree.set(request_name, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	current_action = request_name
	
func _interrupt_current_action() -> void:
	if(current_action != ""):
		anim_tree.set(current_action, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		#this is the request, not the animation name
		_on_current_action_finished()
		
func _insert_shell() -> void:
	_set_anim_tree_oneshot_request(anim_reload_insert_shell_request)

func _eject_shell() -> void:
	_set_anim_tree_oneshot_request(anim_reload_eject_shell_request)
	
func _on_fire() -> void:
	_set_anim_tree_oneshot_request(anim_fire_request)

func _on_dry_fire() -> void:
	_set_anim_tree_oneshot_request(anim_dry_fire_request)
	
func _on_cock_hammer() -> void:
	_set_anim_tree_oneshot_request(anim_hammer_request)
	
func _on_reload_state_changed(entering : bool, current_pistol_state: EPistolState.State)	-> void:
	if(entering):
		if(current_pistol_state == EPistolState.State.HammerUncocked):
			_set_anim_tree_oneshot_request(anim_enter_reload_request)
		else:
			_set_anim_tree_oneshot_request(anim_enter_reload_uncock_request)
	else:
		_set_anim_tree_oneshot_request(anim_exit_reload_request)

func _on_reload_cycle_cylinder(next : bool)	-> void:
	if(next):
		_set_anim_tree_oneshot_request(anim_reload_next_chamber_request)
	else:
		_set_anim_tree_oneshot_request(anim_reload_previous_chamber_request)
		
func _on_animation_finished(_animation_name : String) -> void:
	_on_current_action_finished()

func _on_current_action_finished() -> void:
	if(current_action == ""):
		return
		
	cylinder_bone_modifier.increment_cylinder_rotations(colt_equipment.current_action_cylinder_rotations)
	print("ACTION FINISH", current_action)
		
	colt_equipment._enable_changing_states(true)
	match current_action:
		anim_enter_reload_request:
			_on_enter_reload_finish()
		anim_enter_reload_uncock_request:
			_on_enter_reload_finish()
		anim_exit_reload_request:
			colt_equipment.on_available_equipment_actions_changed.emit(colt_equipment.ready_state_input_details)
			
	current_action = ""		


func _on_enter_reload_finish()->void:
	colt_equipment.on_available_equipment_actions_changed.emit(colt_equipment.reload_state_input_details)	