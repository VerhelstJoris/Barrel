@icon("res://DEBUG/Icons/Ico_Skull.png")
class_name DeathComponent extends Node

@export var hitbox : HitboxComponent

@export_group("Take Damage Settings")
@export var take_hitbox_direct_damage : bool = true
@export var min_direct_damage : float = 5.0
@export var take_hitbox_collision_damage : bool = true
@export var min_collision_impulse : float = 5.0
@export var min_collision_speed : float = 5.0
@export var need_impulse_and_speed_requirements : bool = false

@export_group("On Death Settings")
@export var on_death_vfx : PackedScene
@export var death_vfx_spawn_node : Node3D


@export_group("Damage")
@export var impulse_area : SphereShape3D
@export_group("Damage/Impulse")
@export var apply_radial_impulse : bool = false
@export var radial_impulse_strength : float = 5.0
@export var radial_impulse_fallof_per_distance_unit : float = 0.0
@export_group("Damage/Direct")
@export var apply_radial_damage : bool = false
@export var radial_damage_strength : float = 5.0
@export var radial_damage_fallof_per_distance_unit : float = 0.0

var currently_dying : bool = false

func _ready() -> void:
	if(hitbox):
		if(take_hitbox_direct_damage):
			hitbox.on_hit_direct.connect(_on_direct_damage)	
		if(take_hitbox_collision_damage):
			hitbox.on_hit_collision.connect(_on_collision_damage)
	else:
		push_error("No Hitbox assigned on " ,self.name , ", interactable cannot initialize properly")
		
func _on_direct_damage(_global_pos : Vector3, _normal : Vector3, _other_object : Object, _damage : float) -> void:
	if(_damage < min_direct_damage):
		return
	
	_die()

func _on_collision_damage( _global_pos : Vector3, _normal : Vector3, hit_impulse : Vector3, _hit_velocity : Vector3, _other_object : Object) -> void:
	var impulse_met : bool = hit_impulse.length() > min_collision_impulse
	var speed_met : bool = _hit_velocity.length() > min_collision_speed
	
	if(need_impulse_and_speed_requirements && speed_met && impulse_met):
		_die()
	elif(speed_met || impulse_met):
		_die()
		
func _die() -> void:
	if(currently_dying):
		return
		
	currently_dying = true
	
	_spawn_on_death_vfx()
	_perform_death_blast()

	owner.queue_free()

func _spawn_on_death_vfx() -> void:
	if(on_death_vfx && death_vfx_spawn_node):
		var created_effect : VFXInstance = on_death_vfx.instantiate()
		get_tree().root.add_child(created_effect)
		created_effect.set_global_position(death_vfx_spawn_node.get_global_position())
		created_effect.quaternion = death_vfx_spawn_node.quaternion

func _perform_death_blast() -> void:
	if((apply_radial_impulse || apply_radial_damage)):
		var blast_origin : Vector3 = owner.global_position

		var bodies_to_ignore : Array[RID] = hitbox.bodies_rid_arr
		bodies_to_ignore.append_array(hitbox.shape_rid_arr)
		
		var space_state: PhysicsDirectSpaceState3D = owner.get_world_3d().get_direct_space_state()
		var query = PhysicsShapeQueryParameters3D.new()
		query.shape_rid = impulse_area.get_rid()
		query.transform = owner.get_global_transform()
		query.exclude = bodies_to_ignore

		var results: Array[Dictionary] = space_state.intersect_shape(query)
		for sphere_hit in results:
			if(sphere_hit.collider.owner == owner):
				continue
		
			if sphere_hit.collider is RigidBody3D:
				var ray_query_params := PhysicsRayQueryParameters3D.create(blast_origin, sphere_hit.collider.global_position)
				ray_query_params.collide_with_bodies = true
				ray_query_params.exclude = bodies_to_ignore

				var ray_result : Dictionary = space_state.intersect_ray(ray_query_params)
				if(ray_result == null || ray_result.is_empty()):
					continue	#if the ray somehow hit nothing
				
				if(ray_result.collider != sphere_hit.collider):
					continue # we hit a different collider that we did not expect to be there, something is in the way
				
				var damage_direction : Vector3 = (sphere_hit.collider.global_position - blast_origin).normalized()
				if(apply_radial_impulse):
					var impulse_amount : float = _calculate_falloff_damage(radial_impulse_strength, radial_impulse_fallof_per_distance_unit,impulse_area.radius, blast_origin, ray_result.position)
					var impulse : Vector3 = damage_direction * impulse_amount
					sphere_hit.collider.apply_impulse( impulse, blast_origin)
				if(sphere_hit.collider.has_user_signal(HitboxComponent.damaged_signal_name)):
					sphere_hit["normal"] = damage_direction
					sphere_hit["position"] = ray_result.position
					var damage_amount : float = _calculate_falloff_damage(radial_damage_strength, radial_damage_fallof_per_distance_unit,impulse_area.radius, blast_origin, ray_result.position)
					sphere_hit.collider.emit_signal(HitboxComponent.damaged_signal_name, sphere_hit, damage_amount)
				
				
func _calculate_falloff_damage(base_damage : float, fallof_per_distance_unit : float, max_dist : float,  origin : Vector3, target : Vector3) -> float:
	if(fallof_per_distance_unit <=0):
		return base_damage
		
	var dist : float = min(max_dist, origin.distance_to(target))
	return max(base_damage - (dist * fallof_per_distance_unit) ,0)