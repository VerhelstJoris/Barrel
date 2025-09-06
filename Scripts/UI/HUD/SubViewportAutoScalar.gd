class_name SubViewportAutoScalar extends SubViewportContainer

@export var sub_viewport : SubViewport

func _ready() -> void:
	resized.connect(_on_resized)
	_on_resized()
	pass
	
func _on_resized() -> void:
	if(sub_viewport):
		sub_viewport.size = get_viewport_rect().size