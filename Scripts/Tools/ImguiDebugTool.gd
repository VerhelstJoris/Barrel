class_name DebugWindow extends Node

const debug_toggle_input = "toggle_debug"

var tool_open :bool = false;

func _input(event: InputEvent) -> void:
	if(event.is_action_pressed(debug_toggle_input)):
		_toggle()

func _toggle() -> void:
	tool_open = !tool_open

func _process(_delta: float) -> void:
	if(tool_open):
		if(ImGui.Begin("Demo")):
			ImGui.Text("testing testing")
		ImGui.End()

