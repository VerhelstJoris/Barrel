class_name FencePoleData extends Resource

@export var post_variations_weighting_map : Dictionary[PackedScene, float]
@export var post_spacing: float = 0.3
@export var post_height_offset: float = 0.0
@export var point_up: bool = false
@export_group("Rotation")
enum ERotationRandomization { NONE, FULLY, QUARTER}
@export var random_rotation : ERotationRandomization = ERotationRandomization.NONE
@export var random_added_rotation_range_deg : Vector2 = Vector2.ZERO