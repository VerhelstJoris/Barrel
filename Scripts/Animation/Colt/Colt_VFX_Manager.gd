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
	
func _on_bullet_fired() -> void:
	_randomize_fire_vfx()
	_activate_initial_muzzle_vfx()
	_activate_main_muzzle_vfx()
	_activate_fire_cylinder_vfx()
	

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
	
func _toggle_main_muzzle_vfx(_visible : bool) -> void:
	barrel_muzzle_main_vfx.visible = _visible

func _toggle_initial_muzzle_vfx(_visible : bool) -> void:
	for vfx_node in barrel_muzzle_initial_vfx:
		vfx_node.visible = _visible

func _toggle_cylinder_fire_vfx(_visible : bool) -> void:
	for vfx_node in cylinder_fire_vfx:
		vfx_node.visible = _visible