class_name ColtAnimationBus extends Node


@onready var cylinder_bone_modifier: SkeletonRevolverCylinderModifier = %SkeletonRevolverCylinderModifier
@onready var bullet_attachment_point: Node3D = %BulletAttachmentPoint
@onready var bullet_reparent_point: Node3D = %BulletReparentPoint
@onready var cylinder_attachment: BoneAttachment3D = %CylinderAttachment
@onready var anim_tree : AnimationTree = %AnimationTree

var colt_equipment : PlayerEquipmentPistol = null

const cock_hammer_animation : String = "AL_Colt_SAA/A_Colt_Cock_Hammer"
const enter_reload_animation : String = "AL_Colt_SAA/A_Colt_Enter_Reload"
const enter_reload_uncock_animation : String = "AL_Colt_SAA/A_Colt_Enter_Reload_Uncock"
const exit_reload_animation : String = "AL_Colt_SAA/A_Colt_Exit_Reload"
const reload_next_chamber_animation : String = "AL_Colt_SAA/A_Colt_Reload_Next_Chamber"
const reload_previous_chamber_animation : String = "AL_Colt_SAA/A_Colt_Reload_Previous_Chamber"
const reload_insert_shell_animation : String = "AL_Colt_SAA/A_Colt_Reload_Insert_Shell"

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
	anim_tree.animation_finished.connect(_on_animation_finished)
	
func _insert_shell() -> void:
	anim_tree.set(anim_reload_insert_shell_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _eject_shell() -> void:
	anim_tree.set(anim_reload_eject_shell_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	

func _on_fire() -> void:
	anim_tree.set(anim_fire_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	
func _on_dry_fire() -> void:
	anim_tree.set(anim_fire_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	
func _on_cock_hammer() -> void:
	anim_tree.set(anim_hammer_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _on_reload_state_changed(entering : bool, current_pistol_state: EPistolState.State)	-> void:
	if(entering):
		if(current_pistol_state == EPistolState.State.HammerUncocked):
			anim_tree.set(anim_enter_reload_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)		
		else:
			anim_tree.set(anim_enter_reload_uncock_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		anim_tree.set(anim_exit_reload_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _on_reload_cycle_cylinder(next : bool)	-> void:
	if(next):
		anim_tree.set(anim_reload_next_chamber_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		anim_tree.set(anim_reload_previous_chamber_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		
func _on_animation_finished(animation_name : String) -> void:
	colt_equipment._enable_changing_states(true)
	match animation_name:
		cock_hammer_animation:
			colt_equipment._increase_cylinder_rotations(1)
		reload_previous_chamber_animation:
			colt_equipment._increase_cylinder_rotations(1)
		enter_reload_animation:
			_on_enter_reload_finish()
		enter_reload_uncock_animation:
			_on_enter_reload_finish()
		reload_next_chamber_animation:
			colt_equipment._increase_cylinder_rotations(-1)
		exit_reload_animation:
			colt_equipment.on_available_equipment_actions_changed.emit(colt_equipment.ready_state_input_details)
		
func _on_enter_reload_finish()->void:
	colt_equipment._increase_cylinder_rotations(1)
	colt_equipment.on_available_equipment_actions_changed.emit(colt_equipment.reload_state_input_details)	