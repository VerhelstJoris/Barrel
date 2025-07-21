class_name ColtVFXManager extends Node3D

var colt_equipment : PlayerEquipmentPistol = null

@export_group("Fire Muzzle Flash")
@export var barrel_muzzle_initial_vfx_parent : Node3D
@export var barrel_muzzle_initial_vfx : Array[Node3D]
@export_range(1.5, 5, 0.01) var barrel_muzzle_flash_min_scale : float = 2
@export_range(1.5, 5, 0.01) var barrel_muzzle_flash_max_scale : float = 3
@export var barrel_vfx_initial_active_time : float = 0.04

@export var barrel_muzzle_main_vfx : Node3D
@export var barrel_muzzle_main_delay : float = 0.02
@export var barrel_muzzle_main_active_time : float = 0.02

@export_group("Fire Muzzle Smoke")
@export var muzzle_smoke_vfx : MeshInstance3D
@export var muzzle_smoke_grow_rate : float = 2.5 
@export var muzzle_smoke_max_time : float = 1
@export var muzzle_smoke_decay_rate : float = 4
const muzzle_smoke_grow_shader_param : String = "AlphaGrow"
const muzzle_smoke_shrink_shader_param : String = "AlphaShrink"


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
	
	_toggle_initial_muzzle_vfx(false)
	_toggle_main_muzzle_vfx(false)
	_toggle_cylinder_fire_vfx(false)
	_reset_muzzle_smoke_vfx_shader_params()

func _process(delta: float) -> void:
	_process_muzzle_smoke(delta)
	
func _process_muzzle_smoke(delta : float) -> void:
	if muzzle_smoke_active:
		muzzle_smoke_current_timer += delta
		if(muzzle_smoke_current_timer > muzzle_smoke_max_time):
			_deactivate_muzzle_smoke()
		
	if(muzzle_smoke_decaying):
		muzzle_smoke_decay_timer += delta
		if(muzzle_smoke_decay_timer > muzzle_smoke_decay_duration):
			muzzle_smoke_active = false
			muzzle_smoke_decaying = false

	
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
	muzzle_smoke_growth_tween.tween_method(_set_grow_shader_param,  muzzle_smoke_vfx.get_instance_shader_parameter(muzzle_smoke_grow_shader_param), 1.0, 1.0 / muzzle_smoke_grow_rate)
	muzzle_smoke_active = true

func _deactivate_muzzle_smoke() -> void:
	muzzle_smoke_current_timer = 0
	muzzle_smoke_decaying = true
	muzzle_smoke_decay_tween = create_tween()
	muzzle_smoke_growth_tween = create_tween()
	muzzle_smoke_decay_duration = 1.0 / muzzle_smoke_decay_rate
	muzzle_smoke_decay_tween.tween_method(_set_shrink_shader_param,  0.0, 1.0, muzzle_smoke_decay_duration)
	muzzle_smoke_growth_tween.tween_method(_set_grow_shader_param,  1.0, 0.0, muzzle_smoke_decay_duration)

func _interrupt_muzzle_smoke_decay() -> void:
	muzzle_smoke_decay_tween.stop()
	muzzle_smoke_growth_tween.stop()
	muzzle_smoke_decaying = false
	_set_shrink_shader_param(0)


func _set_grow_shader_param(value : float) -> void:
	muzzle_smoke_vfx.set_instance_shader_parameter(muzzle_smoke_grow_shader_param, value)

func _set_shrink_shader_param(value : float) -> void:
	muzzle_smoke_vfx.set_instance_shader_parameter(muzzle_smoke_shrink_shader_param, value)
	
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
	for vfx_node in barrel_muzzle_initial_vfx:
		vfx_node.visible = _visible

func _toggle_cylinder_fire_vfx(_visible : bool) -> void:
	for vfx_node in cylinder_fire_vfx:
		vfx_node.visible = _visible
