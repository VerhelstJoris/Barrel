@icon("res://DEBUG/Icons/Ico_Skull.png")
class_name DeathComponent extends Node

@export var hitbox : HitboxComponent

@export var take_hitbox_direct_damage : bool = true
@export var min_direct_damage : float = 5.0
@export var take_hitbox_collision_damage : bool = true
@export var min_collision_impulse : float = 5.0

@export var on_death_vfx : PackedScene
@export var death_vfx_spawn_node : Node3D


func _ready() -> void:
	if(hitbox):
		if(take_hitbox_direct_damage):
			hitbox.on_hit_direct.connect(_on_direct_damage)	
		if(take_hitbox_collision_damage):
			hitbox.on_hit_collision.connect(_on_collision_damage)
		
func _on_direct_damage(_global_pos : Vector3, _normal : Vector3, _other_object : Object, _damage : float) -> void:
	if(_damage < min_direct_damage):
		return
	
	_die()

func _on_collision_damage( _global_pos : Vector3, _normal : Vector3, hit_impulse : Vector3, _hit_velocity : Vector3, _other_object : Object) -> void:
	if(hit_impulse.length() < min_collision_impulse):
		return
		
	_die()	
		
func _die():
	if(on_death_vfx && death_vfx_spawn_node):
		var created_effect : VFXInstance = on_death_vfx.instantiate()
		owner.get_parent().add_child(created_effect)
		created_effect.set_global_position(death_vfx_spawn_node.get_global_position())
		created_effect.quaternion = death_vfx_spawn_node.quaternion
		
	owner.queue_free()

