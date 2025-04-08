@tool

class_name SkeletonRevolverHammerModifier extends SkeletonModifier3D


@export_enum(" ") var hammer_bone: String

var rotation_to_cache : float =0
var currently_caching_rotation : bool = false
var cached_transform : Transform3D  = Transform3D.IDENTITY

@onready var skeleton: Skeleton3D = %Skeleton3D
var hammer_bone_id  : int = 0


func _validate_property(property: Dictionary) -> void:
	#make a dropdown of all bones available in skeleton
	if property.name == "hammer_bone":
		var found_skeleton: Skeleton3D = get_skeleton()
		if found_skeleton:
			property.hint = PROPERTY_HINT_ENUM
			property.hint_string = found_skeleton.get_concatenated_bone_names() 

func _ready() -> void:
	if(skeleton):
		hammer_bone_id = skeleton.find_bone(hammer_bone)


func _cache_current_transform(cache : bool) -> void:
	currently_caching_rotation = cache
	if(cache):
		cached_transform = skeleton.get_bone_global_pose(hammer_bone_id)
	else:
		cached_transform = Transform3D.IDENTITY
		
	
func _process_modification() -> void:
	if !skeleton :
		return
	if !currently_caching_rotation:
		return
	skeleton.set_bone_global_pose(hammer_bone_id, cached_transform)