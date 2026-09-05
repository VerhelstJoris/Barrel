class_name StencilBasedOutlineCompositorEffect extends CompositorEffect

## Color of outlines
@export var outline_color := Color.GOLD

## Thickness of outline in pixels
@export_range(0, 181) var thickness : int= 4 :
	set(value):
		value = clampi(value, 0, 181)
		thickness = value
		_passes = 0
		while value > 0:
			value = value >> 1
			_passes += 1
		print("thickness ", thickness, ", _passes ", _passes)

## Stencil value that denotes pixels to be outlined
@export var stencil_value := 1

## Stencil mask to use when checking the stencil value
@export var stencil_mask := 1

## Enable hot-reload of shaders; only set this if you're actively editing the
## shaders.
var _hot_reload := false

## Number of jump-flood _passes to run to make the outline; automatically set
## by the thickness setter.
var _passes := 1

@export var jump_flood_shader_directory : String = "Materials/Shaders/Misc/"

## GLSL shader definitions for each of our shaders
var jf_shader_file : String
var sc_shader_file : String
var do_shader_file : String

var rd: RenderingDevice

## stencil copy shader render pipeline
var sc_shader: RID
var sc_uniform_set: RID
var sc_framebuffer: RID
var sc_pipeline: RID

## draw outline render pipeline
var do_shader: RID
var do_pipeline: RID

## Vertex array for the stencil copy and draw outline pipelines
var scdo_vertex_format : int
var scdo_vertex_buffer : RID
var scdo_vertex_array : RID

## uniform buffer that contains resolution, shared between stencil copy and
## draw outline pipelines
var scdo_uniform_buffer : RID

## Jump-flood stuffs
var jf_shader: RID
var jf_pipeline: RID
var jf_uniform_sets := [RID(), RID()]

## cached copy of the color texture RID to detect when it changes
var color_texture: RID
## cached copy of the depth/stencil texture RID to detect when it changes
var depth_texture: RID
## cached render resolution; updated in _render_callback()
var resolution := Vector2i(1, 1)

## Textures used by both the stencil copy pipeline, and the jump flood pipeline
## And one random debug texture we can do whatever we want to
## The ping-pong textures used by the jump flood passes
var _textures := [RID(), RID(), RID()]

## Coverage mask written by the stencil copy pass and read by the first jump
## flood pass.  Single channel, single sample.
var mask_texture: RID

## Multisampled counterpart of mask_texture, used as the stencil copy pass's
## colour attachment when the scene is multisampled.  The render pass resolves
## it into mask_texture for us, so nothing reads this directly.  RID() when
## MSAA is off.
var mask_msaa_texture: RID

## Sample count of the scene's render buffers, RenderingDevice.TEXTURE_SAMPLES_1
## when MSAA is off.  Every attachment in a render pass has to agree on this,
## so the stencil copy framebuffer and pipeline are built against it.
var samples := RenderingDevice.TEXTURE_SAMPLES_1

## Exposed Texture2Ds to allow debugging of the various textures used in this
## CompositorEffect.
var debug_textures := [Texture2DRD.new(), Texture2DRD.new(), Texture2DRD.new()]

## mutex for rebuild_pipelines
var mutex := Mutex.new()
## Set when the shader is dirty and needs to be rebuilt
@export var rebuild_pipelines := true :
	set(value):
		mutex.lock()
		rebuild_pipelines = value
		mutex.unlock()

## Tracks the highest modification time for any of the shaders to trigger a
## reload
var _shader_mtime := 0

## Check if any of the shaders have been updated, and if so, kick off a rebuild
## of the pipelines
func check_for_shader_changes() -> void:
	var rebuild: bool = false
	for path in [sc_shader_file, jf_shader_file, do_shader_file]:
		var mtime: int = FileAccess.get_modified_time(path)
		if mtime > _shader_mtime:
			rebuild = true
			_shader_mtime = mtime

	if rebuild:
		rebuild_pipelines = true

