@icon("res://DEBUG/Icon.png")
class_name BarrelSceneDebugNode extends Node

@export var ChildNodesToDisplay : Array[BarrelSceneDebugNode]

var is_favourited : Array[bool] = [false]

func _ready() -> void:
	if(!OS.is_debug_build()):
		free()

func _draw(_delta: float) -> void:
	if(_draw_banner(_delta)):
		_draw_contents(_delta)
		_draw_children(_delta)
	
func _draw_banner(_delta : float) -> bool:
	ImGui.SetNextItemAllowOverlap()
	var header_open : bool = ImGui.CollapsingHeader(owner.name)
	
	ImGui.SameLineEx(ImGui.GetWindowWidth() - 50)
	ImGui.PushID(owner.name + "favourite")
	ImGui.Checkbox("Fav", is_favourited)
	ImGui.PopID()
	
	return header_open	

func _draw_contents(_delta : float) -> void:
	pass
	
func _draw_children(_delta : float) -> void:
	ImGui.Indent()
	for child in ChildNodesToDisplay:
		if(child != null):
			child._draw(_delta)
	ImGui.Unindent()
