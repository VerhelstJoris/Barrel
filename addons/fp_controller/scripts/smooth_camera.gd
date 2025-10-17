class_name SmoothCamera extends Camera3D

@export var speed := 44.0

var player: Player

func _ready() -> void:
	await owner.ready
	player = owner as Player

func _physics_process(delta: float) -> void:
	var weight: float = clamp(speed * delta, 0.0, 1.0)
	
	global_transform = global_transform.interpolate_with(
		get_parent().global_transform, weight
	)
	
	global_position = get_parent().global_position