# Called when this resource is constructed.
func _init():
	jf_shader_file = jump_flood_shader_directory + "jump_flood.glsl"
	sc_shader_file = jump_flood_shader_directory + "stencil_copy.glsl"
	do_shader_file = jump_flood_shader_directory + "draw_outline.glsl"
	
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT

	# Grab the rendering device
	rd = RenderingServer.get_rendering_device()

	## We create the vertex & index arrays to draw a full-screen quad.

	# build the vertex format
	var vertex_attr = RDVertexAttribute.new()
	vertex_attr.location = 0
	vertex_attr.format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	vertex_attr.stride = 4 * 3
	scdo_vertex_format = rd.vertex_format_create([vertex_attr])

	# These vertex points make a triangle that cover the entire screen.  The
	# points are declared in counter-clockwise winding order so that the front
	# of the quad is facing the camera.  This is important for the stencil
	# operations set in _build_sc_pipeline(), as we only set stencil front_ops.
	var vertex_data: PackedVector3Array = PackedVector3Array([
	Vector3(-1, -1, 0),
	Vector3(3, -1, 0),
	Vector3(-1, 3, 0),
	])
	var vertex_bytes: PackedByteArray   = vertex_data.to_byte_array()
	scdo_vertex_buffer = rd.vertex_buffer_create(vertex_bytes.size(), vertex_bytes)
	scdo_vertex_array = rd.vertex_array_create(3, scdo_vertex_format, [scdo_vertex_buffer])

	# Create the uniform buffer for the screen resolution used for both the
	# stencil copy, and draw outline pipelines.  Each pipeline will have its
	# own uniform set for this buffer.
	var buffer: PackedByteArray = PackedFloat32Array([1, 1, 0, 0]).to_byte_array()
	scdo_uniform_buffer = rd.uniform_buffer_create(buffer.size(), buffer)

	## mark ourselves as dirty so everything else is created when we know the
	## render resolution
	rebuild_pipelines = true

# System notifications, we want to react on the notification that
# alerts us we are about to be destroyed.
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if jf_shader.is_valid():
			# freeing the shader will free the pipeline and the uniform sets
			rd.free_rid(jf_shader)
		if sc_shader.is_valid():
			rd.free_rid(sc_shader)
		if do_shader.is_valid():
			rd.free_rid(do_shader)
		for rid in _textures:
			if rid.is_valid():
				rd.free_rid(rid)
		if mask_texture.is_valid():
			rd.free_rid(mask_texture)
		if mask_msaa_texture.is_valid():
			rd.free_rid(mask_msaa_texture)
		if scdo_vertex_buffer.is_valid():
			rd.free_rid(scdo_vertex_buffer)
		if scdo_uniform_buffer.is_valid():
			rd.free_rid(scdo_uniform_buffer)

## Load GLSL from a specific resource path
## Returns:
##  false: failed to load or compile shader
##  RDShaderSPIRV: compiled shader
func _load_glsl_from_file(path) -> Variant:
	# hot-reload of shaders via RDShaderFile does not work by default.  See
	# https://github.com/godotengine/godot/issues/110468 for details.
	if not _hot_reload:
		var shader_file: RDShaderFile = ResourceLoader.load(path)
		if(shader_file):
			return shader_file.get_spirv()
		else:
			push_error("_load_glsl_from_file() file not found: ", path)
			return null

	# Manually reload & compile the shader using RDShaderSource
	var lines: Array[Variant] = []
	if not FileAccess.file_exists(path):
		push_error("_load_glsl_from_file() file not found: ", path)
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("_load_glsl_from_file() failed to open `", path, "`: ", FileAccess.get_open_error())
		return

	while not file.eof_reached():
		lines.append(file.get_line())

	file.close()

	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_vertex = ""
	source.source_fragment = ""
	source.source_compute = ""

	var type = null
	for line in lines:
		if line == "#[vertex]":
			type = "vertex"
		elif line == "#[fragment]":
			type = "fragment"
		elif line == "#[compute]":
			type = "compute"
		elif type == "vertex":
			source.source_vertex += line + "\n"
		elif type == "fragment":
			source.source_fragment += line + "\n"
		elif type == "compute":
			source.source_compute += line + "\n"

	var spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(source)
	if spirv.compile_error_vertex != "":
		push_error("Failed to compile shader: ", path, "\n",
		spirv.compile_error_vertex)
		return
	if spirv.compile_error_fragment != "":
		push_error("Failed to compile shader: ", path, "\n",
		spirv.compile_error_fragment)
		return
	if spirv.compile_error_compute != "":
		push_error("Failed to compile shader: ", path, "\n",
		spirv.compile_error_compute)
		return
	return spirv

