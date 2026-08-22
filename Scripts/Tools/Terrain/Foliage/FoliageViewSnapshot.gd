class_name FoliageViewSnapshot extends RefCounted

# Everything the fill and the GPU upload need from the camera, sampled once on
# the main thread. Nothing in here touches the scene tree after construction,
# so it is safe to hand across to the render thread.

var cam_transform : Transform3D
var cam_origin : Vector3
var cam_forward : Vector3

# ground-projected ray normals taken along the bottom edge of the viewport
var left_dir : Vector3
var right_dir : Vector3
var center_dir : Vector3

# terrain height under the camera -- the plane the frustum is restricted to.
# A local sample beats a world-wide constant on sloped ground.
var ground_y : float = 0.0

# The camera's six frustum planes in world space, plus a point known to be
# strictly inside them. The fill clips against these rather than trying to
# rebuild the visible ground region from ray hits -- see FoliageFillGrid.
var frustum : Array[Plane] = []
var inside_point : Vector3


static func capture(cam : Camera3D, terrain : Terrain3D) -> FoliageViewSnapshot:
	var snap := FoliageViewSnapshot.new()

	snap.cam_transform = cam.global_transform
	snap.cam_origin = snap.cam_transform.origin
	snap.cam_forward = -snap.cam_transform.basis.z

	var vp_size : Vector2 = cam.get_viewport().get_visible_rect().size
	snap.left_dir = cam.project_ray_normal(Vector2(0.0, vp_size.y))
	snap.right_dir = cam.project_ray_normal(Vector2(vp_size.x, vp_size.y))
	snap.center_dir = cam.project_ray_normal(Vector2(vp_size.x * 0.5, vp_size.y))

	if cam.is_inside_tree():
		snap.frustum = cam.get_frustum()
	# a point on the view axis halfway between the near and far planes, used to
	# resolve which way each plane's normal faces without relying on their order
	snap.inside_point = snap.cam_origin + snap.cam_forward * ((cam.near + cam.far) * 0.5)

	snap.ground_y = snap.cam_origin.y
	if terrain:
		var h : float = terrain.data.get_height(Vector3(snap.cam_origin.x, 0.0, snap.cam_origin.z))
		if not is_nan(h):
			snap.ground_y = h

	return snap
