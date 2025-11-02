class_name FPArms extends Node3D

@onready var arms_animation_bus : FPArmsAnimationBus = %AnimationTree

@onready var pistol_equipment : PlayerEquipmentPistol = %FP_Colt
@onready var FP_camera : Camera3D = %FP_Camera

func _align_to_world_camera(align_to : Camera3D ) -> void:
	var current_transform : Transform3D = get_global_transform()
	var fp_cam_transform : Transform3D =  FP_camera.get_camera_transform()
	var cam_offset : Vector3 = current_transform.origin - fp_cam_transform.origin

	var target_transform : Transform3D = align_to.get_camera_transform()
	
	target_transform = target_transform.translated(cam_offset)
	#flip 2 axis of the basis that don't align
	target_transform.basis.x *= -1
	target_transform.basis.z *= -1
	

	set_global_transform(target_transform)


	