class_name LineRenderer extends MeshInstance3D

@export var draw_debug : bool = false

@export var should_draw : bool = true
@export var replace_start_point : Node3D
@export var points: Array[Vector3]
@export var use_global_coords:bool = true
@export var billboard_polys : bool = true
@export var connect_polys : bool = true
@export var flip_y_uv : bool = true

@export_group("Smoothing")
@export var smooth_line : bool = false
@export var smooth_permanent : bool = false
@export_range(0.0, 1.0, 0.01) var smooth_strength : float = 0.5
@export var smooth_iterations : int = 2
@export var smooth_permanent_speed : float = 6.0
@export_range(0.0, 1.0, 0.01) var smooth_vertical_scale : float = 1.0

@export_group("Line Thickness")
@export var use_precomputed_thickness_arr : bool = true
@export var pre_computed_thickness_arr : Array[float]
@export var start_thickness:float = 0.1
@export var growth_rate_per_unit_length : float = 2
@export var thickness_added_per_unit_length : float = 1

var PrevBToAB : Vector3
var PrevBFromAB : Vector3

var global_scale : float 

var camera : Camera3D
var cameraOrigin : Vector3

var total_dist : float   = 0
var current_dist : float = 0
var next_dist : float    = 0

var max_thickness : float = 0

var current_alpha : float = 0
var next_alpha : float =0

var _draw_points : Array[Vector3] = []
var _working_points : Array[Vector3] = []

func _enter_tree() -> void:
	mesh = ImmediateMesh.new()
	
func _ready() -> void:
	camera = get_tree().get_root().get_camera_3d()
	
func _process(_delta: float) -> void:
	mesh.clear_surfaces()

	if(!should_draw):
		return
	
	if points.size() < 2:
		return
		
	if camera == null:
		return

	if(use_precomputed_thickness_arr && pre_computed_thickness_arr.size() != points.size()):
		push_error("Line Renderer points Array (",points.size() , ") and Point Thickness Array (", pre_computed_thickness_arr.size(), ")are not the same size")
		return

	# the start point is pinned before smoothing so the rest of the line relaxes toward where it actually is
	if(replace_start_point != null):
		var additional_pos : Vector3
		if(use_global_coords):
			additional_pos = replace_start_point.get_global_position()
		else:
			additional_pos = replace_start_point.get_position()
		points[0] = additional_pos

	_build_draw_points(_delta)

	cameraOrigin = to_local(camera.get_global_transform().origin) 
	
	_reset_vars_for_drawing(_delta)
	
	mesh.surface_begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
		
	for i in range(_draw_points.size() - 1):
		_draw_next_poly(_draw_points[i],_draw_points[i+1], i)
		
	mesh.surface_end()

# permanent smoothing writes back into points and keeps building on itself, transient rebuilds from the untouched source every frame
func _build_draw_points(_delta : float) -> void:
	if(!smooth_line || points.size() < 3):
		_draw_points = points
		return

	if(smooth_permanent):
		_smooth_positions(points, 1, 1.0 - exp(-smooth_permanent_speed * _delta))
		_draw_points = points
		return

	_working_points.assign(points)
	_smooth_positions(_working_points, smooth_iterations, smooth_strength)
	_draw_points = _working_points

# laplacian relaxation, every interior point eases toward the midpoint of its neighbours while both ends stay pinned
func _smooth_positions(target : Array[Vector3], iterations : int, weight : float) -> void:
	if(iterations <= 0 || weight <= 0.0):
		return

	for _pass_id in iterations:
		# working off a snapshot keeps the pass unbiased by the direction it walks the array
		var source := target.duplicate()
		for i in range(1, source.size() - 1):
			var midpoint : Vector3 = (source[i - 1] + source[i + 1]) * 0.5
			var relaxed : Vector3 = source[i].lerp(midpoint, weight)
			relaxed.y = lerpf(source[i].y, midpoint.y, weight * smooth_vertical_scale)
			target[i] = relaxed
		
