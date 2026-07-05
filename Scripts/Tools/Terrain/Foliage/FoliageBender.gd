class_name FoliageBender extends Area3D

var currently_registered_chunks : Array[FoliageChunk]

var prev_transform : Transform3D


func _should_update() -> bool:
	var new_transform : Transform3D = get_global_transform()
	if(new_transform.is_equal_approx(prev_transform)):
		prev_transform = new_transform
		return false
	prev_transform = new_transform

	return true
	
func _process(_delta: float) -> void:
	if(!_should_update()):
		return

	var new_chunks : Array[FoliageChunk]
	var to_unregister_from : Array[FoliageChunk] = currently_registered_chunks.duplicate()
	
	for area in get_overlapping_areas():
		if(area.has_meta(FoliageChunk.foliage_node_meta)):
			var found_chunk : FoliageChunk = NodeUtils._retrieve_node_meta_from_node(FoliageChunk.foliage_node_meta, area)
			new_chunks.append(found_chunk)

	for chunk in new_chunks:
		if(!currently_registered_chunks.has(chunk)):
			_register_to_chunk(chunk)
			pass
			
		to_unregister_from.erase(chunk)	
	
	for unreg_chunk in to_unregister_from:
		_unregister_from_chunk(unreg_chunk)
	
func _register_to_chunk(chunk : FoliageChunk) -> void:
	currently_registered_chunks.append(chunk)
	if(!chunk.current_benders_arr.has(self)):
		chunk.current_benders_arr.append(self)
	print("register")
	
func _unregister_from_chunk(chunk : FoliageChunk) -> void:
	currently_registered_chunks.erase(chunk)
	chunk.current_benders_arr.erase(self)
	print("unregister")
