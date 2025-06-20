class_name BarrelBoneCacheModifierDebugNode extends BarrelSceneDebugNode

@export var bone_cache_mod : SkeletonRevolverBoneCacheModifier

func _ready() -> void:
	super()
	await owner.ready
	bone_cache_mod = owner as SkeletonRevolverBoneCacheModifier

func _draw_contents(_delta : float) -> void:
	super(_delta)
	if(bone_cache_mod != null):
		var current_caching : bool = bone_cache_mod.currently_caching
		ImGui.Text("Currently Caching: " + str(current_caching))
		if(current_caching):
			ImGui.Text("Cached Transform: " + str(bone_cache_mod.cached_transform))
	else:
		ImGui.TextColored(Color.DARK_RED, "No Modifier attached to this node!")
		
