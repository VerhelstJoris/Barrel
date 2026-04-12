@tool
class_name FoliageCreatorEditor extends Node

@export_group("Foliage Chunk Creation")
@export var terrain_node : Terrain3D
@export var chunk_parent_node : Node3D
@export var chunk_size : float = 10.0
@export var chunk_scene : PackedScene

@export_tool_button("Regenerate Chunks", "Callable") var chunk_create_action = _create_foliage_chunks

@export_group("Foliage Chunk Population")

var is_updating: bool = false

func _create_foliage_chunks() -> void:
	if(terrain_node == null):
		push_error("Unable to generat foliage chunks on ", name, " because no terrain is specified!")

	if(chunk_parent_node == null):
		push_error("Unable to generat foliage chunks on ", name, " because no parent node for the new chunks is specified!")
		
	if(chunk_scene == null):
		push_error("Unable to generat foliage chunks on ", name, " because no chunk scene new chunks is specified!")
		
	if is_updating:
		return
		
	is_updating = true	

	_remove_old_chunks()
	
	_fill_all_regions()
	
	is_updating = false
	return
	
func _remove_old_chunks() -> void:
	var id : int = 0
	for child in chunk_parent_node.get_children():
		#rename them so the new nodes we make don't conflict
		child.name = "garbage" + str(id)
		id= id+1
		child.queue_free()

func _fill_all_regions() -> int:
	var _region_array : Dictionary= terrain_node.data.get_regions_all()
	for id in _region_array.keys():
		var region : Terrain3DRegion = terrain_node.data.get_region(id)
		if(region != null):
			_fill_region(id, region)
	
	return 0
	
	
func _fill_region(region_id : Vector2i, region : Terrain3DRegion) -> void:
	var region_parent_node : Node3D = Node3D.new()
	chunk_parent_node.add_child(region_parent_node, true)
	region_parent_node.owner = get_tree().edited_scene_root
	
	var region_size_meters : float = region.region_size * terrain_node.vertex_spacing
	var half_size : Vector2 = Vector2(region_size_meters * 0.5, region_size_meters * 0.5)
	var pos : Vector2 = ((region_id) * region_size_meters) + half_size
	region_parent_node.global_position = Vector3(pos.x, 0, pos.y)

	region_parent_node.name = chunk_parent_node.name + "_Region_" + str(region_id.x) + "_" + str(region_id.y)
	
	_create_chunk_at(region_id,region_size_meters,region_parent_node)

func _create_chunk_at(region_id : Vector2i, region_size : float, parent_node : Node3D) -> Node3D:
	var new_instance: Node3D = chunk_scene.instantiate()
	
	var half_size : Vector2 = Vector2(region_size * 0.5, region_size * 0.5)
	var pos : Vector2 = ((region_id) * region_size) + half_size

	parent_node.add_child(new_instance, true)
	new_instance.owner = get_tree().edited_scene_root

	new_instance.global_position = Vector3(pos.x, 0, pos.y)

	return new_instance