func _reset_vars_for_drawing(_delta : float)->void:
	current_alpha = 0
	if(flip_y_uv):
		next_alpha = 1
	else:
		next_alpha = 0
		
	var prev_total_dist: float = total_dist
	total_dist = 0
	for i in range(_draw_points.size() - 1):
		total_dist += _draw_points[i].distance_to(_draw_points[i + 1])
		
	total_dist = lerp(prev_total_dist, total_dist, 1 * _delta)	

	current_dist = 0
	next_dist = 0
	
	max_thickness = start_thickness + (growth_rate_per_unit_length * total_dist) + (thickness_added_per_unit_length * total_dist)
	global_scale = get_global_transform().basis.get_scale().length()
	
func _draw_next_poly(A: Vector3, B : Vector3, index : int )	-> void:
	current_dist = next_dist
	next_dist += A.distance_to(B)
	current_alpha = next_alpha
	next_alpha = next_dist / total_dist
	if(flip_y_uv):
		next_alpha = 1 - next_alpha
		
	if use_global_coords:
		A = to_local(A)
		B = to_local(B)
		
	if(draw_debug):
		DebugDraw3D.draw_line(A,B,Color(1,0,0,1))
		
	var current_thickness : float
	var next_thickness : float
	if(use_precomputed_thickness_arr):	
		current_thickness = pre_computed_thickness_arr[index] / global_scale
		next_thickness = pre_computed_thickness_arr[index + 1] / global_scale
	else:	
		current_thickness = lerp(start_thickness, max_thickness, current_alpha) / global_scale
		next_thickness = lerp(start_thickness, max_thickness, next_alpha) / global_scale
	
	var AB:Vector3 = B - A;
	var dir : Vector3
	var normal
	var cam_transform :Transform3D = camera.get_global_transform()
	
	if(billboard_polys):
		var forward : Vector3 = Vector3.FORWARD
		dir = Vector3.RIGHT #right
		
		#project B onto the plane made by the  forward and A
		var proj_B : Vector3 = B
		proj_B.y = 0
		#calculate angle between A and projected B
		var dot :float = (A - forward).dot(A-proj_B)
		
		#rotate dir around forward
		dir.rotated(forward, acos(dot))
	else:
		dir = (cameraOrigin - ((A + B) / 2)).cross(AB).normalized()
	
	var orthogonalABStart:Vector3 = dir * current_thickness
	var orthogonalABEnd:Vector3 = dir * next_thickness
	
	var AtoABStart:Vector3
	var AfromABStart:Vector3
	
	if(index != 0 && connect_polys):
		AtoABStart = PrevBToAB
		AfromABStart = PrevBFromAB
	else:
		AtoABStart   = A + orthogonalABStart
		AfromABStart = A - orthogonalABStart
	
	var BtoABEnd:Vector3  = B + orthogonalABEnd
	var BfromABEnd:Vector3 = B - orthogonalABEnd
	
	normal = - cam_transform.basis.z	#reverse forward
	_add_vertex(AtoABStart,Vector2(0,current_alpha), normal)
	_add_vertex(BtoABEnd,Vector2( 0, current_alpha),normal)
	_add_vertex(AfromABStart,Vector2(1, next_alpha),normal)
	
	_add_vertex(BtoABEnd,Vector2(0 , current_alpha),normal)
	_add_vertex(BfromABEnd,Vector2(1, next_alpha),normal)
	_add_vertex(AfromABStart,Vector2(1,next_alpha),normal)
	
	PrevBToAB = BtoABEnd
	PrevBFromAB = BfromABEnd

func _add_vertex(pos : Vector3,   uv : Vector2, normal : Vector3) -> void:
	mesh.surface_set_normal(normal)
	mesh.surface_set_uv(uv)
	mesh.surface_add_vertex(pos)
