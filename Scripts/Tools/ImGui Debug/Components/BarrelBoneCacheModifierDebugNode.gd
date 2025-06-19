class_name BarrelBoneCacheModifierDebugNode extends BarrelSceneDebugNode

@export var BoneCacheModifier : SkeletonRevolverBoneCacheModifier

func _draw(_delta : float) -> void:
	super(_delta)
	if(BoneCacheModifier != null):
		ImGui.Text(str(BoneCacheModifier))
	else:
		ImGui.TextColored(Color.DARK_RED, "No Modifier attached to this node!")
		
