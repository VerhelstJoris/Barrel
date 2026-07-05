class_name NodeUtils extends Node

static func _retrieve_node_meta_from_owner(property_name : String, from_node : Node) -> Variant:
	if(from_node == null):
		push_error("Try to retrieve metadata from invalid node")
		return null

	if(!from_node.get_owner().has_meta(property_name)):
		push_error(from_node.name , " Cannot find metadata " , property_name ," via metadata on owner ", from_node.get_owner().name)
		return null

	return from_node.get_owner().get_meta(property_name)

static func _retrieve_node_meta_from_node(property_name : String, from_node : Node) -> Variant:
	if(from_node == null):
		push_error("Try to retrieve metadata from invalid node")
		return null

	if(!from_node.has_meta(property_name)):
		push_error(from_node.name , " Cannot find metadata " , property_name ," via metadata")
		return null

	return from_node.get_meta(property_name)	
	
static func _add_node_meta_to_owner(property_name : String, from_node : Node, data_to_set : Variant) -> void:
	if(from_node == null):
		push_error("Cannot add metadata to null parent!")
		return
		
	from_node.owner.set_meta(property_name, data_to_set)

static func _add_node_meta_to_node(property_name : String, from_node : Node, data_to_set : Variant) -> void:
	if(from_node == null):
		push_error("Cannot add metadata to null node!")
		return

	from_node.set_meta(property_name, data_to_set)	