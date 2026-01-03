class_name ColtVFXManagerDebugNode extends BarrelSceneDebugNode

@export var manager : ColtVFXManager


func _draw_contents(_delta : float) -> void:
	ImGui.Indent()
	if(ImGui.CollapsingHeader("Muzzle Smoke")):
		_draw_muzzle_smoke_details(_delta)
		
	ImGui.Unindent()
	super(_delta)


func _get_name() -> String:
	return "Colt VFX Manager"		

func _draw_muzzle_smoke_details(_delta : float) -> void:
	if(manager.smoke_renderer):
		ImGui.Text("Alpha Growth : %f" % manager.smoke_renderer.get_instance_shader_parameter(manager.muzzle_smoke_grow_shader_param))
		ImGui.Text("Alpha Decay : %f" % manager.smoke_renderer.get_instance_shader_parameter(manager.muzzle_smoke_shrink_shader_param))

		var smoke_debug : BarrelSceneDebugNode = manager.smoke_renderer.get_child(0)

		if(smoke_debug && !ChildNodesToDisplay.has(smoke_debug)):
			ChildNodesToDisplay.push_back(smoke_debug)