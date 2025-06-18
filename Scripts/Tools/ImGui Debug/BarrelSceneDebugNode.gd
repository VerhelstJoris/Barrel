@icon("res://DEBUG/Icon.png")
class_name BarrelSceneDebugNode extends Node

@export var ChildNodesToDisplay : Array[BarrelSceneDebugNode]

func _ready() -> void:
	if(!OS.is_debug_build()):
		free()

func _draw(_delta: float) -> void:
	pass

func _draw_children(_delta : float) -> void:
	pass
	


	