## build the stencil-copy render pipeline
## This pipeline is responsible for initializing the jump-flood state from the
## stencil buffer.
func _build_sc_pipeline() -> void:
	print("building stencil copy pipeline")
	if sc_shader.is_valid():
		rd.free_rid(sc_shader)
		sc_shader = RID()

	# load the shader
	var shader_spirv = _load_glsl_from_file(sc_shader_file)
	if not shader_spirv:
		push_error("failed to load stencil copy shader")
		return
	sc_shader = rd.shader_create_from_spirv(shader_spirv)
	assert(sc_shader.is_valid())

	# create the uniform set
	assert(scdo_uniform_buffer.is_valid())
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = 0
	uniform.add_id(scdo_uniform_buffer)
	sc_uniform_set = rd.uniform_set_create([uniform], sc_shader, 0)

	# Make the framebuffer.
	#
	# Attachment 0 is the mask we render into, at the scene's sample count.
	# Attachment 1 is the scene's depth/stencil buffer.  Under MSAA that has to
	# be the multisampled one, because the resolved copy Godot hands out is
	# R32_SFLOAT with no stencil aspect and no attachment usage bit.
	# Attachment 2, only present under MSAA, is the single sampled mask, which
	# the render pass resolves into for free at the end of the pass.
	assert(mask_texture.is_valid())
	assert(depth_texture.is_valid())

	var attachments: Array[RDAttachmentFormat] = []
	attachments.push_back(_attachment_format_for(_sc_color_target(), samples))
	attachments.push_back(_attachment_format_for(depth_texture, samples))

	var fb_pass := RDFramebufferPass.new()
	fb_pass.color_attachments = PackedInt32Array([0])
	fb_pass.depth_attachment = 1

	var fb_textures: Array[RID] = [_sc_color_target(), depth_texture]

	if _using_msaa():
		attachments.push_back(_attachment_format_for(
				mask_texture, RenderingDevice.TEXTURE_SAMPLES_1))
		fb_pass.resolve_attachments = PackedInt32Array([2])
		fb_textures.push_back(mask_texture)

	# Note: framebuffer_format_create() has no concept of resolve attachments and
	# would sort the resolve target into color_attachments, producing a format
	# that disagrees with the one framebuffer_create() derives.  The multipass
	# variants take the pass description explicitly, so use them for both.
	var format: int = rd.framebuffer_format_create_multipass(attachments, [fb_pass])
	sc_framebuffer = rd.framebuffer_create_multipass(fb_textures, [fb_pass], format)
	if not sc_framebuffer.is_valid():
		# asserts are stripped in release builds, so fail loudly here instead
		push_error("failed to create sc_framebuffer")
		return

	# Create the pipeline
	var blend := RDPipelineColorBlendState.new()
	var blend_attachment := RDPipelineColorBlendStateAttachment.new()
	blend.attachments.push_back(blend_attachment)

	# If the masked stencil value equals our reference value, write that
	# fragment
	var stencil_state = RDPipelineDepthStencilState.new()
	stencil_state.enable_stencil = true
	stencil_state.front_op_compare = RenderingDevice.COMPARE_OP_EQUAL
	stencil_state.front_op_compare_mask = stencil_mask
	stencil_state.front_op_reference = stencil_value
	stencil_state.front_op_fail = RenderingDevice.STENCIL_OP_KEEP
	stencil_state.front_op_pass = RenderingDevice.STENCIL_OP_KEEP

	# The pipeline's sample count has to match the framebuffer's, or pipeline
	# creation fails.
	var multisample_state := RDPipelineMultisampleState.new()
	multisample_state.sample_count = samples

	sc_pipeline = rd.render_pipeline_create(
		sc_shader,
		format,
		scdo_vertex_format,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
		RDPipelineRasterizationState.new(),
		multisample_state,
		stencil_state,
		blend,
	)
	assert(sc_pipeline.is_valid())

