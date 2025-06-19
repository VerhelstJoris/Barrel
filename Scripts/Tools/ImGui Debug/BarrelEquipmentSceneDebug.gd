class_name BarrelEquipmentSceneDebug extends BarrelSceneDebugNode

@export	var current_equipment : PlayerEquipment

func _ready() -> void:
	if(current_equipment):
		current_equipment.on_equipped.connect(_on_equipped)
		current_equipment.on_unequipped.connect(_on_unequipped)
	pass
	
func _draw(_delta: float) -> void:
	super(_delta)
	if(ImGui.CollapsingHeader("pistol")):
		ImGui.Text("yippee")
		_draw_children(_delta)

func _on_equipped() -> void:
	BarrelDebugWindow.draw_current_equipment.connect(_draw)
	pass
	
func _on_unequipped() -> void:
	BarrelDebugWindow.draw_current_equipment.disconnect(_draw)
	pass
	
