class_name FPArms extends Node3D

@export var colt_scene : Node3D
@onready var pistol_equipment : PlayerEquipmentPistol

@onready var FP_camera : Camera3D = %FP_Camera

var cached_scale : Vector3

func _ready() -> void:
	pistol_equipment = NodeUtils._retrieve_node_meta_from_self(PlayerEquipment.equipment_node_name, colt_scene)
	cached_scale = get_scale()

func _align_to_world_camera(align_to : Camera3D ) -> void:
	var current_transform : Transform3D = get_global_transform()
	var fp_cam_transform : Transform3D =  FP_camera.get_camera_transform()
	var cam_offset : Vector3 = current_transform.origin - fp_cam_transform.origin

	var target_transform : Transform3D = align_to.get_camera_transform()
	
	target_transform = target_transform.translated(cam_offset)

	set_global_transform(target_transform)
	set_scale(cached_scale)

	