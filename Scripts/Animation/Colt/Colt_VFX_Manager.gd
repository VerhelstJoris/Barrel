class_name ColtVFXManager extends Node

var colt_equipment : PlayerEquipmentPistol = null

@export_group("Fire Muzzle Flash")
@export var barrel_muzzle_initial_vfx_parent : Node3D
@export var barrel_muzzle_initial_vfx : Array[Node3D]
@export_range(1.5, 5, 0.01) var barrel_muzzle_flash_min_scale : float = 2
@export_range(1.5, 5, 0.01) var barrel_muzzle_flash_max_scale : float = 3
@export var barrel_vfx_initial_active_time : float = 0.04
@export var barrel_muzzle_flash_light : Node3D

@export var barrel_muzzle_main_vfx : Node3D
@export var barrel_muzzle_main_delay : float = 0.02
@export var barrel_muzzle_main_active_time : float = 0.02

@export_group("Fire Muzzle Smoke Shader Settings")
@export var muzzle_smoke_grow_rate : float = 2.5 
@export var muzzle_smoke_max_time : float = 1
@export var muzzle_smoke_decay_rate : float = 4
@export var muzzle_smoke_instant_decay_rate : float = 8
const muzzle_smoke_grow_shader_param : String = "AlphaGrow"
const muzzle_smoke_shrink_shader_param : String = "AlphaShrink"

@export_group("Fire Muzzle Smoke Line Renderer Settings")
@export var smoke_renderer : LineRenderer
@export var _point_amount : int = 75
@export var _smoke_point_tracking_time : float = 4.0
@export var _muzzle_smoke_start_width:float = 0.1
@export var _point_thickness_growth_per_second : float = 0.5

@export var min_muzzle_smoke_move_speed : Vector3 = Vector3(-0.1, 0.2, -0.1)
@export var max_muzzle_smoke_move_speed : Vector3 = Vector3(0.1, 0.5, 0.1)
@export var muzzle_smoke_averaging_speed : float = 15

@export_subgroup("length subdiv")
@export var subdivide_long_polys : bool = true
@export var long_poly_max_length : float = 0.2
@export var debug_draw_length_subdiv : bool = true

@export_subgroup("sharpness subdiv")
@export var subdivide_sharp_polys : bool = true
@export var min_subdiv_dist : float = 0.05
@export var debug_draw_sharp_subdiv : bool = true
var max_sharp_angle_rad : float
@export var max_sharp_angle_degree : float = 40:
	set(new_value):
		max_sharp_angle_degree = new_value
		max_sharp_angle_rad = deg_to_rad(max_sharp_angle_degree)

var _smoke_add_point_timer : float = 0.0
var muzzle_positions : Array[Vector3]
var muzzle_smoke_width_arr : Array[float]

var muzzle_smoke_growth_tween : Tween
var muzzle_smoke_decay_tween : Tween
var muzzle_smoke_current_timer : float = 0.0
var muzzle_smoke_decay_timer : float = 0.0
var muzzle_smoke_active : bool = false
var muzzle_smoke_decaying : bool = false
var muzzle_smoke_decay_duration : float = 0.0

@export_group("Fire Cylinder Flash")
@export var cylinder_fire_vfx : Array[Node3D]
@export var cylinder_fire_vfx_active : float = 0.02
@export_range(1, 3, 0.01) var cylinder_fire_min_scale : float = 1.5
@export_range(1, 3, 0.01) var cylinder_fire_max_scale : float = 2

func _ready() -> void:
	colt_equipment = get_owner() as PlayerEquipmentPistol
	colt_equipment.on_fired.connect(_on_bullet_fired)
	colt_equipment.on_holstered.connect(_on_start_holstering)
	colt_equipment.on_unholstered.connect(_on_start_unholstering)

	max_sharp_angle_degree = max_sharp_angle_degree
	
	_toggle_initial_muzzle_vfx(false)
	_toggle_main_muzzle_vfx(false)
	_toggle_cylinder_fire_vfx(false)
	_reset_muzzle_smoke_vfx_shader_params()

func _physics_process(delta: float) -> void:
	_process_muzzle_smoke(delta)
	_process_muzzle_smoke_points(delta)

func _on_start_holstering() -> void:
	_start_muzzle_smoke_decay(muzzle_smoke_instant_decay_rate)

func _on_start_unholstering() -> void:
	_reset_vars()
	
func _process_muzzle_smoke(delta : float) -> void:
	if muzzle_smoke_active:
		muzzle_smoke_current_timer += delta
		if(muzzle_smoke_current_timer > muzzle_smoke_max_time):
			_start_muzzle_smoke_decay(muzzle_smoke_decay_rate)
		
	if(muzzle_smoke_decaying):
		muzzle_smoke_decay_timer += delta
		if(muzzle_smoke_decay_timer > muzzle_smoke_decay_duration):
			_reset_vars()
			
func _reset_vars() -> void:
	muzzle_positions.clear()
	muzzle_smoke_width_arr.clear()
	muzzle_smoke_active = false
	muzzle_smoke_decaying = false
	smoke_renderer.points.clear()
	smoke_renderer.pre_computed_thickness_arr.clear()
	_reset_muzzle_smoke_vfx_shader_params()
	

