@icon("res://DEBUG/Icons/Ico_Bug.png")
class_name BarrelSceneDebugNode extends Node

@export var ChildNodesToDisplay : Array[BarrelSceneDebugNode]
@export var auto_expanded : bool = false

var is_favourited : Array[bool] = [false]
	
func _set_favourited(value):
	is_favourited = value
	print("set")


func _ready() -> void:
	if(!OS.is_debug_build()):
		free()
		
func _get_name() -> String:
	return owner.name

func _draw(_delta: float) -> void:
	if(_draw_banner(_delta)):
		_draw_contents(_delta)
		_draw_children(_delta)
	
func _draw_banner(_delta : float) -> bool:
	ImGui.SetNextItemAllowOverlap()
	
	var node_name : String = _get_name()
	var flags : int = 0
	if(auto_expanded):
		flags = ImGui.TreeNodeFlags_DefaultOpen
	var header_open : bool = ImGui.CollapsingHeader(node_name, flags)
	
	ImGui.SameLineEx(ImGui.GetWindowWidth() - 50)
	ImGui.PushID(node_name + "favourite")
	if(ImGui.Checkbox("Fav", is_favourited)):
		if(is_favourited[0] == true):
			BarrelDebugWindow.draw_favourited_debug.connect(_draw)
		else:
			BarrelDebugWindow.draw_favourited_debug.disconnect(_draw)
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