## True when the scene's render buffers are multisampled.
func _using_msaa() -> bool:
	return samples != RenderingDevice.TEXTURE_SAMPLES_1

## The colour attachment the stencil copy pass renders into.
func _sc_color_target() -> RID:
	return mask_msaa_texture if mask_msaa_texture.is_valid() else mask_texture

## Describe an existing texture as a framebuffer attachment at a given sample
## count.
func _attachment_format_for(texture: RID,
		attachment_samples: RenderingDevice.TextureSamples) -> RDAttachmentFormat:
	var texture_format: RDTextureFormat = rd.texture_get_format(texture)
	var attachment_format := RDAttachmentFormat.new()
	attachment_format.format = texture_format.format
	attachment_format.usage_flags = texture_format.usage_bits
	attachment_format.samples = attachment_samples
	return attachment_format

## Build the draw-outline render pipeline
## This pipeline will use the stencil buffer to draw the generated outlines
## to the frame being rendered.
func _build_do_pipeline() -> void:
	print("building draw-outline pipeline")
	if do_shader.is_valid():
		rd.free_rid(do_shader)
		do_shader = RID()

	# load the shader
	var shader_spirv = _load_glsl_from_file(do_shader_file)
	if not shader_spirv:
		push_error("failed to load stencil copy shader")
		return
	do_shader = rd.shader_create_from_spirv(shader_spirv)
	assert(do_shader.is_valid())

	do_pipeline = rd.compute_pipeline_create(do_shader)
	assert(do_pipeline.is_valid())

func _build_jf_pipeline() -> void:
	print("building jump flood pipeline")

	if jf_shader.is_valid():
		rd.free_rid(jf_shader)
		jf_shader = RID()

	# load the jump-flood shader
	var shader_spirv = _load_glsl_from_file(jf_shader_file)
	if not shader_spirv:
		push_error("failed to load jump flood shader")
		return
	jf_shader = rd.shader_create_from_spirv(shader_spirv)
	assert(jf_shader.is_valid())

	# build the pipeline
	jf_pipeline = rd.compute_pipeline_create(jf_shader)
	assert(jf_pipeline.is_valid())

	# now build the uniform sets we'll use through the _passes
	assert(_textures[0].is_valid())
	assert(_textures[1].is_valid())
	assert(mask_texture.is_valid())

	var mask_uniform := RDUniform.new()
	mask_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	mask_uniform.binding = 2
	mask_uniform.add_id(mask_texture)

	for group in [[0, _textures[0], _textures[1]],
		[1, _textures[1], _textures[0]]]:
		var pass_number = group[0]
		var src_texture = group[1]
		var dest_texture = group[2]

		# clear the pass uniform sets; they were already freed when the shader
		# was destroyed.
		jf_uniform_sets[pass_number] = [RID(), RID()]

		var src_uniform := RDUniform.new()
		src_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		src_uniform.binding = 0
		src_uniform.add_id(src_texture)

		var dest_uniform = RDUniform.new()
		dest_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		dest_uniform.binding = 1
		dest_uniform.add_id(dest_texture)

		jf_uniform_sets[pass_number] = rd.uniform_set_create(
				[src_uniform, dest_uniform, mask_uniform], jf_shader, 0)