func _add_muzzle_smoke_point() -> void:
	if(muzzle_positions.size() >= _point_amount):
		muzzle_positions.pop_back()
		muzzle_smoke_width_arr.pop_back()

	muzzle_positions.push_front(smoke_renderer.get_global_position())
	muzzle_smoke_width_arr.push_front(_muzzle_smoke_start_width)
	
func _process_muzzle_smoke_points(_delta : float) -> void:
	if muzzle_smoke_active:
		_update_existing_muzzle_points(_delta)

		_smoke_add_point_timer += _delta
		if(_smoke_add_point_timer > _smoke_point_tracking_time / _point_amount):
			_add_muzzle_smoke_point()
			_smoke_add_point_timer = 0
		
		if(!muzzle_positions.is_empty()):
			smoke_renderer.points = muzzle_positions
			smoke_renderer.pre_computed_thickness_arr = muzzle_smoke_width_arr
	
func _update_existing_muzzle_points(_delta : float) -> void:
	var added : Vector3= Vector3(randf_range(min_muzzle_smoke_move_speed.x, max_muzzle_smoke_move_speed.x) ,
		randf_range(min_muzzle_smoke_move_speed.y, max_muzzle_smoke_move_speed.y),
		randf_range(min_muzzle_smoke_move_speed.z, max_muzzle_smoke_move_speed.z)) * _delta

	var thickness_delta_add : float = _delta * _point_thickness_growth_per_second
	for id in muzzle_positions.size():
		muzzle_positions[id] +=  added
		muzzle_smoke_width_arr[id] += thickness_delta_add
		
	for id in range(1, muzzle_positions.size() -1):
		#average x/z of position out to between previous and next point
		muzzle_positions[id] = lerp(muzzle_positions[id], (muzzle_positions[id -1] + muzzle_positions[id + 1]) /2, _delta * muzzle_smoke_averaging_speed)
			

	#only process the first X points if possible	
	var points_to_process : int = min(15, muzzle_positions.size() -1)	
	for id in points_to_process:
		if( id < 1):	
			continue
			
		var new_id : int = _check_subdivide_long_poly(id)	
		if(new_id != id):
			continue

		_check_subdivide_sharp_poly(id)	
					
func _check_subdivide_long_poly(current_id : int) -> int:
	var A:Vector3 = muzzle_positions[current_id]
	var B: Vector3 = muzzle_positions[current_id + 1]
	var dist : float = A.distance_to(B)
	if(subdivide_long_polys && dist > long_poly_max_length):
		var sub_amount : int =  int(dist / long_poly_max_length)
		var debug_points : PackedVector3Array

		if(debug_draw_length_subdiv):
			debug_points.push_back(A)
			DebugDraw3D.draw_line_path(PackedVector3Array([A,B]),Color(1,0,0),1.5)

		for j in sub_amount:
			var alpha : float = float(j +1)/ (sub_amount + 1)
			var new_pos : Vector3 = lerp(A, B,alpha)
			current_id = current_id +1
			muzzle_positions.insert(current_id, new_pos)
			muzzle_smoke_width_arr.insert(current_id, lerp(muzzle_smoke_width_arr[current_id], muzzle_smoke_width_arr[current_id +1], alpha))
			debug_points.push_back(new_pos)
			

		if(debug_draw_length_subdiv):
			debug_points.push_back(B)
			DebugDraw3D.draw_line_path(debug_points,Color(0,1,0),1.5)
			
	return current_id
			
func _check_subdivide_sharp_poly(current_id : int) -> bool:
	if(subdivide_sharp_polys && current_id > 1 && current_id < muzzle_positions.size() -2):
		var A :Vector3 = muzzle_positions[current_id-2]
		var B :Vector3 = muzzle_positions[current_id -1]
		var C: Vector3 = muzzle_positions[current_id]
		var D: Vector3 = muzzle_positions[current_id+1]
		
		if(C.distance_to(D) < min_subdiv_dist):
			return false
		
		var angleDot : float =  (C-B).normalized().dot((C -D).normalized())
		if(abs(acos(angleDot)) < max_sharp_angle_rad):
			muzzle_positions[current_id] = _bezier_4(A,B,C,D,0.5)
			if(debug_draw_sharp_subdiv):
				DebugDraw3D.draw_line_path(PackedVector3Array( [A,B,C,D]) , Color(1,0,0),1.5)
				DebugDraw3D.draw_line_path(PackedVector3Array( [A,B,muzzle_positions[current_id],D]) , Color(0,1,0),1.5)

			return true
	return false

func _bezier_2( A : Vector3 , B : Vector3, alpha : float) -> Vector3:
	return lerp(A, B, alpha)

func _bezier_3( A : Vector3 , B : Vector3, C : Vector3, alpha : float) -> Vector3:
	return lerp(_bezier_2(A, B, alpha), _bezier_2(B, C, alpha), alpha)

