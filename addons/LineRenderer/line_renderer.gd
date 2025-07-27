class_name LineRenderer extends MeshInstance3D

@export var points: Array[Vector3] = [Vector3(0,0,0),Vector3(0,5,0)]:
	set(new_points): points = new_points
@export var start_thickness:float = 0.1:
	set(new_start_thickness): start_thickness = new_start_thickness
@export var end_thickness:float = 0.1:
	set(new_end_thickness): end_thickness = new_end_thickness
@export var corner_resolution:int = 5:
	set(new_corner_resolution): corner_resolution = new_corner_resolution
@export var cap_resolution:int = 5:
	set(new_cap_resolution): cap_resolution = new_cap_resolution
@export var draw_caps:bool = true:
	set(new_draw_caps): draw_caps = new_draw_caps
@export var draw_crners:bool = true:
	set(new_draw_crners): draw_crners = new_draw_crners
@export var use_global_coords:bool = true:
	set(new_use_global_coords): use_global_coords = new_use_global_coords
@export var tile_texture:bool = true:
	set(new_tile_texture): tile_texture = new_tile_texture
@export var tile_y : bool = true

var camera : Camera3D
var cameraOrigin : Vector3

func _enter_tree() -> void:
	mesh = ImmediateMesh.new()
	
func _ready() -> void:
	camera = get_tree().get_root().get_camera_3d()


func _process(_delta : float) -> void:
	if points.size() < 2:
		return
		
	if camera == null:
		return
	cameraOrigin = to_local(camera.get_global_transform().origin) 
	
	var progressStep:float = 1.0 / points.size();
	var progress:float = 0;
	var thickness:float = lerp(start_thickness, end_thickness, progress);
	var nextThickness:float = lerp(start_thickness, end_thickness, progress + progressStep);
	
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for i in range(points.size() - 1):
		var A:Vector3 = points[i]
		var B:Vector3 = points[i+1]
	
		if use_global_coords:
			A = to_local(A)
			B = to_local(B)
	
		var AB:Vector3 = B - A;
		var orthogonalABStart:Vector3 = (cameraOrigin - ((A + B) / 2)).cross(AB).normalized() * thickness;
		var orthogonalABEnd:Vector3 = (cameraOrigin - ((A + B) / 2)).cross(AB).normalized() * nextThickness;
		
		var AtoABStart:Vector3 = A + orthogonalABStart
		var AfromABStart:Vector3 = A - orthogonalABStart
		var BtoABEnd:Vector3 = B + orthogonalABEnd
		var BfromABEnd:Vector3 = B - orthogonalABEnd
		
		if i == 0:
			if draw_caps:
				cap(A, B, thickness, cap_resolution)
		
		if tile_texture:
			var ABLen : float = AB.length()
			var ABFloor : float = floor(ABLen)
			var ABFrac : float = ABLen - ABFloor
			if(tile_y):
				_add_vertex(AtoABStart,Vector2(0, ABFloor))
				_add_vertex(BtoABEnd,Vector2(0, -ABFrac))
				_add_vertex(AfromABStart,Vector2(1, ABFloor))
				_add_vertex(BtoABEnd,Vector2(0, -ABFrac))
				_add_vertex(BfromABEnd,Vector2(1, -ABFrac))
				_add_vertex(AfromABStart,Vector2(1, ABFloor))
			else:
				_add_vertex(AtoABStart,Vector2(ABFloor, 0))
				_add_vertex(BtoABEnd,Vector2(-ABFrac, 0))
				_add_vertex(AfromABStart,Vector2(ABFloor, 1))
				_add_vertex(BtoABEnd,Vector2(-ABFrac , 0))
				_add_vertex(BfromABEnd,Vector2(-ABFrac, 1))
				_add_vertex(AfromABStart,Vector2(ABFloor,1))
		else:
			_add_vertex(AtoABStart,Vector2(1, 0))
			_add_vertex(BtoABEnd,Vector2(0, 0))
			_add_vertex(AfromABStart,Vector2(1, 1))
			_add_vertex(BtoABEnd,Vector2(0 , 0))
			_add_vertex(BfromABEnd,Vector2(0, 1))
			_add_vertex(AfromABStart,Vector2(1,1))

		
		if i == points.size() - 2:
			if draw_caps:
				cap(B, A, nextThickness, cap_resolution)
		else:
			if draw_crners:
				var C : Vector3 = points[i+2]
				if use_global_coords:
					C = to_local(C)
				
				var BC : Vector3= C - B;
				var orthogonalBCStart : Vector3 = (cameraOrigin - ((B + C) / 2)).cross(BC).normalized() * nextThickness;
				
				var angleDot : float = AB.dot(orthogonalBCStart)
				
				if angleDot > 0 and not angleDot == 1:
					corner(B, BtoABEnd, B + orthogonalBCStart, corner_resolution)
				elif angleDot < 0 and not angleDot == -1:
					corner(B, B - orthogonalBCStart, BfromABEnd, corner_resolution)
		
		progress += progressStep;
		thickness = lerp(start_thickness, end_thickness, progress);
		nextThickness = lerp(start_thickness, end_thickness, progress + progressStep);
	
	mesh.surface_end()

func _add_vertex(pos : Vector3,   uv : Vector2) -> void:
	mesh.surface_set_uv(uv)
	mesh.surface_add_vertex(pos)

func cap(center:Vector3, pivot:Vector3, thickness:float, cap_resolution:int):
	var orthogonal:Vector3 = (cameraOrigin - center).cross(center - pivot).normalized() * thickness;
	var axis:Vector3 = (center - cameraOrigin).normalized();
	
	var vertex_array:Array = []
	for i in range(cap_resolution + 1):
		vertex_array.append(Vector3(0,0,0))
	vertex_array[0] = center + orthogonal;
	vertex_array[cap_resolution] = center - orthogonal;
	
	for i in range(1, cap_resolution):
		vertex_array[i] = center + (orthogonal.rotated(axis, lerp(0.0, PI, float(i) / cap_resolution)));
	
	for i in range(1, cap_resolution + 1):
		mesh.surface_set_uv(Vector2(0, (i - 1) / cap_resolution))
		mesh.surface_add_vertex(vertex_array[i - 1]);
		mesh.surface_set_uv(Vector2(0, (i - 1) / cap_resolution))
		mesh.surface_add_vertex(vertex_array[i]);
		mesh.surface_set_uv(Vector2(0.5, 0.5))
		mesh.surface_add_vertex(center);
		
func corner(center:Vector3, start:Vector3, end:Vector3, resolution:int):
	var vertex_array:Array = []
	for i in range(resolution + 1):
		vertex_array.append(Vector3(0,0,0))
	vertex_array[0] = start;
	vertex_array[resolution] = end;
	
	var axis:Vector3 = start.cross(end).normalized()
	if(axis == Vector3.ZERO):
		axis = start.normalized()
	var offset:Vector3 = start - center
	var angle:float = offset.angle_to(end - center)
	
	for i in range(1, resolution):
		vertex_array[i] = center + offset.rotated(axis, lerp(0.0, angle, float(i) / resolution));
	
	for i in range(1, resolution + 1):
		mesh.surface_set_uv(Vector2(0, (i - 1) / resolution))
		mesh.surface_add_vertex(vertex_array[i - 1]);
		mesh.surface_set_uv(Vector2(0, (i - 1) / resolution))
		mesh.surface_add_vertex(vertex_array[i]);
		mesh.surface_set_uv(Vector2(0.5, 0.5))
		mesh.surface_add_vertex(center);
		
