@tool

class_name SkeletonRevolverCylinderModifier extends SkeletonModifier3D


@export_enum(" ") var cylinder_bone: String


@onready var skeleton: Skeleton3D = %Skeleton3D
var cylinder_bone_id  : int = 0

var amount_of_rotations : int =0

func _validate_property(property: Dictionary) -> void:
	#make a dropdown of all bones available in skeleton
	if property.name == "cylinder_bone":
		var found_skeleton: Skeleton3D = get_skeleton()
		if found_skeleton:
			property.hint = PROPERTY_HINT_ENUM
			property.hint_string = found_skeleton.get_concatenated_bone_names() 

func _ready() -> void:
	if(skeleton):
		cylinder_bone_id = skeleton.find_bone(cylinder_bone)
		
func increment_cylinder_rotations(added: int) -> void:
	amount_of_rotations += added
	
		
func _process_modification() -> void:
	if !skeleton :
		return
		
	var pose: Transform3D = skeleton.get_bone_global_pose_override(cylinder_bone_id)
	var new_pose: Transform3D = skeleton.get_bone_global_pose(cylinder_bone_id).rotated_local( pose.basis.y ,deg_to_rad(amount_of_rotations * 60))
	skeleton.set_bone_global_pose(cylinder_bone_id, new_pose)
