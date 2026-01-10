class_name BarrelInteractorDebugNode extends BarrelSceneDebugNode

@export var interactor : InteractorComponent

func _get_name() -> String:
	return interactor.name

func _draw_contents(_delta: float) -> void:
	
	if(interactor.current_hovered_interactable != null):
		ImGui.Text("Current Interactable: %s" % interactor.current_hovered_interactable.owner.name)
		_draw_interactable_data_info(interactor.current_hovered_interactable.interact_data)
	else:
		ImGui.TextColored(Color.RED ,"No Currently Hovered over Interactable!")

	var draw_target : Array[bool] = [interactor.DEBUG_draw_target]
	if(ImGui.Checkbox("Draw Interactor Target?", draw_target)):
		interactor.DEBUG_draw_target = draw_target[0]
		
	super(_delta)

func _draw_interactable_data_info(data : InteractableDataAsset)	-> void:
	if(data == null):
		return
		
	ImGui.Indent()
	ImGui.Text("Interactable Name: %s " % data.interactable_display_name)
	ImGui.Text("Interactable Description: %s " % data.interaction_description)
	
	var type :  InteractableDataAsset.EInteractionType = data.type
	ImGui.Text("Interactable Type: %s " % InteractableDataAsset.EInteractionType.keys()[type])
	if(type == InteractableDataAsset.EInteractionType.Equip):
		ImGui.Text("Pick up Self %s " % data.pick_up_self)
		if(data.alternative_interaction_item):
			ImGui.Text("Alt Pickup Item: %s " % data.alternative_interaction_item)
		else:
			ImGui.Text("Alt Pickup Item: NONE ")


	ImGui.Unindent()