func _bezier_4( A: Vector3 , B : Vector3, C : Vector3, D : Vector3, alpha : float) -> Vector3:
	return lerp(_bezier_3(A, B, C, alpha), _bezier_3(B, C, D, alpha), alpha)
	
func _on_bullet_fired() -> void:
	_randomize_fire_vfx()
	_activate_initial_muzzle_vfx()
	_activate_main_muzzle_vfx()
	_activate_fire_cylinder_vfx()
	_activate_muzzle_smoke()
	
func _activate_initial_muzzle_vfx() -> void:
	_toggle_initial_muzzle_vfx(true)
	await get_tree().create_timer(barrel_vfx_initial_active_time).timeout
	_toggle_initial_muzzle_vfx(false)

func _activate_fire_cylinder_vfx()-> void:
	_toggle_cylinder_fire_vfx(true)
	await get_tree().create_timer(cylinder_fire_vfx_active).timeout
	_toggle_cylinder_fire_vfx(false)
	
func _activate_main_muzzle_vfx() -> void:
	await get_tree().create_timer(barrel_muzzle_main_delay).timeout
	_toggle_main_muzzle_vfx(true)
	await get_tree().create_timer(barrel_muzzle_main_active_time).timeout
	_toggle_main_muzzle_vfx(false)
	
func _activate_muzzle_smoke() -> void:
	muzzle_smoke_current_timer = 0.0 #reset the timer before early out
	muzzle_smoke_decay_timer = 0.0
	var interrupting_already_active : bool = false
	
	if(muzzle_smoke_decaying):
		#if we're already decaying back down to nothing
		_interrupt_muzzle_smoke_decay()
		interrupting_already_active = true
	elif(muzzle_smoke_active):
		return
		
	if(!interrupting_already_active):
		_reset_muzzle_smoke_vfx_shader_params()
		
	muzzle_smoke_growth_tween = create_tween()
	muzzle_smoke_growth_tween.tween_method(_set_grow_shader_param,  smoke_renderer.get_instance_shader_parameter(muzzle_smoke_grow_shader_param), 1.0, 1.0 / muzzle_smoke_grow_rate)
	muzzle_smoke_active = true

func _start_muzzle_smoke_decay(decay_rate : float) -> void:
	muzzle_smoke_current_timer = 0
	muzzle_smoke_decaying = true
	muzzle_smoke_decay_tween = create_tween()
	muzzle_smoke_growth_tween = create_tween()
	muzzle_smoke_decay_duration = 1.0 / decay_rate
	var current_growth : float = smoke_renderer.get_instance_shader_parameter(muzzle_smoke_grow_shader_param)
	var current_decay : float = smoke_renderer.get_instance_shader_parameter(muzzle_smoke_shrink_shader_param)
	muzzle_smoke_decay_tween.tween_method(_set_shrink_shader_param, current_decay, 1.0, muzzle_smoke_decay_duration)
	muzzle_smoke_growth_tween.tween_method(_set_grow_shader_param,  current_growth, 0.0, muzzle_smoke_decay_duration)

func _interrupt_muzzle_smoke_decay() -> void:
	muzzle_smoke_decay_tween.stop()
	muzzle_smoke_growth_tween.stop()
	muzzle_smoke_decaying = false
	_set_shrink_shader_param(0)
	
func _set_grow_shader_param(value : float) -> void:
	smoke_renderer.set_instance_shader_parameter(muzzle_smoke_grow_shader_param, value)

func _set_shrink_shader_param(value : float) -> void:
	smoke_renderer.set_instance_shader_parameter(muzzle_smoke_shrink_shader_param, value)
	
func _randomize_fire_vfx() -> void:
	barrel_muzzle_initial_vfx_parent.rotation.y = randf() * 360
	for vfx_node in barrel_muzzle_initial_vfx:
		_randomize_node_scale(vfx_node, barrel_muzzle_flash_min_scale, barrel_muzzle_flash_max_scale)
		
	for cyl_vfx_node in cylinder_fire_vfx:
		_randomize_node_scale(cyl_vfx_node, cylinder_fire_min_scale, cylinder_fire_max_scale)
		
func _randomize_node_scale(node : Node3D, min_scale : float , max_scale : float) -> void:
	randomize()
	var new_scale : float = randf_range(min_scale, max_scale)
	node.scale = Vector3.ONE * new_scale
	
func _reset_muzzle_smoke_vfx_shader_params() -> void:
	_set_grow_shader_param(0)
	_set_shrink_shader_param(0)

func _toggle_main_muzzle_vfx(_visible : bool) -> void:
	barrel_muzzle_main_vfx.visible = _visible

func _toggle_initial_muzzle_vfx(_visible : bool) -> void:
	if(barrel_muzzle_flash_light):
		barrel_muzzle_flash_light.visible = _visible
	for vfx_node in barrel_muzzle_initial_vfx:
		vfx_node.visible = _visible

func _toggle_cylinder_fire_vfx(_visible : bool) -> void:
	for vfx_node in cylinder_fire_vfx:
		vfx_node.visible = _visible
