@icon("res://DEBUG/Icons/Ico_Hitbox.png")
class_name HitboxComponent extends Node

@export var shapes_to_register_hits_from : Array[PhysicsBody3D]
@export var rigidbodies_to_register_collisions_from : Array[CollisionPhysicsBody]

const damaged_signal_name : String = "on_damaged"

signal on_hit_collision( global_pos : Vector3, normal : Vector3, hit_impulse : Vector3, hit_velocity : Vector3, other_object : Object)
signal on_hit_direct(_global_pos : Vector3, normal : Vector3,other_object : Object, damage : float)

func _ready() -> void:
	_register_shape_signals()
	
func _register_shape_signals() -> void:
	for shape in shapes_to_register_hits_from:
		shape.add_user_signal(damaged_signal_name, ["Hit", "Damage"])
		shape.connect(damaged_signal_name, Callable(self, "_on_shape_hit"))

	for rb in rigidbodies_to_register_collisions_from:
		rb.on_rigidbody_collision.connect(_on_rigidbody_collision)

func _on_shape_hit(_hit : Dictionary, _damage : float) -> void:
	on_hit_direct.emit(_hit.position, _hit.normal, _hit.collider, _damage)
	
func _on_rigidbody_collision(_global_pos : Vector3, _normal : Vector3, _hit_impulse : Vector3, _hit_velocity : Vector3, _other_rid : RID, _other_object : Object, _self_rigid_body: CollisionPhysicsBody ) -> void:
	on_hit_collision.emit(_global_pos, _normal, _hit_impulse, _hit_velocity, _other_object)	
	