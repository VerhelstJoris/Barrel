@icon("res://DEBUG/Icons/Ico_Hitbox.png")
class_name HitboxComponent extends Node

@export var shapes_to_register_hits_from : Array[PhysicsBody3D]
@export var rigidbodies_to_register_collisions_from : Array[CollisionPhysicsBody]

const damaged_signal_name : String = "direct_damage"

signal on_hit_collision( global_pos : Vector3, normal : Vector3, hit_impulse : Vector3, hit_velocity : Vector3, other_object : Object)
signal on_hit_direct(_global_pos : Vector3, normal : Vector3,other_object : Object, damage : float)

var collisions_enabled : bool = true

var bodies_rid_arr : Array[RID]
var shape_rid_arr : Array[RID]

func _ready() -> void:
	_register_shape_signals()
	
func _register_shape_signals() -> void:
	shape_rid_arr.resize(shapes_to_register_hits_from.size())
	for shape in shapes_to_register_hits_from:
		shape.add_user_signal(damaged_signal_name, ["Hit", "Damage"])
		shape.connect(damaged_signal_name, _on_shape_hit)
		shape_rid_arr.append(shape.get_rid())
		
	bodies_rid_arr.resize(rigidbodies_to_register_collisions_from.size())
	for rb in rigidbodies_to_register_collisions_from:
		rb.on_rigidbody_collision.connect(_on_rigidbody_collision)
		bodies_rid_arr.append(rb.get_rid())

func _on_shape_hit(_hit : Dictionary, _damage : float) -> void:
	if(collisions_enabled):
		on_hit_direct.emit(_hit.position, _hit.normal, _hit.collider, _damage)
	
func _on_rigidbody_collision(_global_pos : Vector3, _normal : Vector3, _hit_impulse : Vector3, _hit_velocity : Vector3, _other_rid : RID, _other_object : Object, _self_rigid_body: CollisionPhysicsBody ) -> void:
	if(collisions_enabled):
		on_hit_collision.emit(_global_pos, _normal, _hit_impulse, _hit_velocity, _other_object)	
	
func _set_collisions_enabled(enabled : bool) -> void:
	if(collisions_enabled == enabled):
		return
	
	collisions_enabled = enabled
	for shape in shapes_to_register_hits_from:
		if(!enabled):
			shape.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			shape.process_mode = Node.PROCESS_MODE_INHERIT
		