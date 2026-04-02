class_name CommonAlgorithms extends Node


static func _weighted_random_from_weights(weights : Array[float]) -> int:
	var total_weight: float = 0.0
	
	for weight in weights:
		total_weight = total_weight + weight

	var random : float = randf() * total_weight

	var cursor : float = 0.0
	var chosen_index : int = 0
	
	for weight in weights:
		cursor += weight
		if(cursor >= random):
			return chosen_index
		chosen_index = chosen_index +1

	return 0