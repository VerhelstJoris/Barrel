class_name CollisionPhysicsBody extends RigidBody3D

signal on_rigidbody_collision( global_pos : Vector3, normal : Vector3, hit_impulse : Vector3, hit_velocity : Vector3, other_rid : RID, other_object : Object, self_rigid_body: CollisionPhysicsBody  )

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if(!contact_monitor):
		return
		
	var col_amount: int = state.get_contact_count()
	for col_id in col_amount:
		var global_pos: Vector3 = state.get_contact_collider_position(col_id)
		var local_normal: Vector3 = state.get_contact_local_normal(col_id)
		var impulse : Vector3 = state.get_contact_impulse(col_id)
		var velocity : Vector3 = state.get_contact_local_velocity_at_position(col_id)
		var col_rid : RID = state.get_contact_collider(col_id)
		var other_obj : RID = state.get_contact_collider_object(col_id)
		
		on_rigidbody_collision.emit(global_pos, local_normal,impulse, velocity, col_rid, other_obj , self)
