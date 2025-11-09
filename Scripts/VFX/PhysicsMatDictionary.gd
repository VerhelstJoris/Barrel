
class_name PhysicsMatDictionary extends  Resource

@export var physics_material_map : Dictionary[PhysicsMaterial, PackedScene]
@export var fallback : PackedScene

func _find_scene_from_material(mat : PhysicsMaterial) -> PackedScene:
	if(!mat):
		return fallback
	
	if(physics_material_map.has(mat)):
		return physics_material_map[mat]

	return fallback

func _find_scene_from_physicsbody(body: PhysicsBody3D)	-> PackedScene:
	if(!body):
		return fallback

	if(body && body.physics_material_override):
		return _find_scene_from_material(body.physics_material_override)
		
	return fallback	