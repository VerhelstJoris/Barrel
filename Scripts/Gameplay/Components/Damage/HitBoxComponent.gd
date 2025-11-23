@icon("res://DEBUG/Icons/Ico_Hitbox.png")
class_name HitboxComponent extends Node

@export var shapes_to_register_hits_from : Array[PhysicsBody3D]
@export var rigidbodies_to_register_collisions_from : Array[CollisionPhysicsBody]

const damaged_signal_name : String = "on_damaged"

signal on_shape_hit(new : float, old : float)

func _ready() -> void:
	_register_shape_signals()
	
func _register_shape_signals() -> void:
	for shape in shapes_to_register_hits_from:
		shape.add_user_signal(damaged_signal_name, ["Hit", "Damage"])
		shape.connect(damaged_signal_name, Callable(self, "_on_shape_damaged"))

	for rb in rigidbodies_to_register_collisions_from:
		rb.on_rigidbody_collision.connect(_on_rigidbody_collision)

func _on_shape_damaged(_hit : Dictionary, _damage : float) -> void:
	on_shape_hit.emit(0,_damage)
	

func _on_rigidbody_collision(_global_pos : Vector3, _normal : Vector3, _hit_impulse : Vector3, _hit_velocity : Vector3, _other_rid : RID, _other_object : Object, _self_rigid_body: CollisionPhysicsBody ) -> void:
	var impulse_strength : float = _hit_impulse.length()
	if(impulse_strength > .2):
		on_shape_hit.emit(0, impulse_strength)
	