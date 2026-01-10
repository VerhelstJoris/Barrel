class_name ColtAnimationBus extends Node


@onready var cylinder_bone_modifier: SkeletonRevolverCylinderModifier = %SkeletonRevolverCylinderModifier
@onready var bullet_attachment_point: Node3D = %BulletAttachmentPoint
@onready var bullet_reparent_point: Node3D = %BulletReparentPoint
@onready var cylinder_attachment: BoneAttachment3D = %CylinderAttachment
@onready var anim_tree : AnimationTree = %AnimationTree

var colt_equipment : PlayerEquipmentPistol = null

var current_anim_request : String = ""

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
const anim_reload_fan_fire_request : String = "parameters/FanFireOneShot/request"

func _ready() -> void:
	if(!get_owner().has_meta(PlayerEquipment.equipment_node_name)):
		push_error("Colt Animation Bus Cannot find equipment node via metadata")
		return
		
	colt_equipment = get_owner().get_meta(PlayerEquipment.equipment_node_name) as PlayerEquipmentPistol
	colt_equipment.on_action_started.connect(_on_action_started)
	colt_equipment.on_current_action_interrupted.connect(_interrupt_current_action)
	anim_tree.animation_finished.connect(_on_animation_finished)
	
func _set_anim_tree_oneshot_request(request_name):
	anim_tree.set(request_name, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	current_anim_request = request_name
	
func _on_action_started(new_action : PlayerEquipmentPistol.EPistolActions)	-> void:
	match new_action:
		PlayerEquipmentPistol.EPistolActions.Fire:
			_set_anim_tree_oneshot_request(anim_fire_request)
		PlayerEquipmentPistol.EPistolActions.DryFire:
			_set_anim_tree_oneshot_request(anim_dry_fire_request)
		PlayerEquipmentPistol.EPistolActions.CockHammer:
			_set_anim_tree_oneshot_request(anim_hammer_request)
		PlayerEquipmentPistol.EPistolActions.EnterReload:
			_set_anim_tree_oneshot_request(anim_enter_reload_request)
		PlayerEquipmentPistol.EPistolActions.EnterReloadUncock:
			_set_anim_tree_oneshot_request(anim_enter_reload_uncock_request)
		PlayerEquipmentPistol.EPistolActions.ExitReload:
			_set_anim_tree_oneshot_request(anim_exit_reload_request)
		PlayerEquipmentPistol.EPistolActions.CylinderNext:
			_set_anim_tree_oneshot_request(anim_reload_next_chamber_request)
		PlayerEquipmentPistol.EPistolActions.CylinderPrev:
			_set_anim_tree_oneshot_request(anim_reload_previous_chamber_request)
		PlayerEquipmentPistol.EPistolActions.Insert:
			_set_anim_tree_oneshot_request(anim_reload_insert_shell_request)
		PlayerEquipmentPistol.EPistolActions.Eject:
			_set_anim_tree_oneshot_request(anim_reload_eject_shell_request)
		PlayerEquipmentPistol.EPistolActions.FanFire:
			_set_anim_tree_oneshot_request(anim_reload_fan_fire_request)	
		_:
			pass

func _interrupt_current_action(_prev : PlayerEquipmentPistol.EPistolActions, _new : PlayerEquipmentPistol.EPistolActions) -> void:
	if(current_anim_request != ""):
		anim_tree.set(current_anim_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	
	if(_prev != PlayerEquipmentPistol.EPistolActions.None):
		_on_current_action_finished()
		
func _on_animation_finished(_animation_name : String) -> void:
	_on_current_action_finished()
	colt_equipment._enable_changing_states(true)


func _on_current_action_finished() -> void:
	if(current_anim_request == ""):
		return
		
	cylinder_bone_modifier.increment_cylinder_rotations(colt_equipment.current_action_cylinder_rotations)
			
	current_anim_request = ""
