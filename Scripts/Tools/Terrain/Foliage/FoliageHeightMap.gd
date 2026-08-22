@tool
class_name FoliageHeightMap extends Resource

# One flat height sample per world grid vertex, baked once from Terrain3D and

@export var data : PackedFloat32Array
@export var stride : int = 0			# vertices per dimension
@export var cell_size : float = 4.0		# metres between vertices
@export var origin : Vector2 = Vector2.ZERO	# world XZ of vertex (0,0)

@export var min_height : float = 0.0
@export var max_height : float = 0.0


func is_valid() -> bool:
	return stride > 0 and data.size() == stride * stride


func height_at_vertex(vx : int, vz : int) -> float:
	if vx < 0 or vz < 0 or vx >= stride or vz >= stride:
		return 0.0
	return data[vx + vz * stride]


func to_byte_array() -> PackedByteArray:
	return data.to_byte_array()
