@tool

class_name SkeletonRevolverCylinderModifier extends SkeletonModifier3D


@export_enum(" ") var cylinder_bone: String


var amount_to_rotate: float = 0
var curve_alpha: Curve
var time_passed: float =0
var time_total: float =0

var current_rotation_amount: float = 0

func _validate_property(property: Dictionary) -> void:
	#make a dropdown of all bones available in skeleton
	if property.name == "cylinder_bone":
		var skeleton: Skeleton3D = get_skeleton()
		if skeleton:
			property.hint = PROPERTY_HINT_ENUM
			property.hint_string = skeleton.get_concatenated_bone_names()



func _physics_process(delta: float) -> void:
	if(time_passed < time_total && time_total >0):
		time_passed += delta
		var alpha: float = curve_alpha.sample(time_passed/time_total)
		current_rotation_amount = amount_to_rotate * alpha
	

func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if !skeleton:
		return
	var bone_idx: int = skeleton.find_bone(cylinder_bone)
	var pose: Transform3D = skeleton.get_bone_global_pose_override(bone_idx)
	var new_pose: Transform3D = skeleton.get_bone_global_pose(bone_idx).rotated_local( pose.basis.y ,deg_to_rad(current_rotation_amount))
	skeleton.set_bone_global_pose(bone_idx, new_pose)


#func _rotate_over_time(amount_deg: float, time : float) -> void:
#	pass

func _rotate_over_time(amount_deg: float, time : float, curve : Curve ) -> void:
	amount_to_rotate = amount_deg
	curve_alpha = curve
	time_passed = 0
	time_total = time
	pass