## Create a new color texture to use as the output for our render sc_pipeline.
## Note: this texture must be the same size as the depth texture, so we create
## it on demand.
func _build_textures():
	var count: int = _textures.size()
	print("building ", count, " output textures ", resolution)

	# set up the texture format
	var texture_format = RDTextureFormat.new()
	texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	texture_format.width = resolution.x
	texture_format.height = resolution.y
	# XXX may need to explore proper format to use here.
	texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	# texture_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	texture_format.usage_bits = (
	RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
	RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
	RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
	RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	)

	var texture_view = RDTextureView.new()

	# build the new texture buffers
	for i in range(count):
		var rid: RID = rd.texture_create(texture_format, texture_view)
		assert(rid.is_valid())

		# Save off the old rid to be freed after we swap the value in the debug
		# texture.  If we don't do this, the debug textures will flicker.
		var old_rid: RID = _textures[i]

		# update the rids
		_textures[i] = rid
		debug_textures[i].texture_rd_rid = rid

		if old_rid.is_valid():
			rd.free_rid(old_rid)

	# Build the coverage mask.  This is what the stencil copy pass renders into
	# and what the first jump flood pass seeds from.  One channel is enough: a
	# seed's position is its own pixel position, so the only thing the stencil
	# copy pass has to record is whether the pixel is covered.
	if mask_texture.is_valid():
		rd.free_rid(mask_texture)
		mask_texture = RID()
	if mask_msaa_texture.is_valid():
		rd.free_rid(mask_msaa_texture)
		mask_msaa_texture = RID()

	var mask_format := RDTextureFormat.new()
	mask_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	mask_format.width = resolution.x
	mask_format.height = resolution.y
	mask_format.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	mask_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	)
	# Hint to the driver that this is a resolve target under MSAA.
	mask_format.is_resolve_buffer = _using_msaa()
	mask_texture = rd.texture_create(mask_format, RDTextureView.new())
	assert(mask_texture.is_valid())

	if _using_msaa():
		# The stencil copy pass has to render at the scene's sample count,
		# because the stencil it tests against only exists in the multisampled
		# depth buffer.  Nothing reads this texture: the render pass resolves it
		# into mask_texture, so it can be discarded as soon as the pass ends.
		var mask_msaa_format := RDTextureFormat.new()
		mask_msaa_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
		mask_msaa_format.width = resolution.x
		mask_msaa_format.height = resolution.y
		mask_msaa_format.format = RenderingDevice.DATA_FORMAT_R8_UNORM
		mask_msaa_format.samples = samples
		mask_msaa_format.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
		mask_msaa_texture = rd.texture_create(mask_msaa_format, RDTextureView.new())
		assert(mask_msaa_texture.is_valid())
		rd.texture_set_discardable(mask_msaa_texture, true)

## Update uniform buffer shared between the stencil-copy and draw-outline
## pipelines
func _update_common_buffers():
	print("updating common uniform buffer");
	assert(scdo_uniform_buffer.is_valid())

	# update the render resolution
	var buffer: PackedByteArray = PackedFloat32Array([resolution.x, resolution.y, 0, 0]).to_byte_array()
	rd.buffer_update(scdo_uniform_buffer, 0, buffer.size(), buffer)

