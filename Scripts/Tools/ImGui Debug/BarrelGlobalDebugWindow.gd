class_name BarrelGlobalDebugWindow extends Node

const debug_toggle_input : String = "debug_toggle"
const debug_toggle_mouse_capture : String = "debug_toggle_mouse_capture"

var tool_open :bool = false;

signal draw_player_debug(_delta)

func _input(event: InputEvent) -> void:
	if(event.is_action_pressed(debug_toggle_input)):
		_toggle_window()
	elif(event.is_action_pressed(debug_toggle_mouse_capture)):
		_toggle_mouse_capture()

	
func _toggle_window() -> void:
	tool_open = !tool_open
	if(tool_open):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _toggle_mouse_capture() -> void:
	pass
	#if(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
	#	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	#else:
	#	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if(tool_open):
		if(ImGui.Begin("Demo")):
			ImGui.BeginTabBar("Categories")
			if(ImGui.BeginTabItem("Player")):
				draw_player_debug.emit(_delta)
				ImGui.EndTabItem()
			if(ImGui.BeginTabItem("Environment")):
				ImGui.EndTabItem()	
			ImGui.EndTabBar()	
			
		ImGui.End()
