class_name BarrelEquipmentSceneDebug extends BarrelSceneDebugNode
	

var equipment : PlayerEquipment

func _ready() -> void:
	super()
	await owner.ready 
	equipment = owner as PlayerEquipment
	pass
	
func _draw_contents(_delta: float) -> void:
	super(_delta)
	ImGui.Text("yippee")

func _on_equipped() -> void:
	pass
	
func _on_unequipped() -> void:
	pass
	