# Called by the rendering thread every frame.
func _render_callback(_p_effect_callback_type, p_render_data) -> void:
	var rebuild := false

	if not rd:
		return

	# Get our render scene buffers object, this gives us access to our render
	# buffers. Note that implementation differs per renderer hence the need
	# for the cast.
	var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
	if not render_scene_buffers:
		return

	# Get our render size, this is the 3D render resolution!
	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 and size.y == 0:
		return

	# check if shaders are dirty; if so rebuild
	if rebuild_pipelines:
		mutex.lock()
		rebuild_pipelines = false
		mutex.unlock()
		rebuild = true

	# Build the output texture the same size as the render resolution.
	# Note: the output texture must be the same size as the render resolution
	#       because the texture and depth texture must be the same resolution
	#       to create a sc_framebuffer later.  If they are not the same size, we
	#       get an error in _build_framebuffer()
	if resolution != size:
		resolution = size
		rebuild = true

	# MSAA changes the sample count every attachment in the stencil copy pass
	# has to be built at, so pick it up before anything gets rebuilt.
	var new_samples: RenderingDevice.TextureSamples = render_scene_buffers.get_texture_samples()
	if new_samples != samples:
		samples = new_samples
		rebuild = true

	# if the color texture has changed, we'll need to rebuild the pipelines
	var color_tex: RID = render_scene_buffers.get_color_layer(0)
	if color_tex != color_texture:
		color_texture = color_tex
		rebuild = true

	# If the depth texture has changed, we'll need to rebuild the pipelines.
	# The msaa argument matters: with MSAA on, the non-multisampled depth layer
	# is a resolve target created as R32_SFLOAT with no depth/stencil attachment
	# bit and no stencil aspect, so it can't be attached to a framebuffer and
	# wouldn't carry our stencil values anyway.
	var depth_tex: RID = render_scene_buffers.get_depth_layer(0, _using_msaa())
	if depth_tex != depth_texture:
		depth_texture = depth_tex
		rebuild = true


	if rebuild:
		_build_textures()
		_update_common_buffers()
		_build_sc_pipeline()
		_build_jf_pipeline()
		_build_do_pipeline()

	if not sc_framebuffer.is_valid() or not sc_pipeline.is_valid():
		return

	# Perform the draw using the rendering sc_pipeline, and the stencil buffer
	# from the real render pipeline.
	var draw_list := rd.draw_list_begin(
						 sc_framebuffer,
						 RenderingDevice.DRAW_CLEAR_COLOR_0,
							 [Color(0, 0, 0, 0)],
						 1.0,
						 0,
						 Rect2(),
						 RenderingDevice.OPAQUE_PASS)
	rd.draw_list_bind_render_pipeline(draw_list, sc_pipeline)
	rd.draw_list_bind_vertex_array(draw_list, scdo_vertex_array)
	rd.draw_list_bind_uniform_set(draw_list, sc_uniform_set, 0)
	rd.draw_list_draw(draw_list, false, 3) # this is the 
	rd.draw_list_end()

	# Create our group counts for the next two compute shaders: jump-flood, and
	# draw-outlines
	@warning_ignore("integer_division")
	var x_groups : int = (resolution.x - 1) / 8 + 1
	@warning_ignore("integer_division")
	var y_groups : int = (resolution.y - 1) / 8 + 1
	var push_constant := PackedByteArray()
	push_constant.resize(16) # Must be a multiple of 16 bytes

	# Run the jump-flood pipeline the required number of passes, swapping the
	# textures between each pass.
	#
	# At least one pass always runs.  The seed buffer is now produced by the
	# first jump flood pass rather than written directly by the stencil copy
	# pass, so skipping every pass (thickness 0) would leave the draw outline
	# pass reading a stale buffer.
	var jf_passes: int = maxi(_passes, 1)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, jf_pipeline)

	for i in range(jf_passes):
		var stride: int = (1<<(jf_passes-i-1))
		push_constant.encode_u32(0, stride)
		# The first pass has no seed buffer to read yet, so it seeds from the
		# coverage mask instead.
		push_constant.encode_u32(4, 1 if i == 0 else 0)
		rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())

		# pick the uniform set based on the pass number so we ping-pong between
		# the two textures.
		rd.compute_list_bind_uniform_set(
			compute_list,
			jf_uniform_sets[i & 0x1],
			0)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)

	rd.compute_list_end()


	# next we run the draw outline pipeline

	# Because the color layer can vanish during resize, we just create the
	# uniform set here.
	# XXX need to open an issue about resizing debounce because the depth and
	# color textures can be freed underneath you during resize.
	var src_uniform := RDUniform.new()
	src_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	src_uniform.binding = 0
	src_uniform.add_id(_textures[jf_passes & 0x1])
	var dest_uniform = RDUniform.new()
	dest_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	dest_uniform.binding = 1
	dest_uniform.add_id(color_texture)
	var uniform_set: RID = UniformSetCacheRD.get_cache(do_shader, 0, [src_uniform, dest_uniform])
	assert(uniform_set.is_valid())

	# construct the push constant for drawing our outlines.  It contains the
	# outline color, and the outline thickness squared
	var do_push_constant: PackedByteArray = PackedByteArray()
	do_push_constant.resize(32)
	do_push_constant.encode_float(0, outline_color.r)
	do_push_constant.encode_float(4, outline_color.g)
	do_push_constant.encode_float(8, outline_color.b)
	do_push_constant.encode_float(12, outline_color.a)
	do_push_constant.encode_u32(16, thickness*2)

	compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, do_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, do_push_constant, do_push_constant.size())
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()
