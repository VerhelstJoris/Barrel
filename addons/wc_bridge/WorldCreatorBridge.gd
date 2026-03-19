@tool
extends Control

# References to the UI nodes
@onready var path_line_edit: LineEdit = $VBoxContainer/ControlsContainer/HBoxContainer_XML/XMLLineEdit
@onready var browse_button: Button = $VBoxContainer/ControlsContainer/HBoxContainer_XML/BrowseButton
@onready var name_line_edit: LineEdit = $VBoxContainer/ControlsContainer/HBoxContainer_Name/NameLineEdit
@onready var sync_terrain_button: Button = $VBoxContainer/ControlsContainer/SyncTerrainButton
@onready var vertex_spacing_spinbox: SpinBox = $VBoxContainer/ControlsContainer/HBoxContainer_VertexSpacing/SpinBox
@onready var height_scale_spinbox: SpinBox = $VBoxContainer/ControlsContainer/HBoxContainer_HeightScale/SpinBox
@onready var world_scale_spinbox: SpinBox = $VBoxContainer/ControlsContainer/HBoxContainer_WorldScale/SpinBox
@onready var error_label: Label = $VBoxContainer/ErrorLabel
@onready var controls_container: Control = $VBoxContainer/ControlsContainer

var file_dialog: FileDialog
var terrain3d_available: bool = false

func _enter_tree():
	# Connect signals when added to tree
	if not browse_button:
		return
	if not browse_button.pressed.is_connected(show_file_dialog):
		browse_button.pressed.connect(show_file_dialog)
	if not sync_terrain_button.pressed.is_connected(_on_sync_terrain_button_pressed):
		sync_terrain_button.pressed.connect(_on_sync_terrain_button_pressed)

func _ready(): 
	# Check if Terrain3D plugin is enabled by checking the project settings
	var enabled_plugins = ProjectSettings.get_setting("editor_plugins/enabled", [])
	terrain3d_available = "res://addons/terrain_3d/plugin.cfg" in enabled_plugins
	
	if not terrain3d_available:
		_show_error_message()
		return
	
	# Hide error label if Terrain3D is available
	if error_label:
		error_label.visible = false
	
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Select World Creator Sync XML"
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.xml ; XML Metadata"]
	file_dialog.file_selected.connect(_on_xml_selected)
	
	# Connect buttons (also done in _enter_tree for safety)
	if not browse_button.pressed.is_connected(show_file_dialog):
		browse_button.pressed.connect(show_file_dialog)
	if not sync_terrain_button.pressed.is_connected(_on_sync_terrain_button_pressed):
		sync_terrain_button.pressed.connect(_on_sync_terrain_button_pressed)
	
	# Default Values
	var defaultXmlPath = OS.get_system_dir(OS.SystemDir.SYSTEM_DIR_DOCUMENTS).path_join("World Creator/Sync/bridge.xml")
	path_line_edit.text = defaultXmlPath
	name_line_edit.text = "WC_Terrain"
	
	world_scale_spinbox.value = 1
	height_scale_spinbox.value = 1
	vertex_spacing_spinbox.value = 1

func _show_error_message():
	# Hide all controls
	if controls_container:
		controls_container.visible = false
	
	# Show error message
	if error_label:
		error_label.visible = true
		error_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	
# ----------------------------------------------------------------------
# --- EXISTING UI AND IMPORT FUNCTIONS ---

func show_file_dialog():
	get_tree().get_root().add_child(file_dialog)
	file_dialog.popup_centered()
	
func _on_xml_selected(path: String):
	path_line_edit.text = path
	
func _on_sync_terrain_button_pressed():
	if not terrain3d_available:
		push_error("Terrain3D is not available. Please install Terrain3D plugin.")
		return
	
	var xml_path: String = path_line_edit.text
	var terrain_name: String = name_line_edit.text
	var vertex_spacing: float = vertex_spacing_spinbox.value
	var height_scale: float = height_scale_spinbox.value
	var world_scale: float = world_scale_spinbox.value
	
	print("=== STARTING TERRAIN IMPORT ===")
	print("XML: %s | Terrain: %s" % [xml_path, terrain_name])
	print("Vertex Spacing: %.2f | World Scale: %.2f | Height Scale: %.2f" % [vertex_spacing, world_scale, height_scale])
		
	# 1. Check if the XML file exists
	if not FileAccess.file_exists(xml_path):
		push_error("XML file not found: " + xml_path)
		return
			
	# 2. Parse the XML and get metadata
	var metadata = _parse_wc_xml(xml_path)
		
	if metadata.is_empty():
		push_error("Failed to parse required metadata from XML.")
		return
	
	# 3. Create resource directory for this terrain
	var resource_dir = "res://wc_data/%s" % terrain_name
	_create_resource_directory(resource_dir)
	
	# 4. Read and import the heightmap tiles
	_import_heightmap_tiles(xml_path, metadata, terrain_name, resource_dir, vertex_spacing, world_scale, height_scale) 
		
	print("=== IMPORT COMPLETE ===\n")

# Helper function to read and parse the XML file
func _parse_wc_xml(path: String) -> Dictionary:
	var metadata = {}
	var parser = XMLParser.new()
	
	var error = parser.open(path)
	if error != OK:
		push_error("XMLParser Error: Could not open file: " + path)
		return metadata
	
	var textures = []
	
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			
			if parser.get_node_name() == "Surface":
				metadata.min_height = parser.get_named_attribute_value("MinHeight").to_float()
				metadata.max_height = parser.get_named_attribute_value("MaxHeight").to_float()
				
				# Terrain dimensions in METERS
				metadata.length = parser.get_named_attribute_value("Length").to_float()
				metadata.width = parser.get_named_attribute_value("Width").to_float()
				
				# Total resolution in PIXELS across entire terrain
				metadata.resolution_x = parser.get_named_attribute_value("ResolutionX").to_int()
				metadata.resolution_y = parser.get_named_attribute_value("ResolutionY").to_int()
				
				# Tile resolution: the maximum resolution per tile (usually matches ResolutionX/Y for single tiles)
				# For multi-tile exports, World Creator uses up to 4096px per tile
				# For single tiles, it uses the actual resolution
				metadata.tile_resolution = max(metadata.resolution_x, metadata.resolution_y)
				
				# Calculate actual precision (pixels per meter)
				metadata.precision_x = float(metadata.resolution_x) / metadata.width
				metadata.precision_y = float(metadata.resolution_y) / metadata.length
				
				print("Terrain size: %.0fm x %.0fm (%.2f px/m)" % [metadata.width, metadata.length, metadata.precision_x])
			
			elif parser.get_node_name() == "TextureInfo":
				# Check if this texture has an albedo file (some materials might not)
				var albedo_file = ""
				if parser.has_attribute("AlbedoFile"):
					albedo_file = parser.get_named_attribute_value("AlbedoFile")
				
				var tile_size = "1024,1024"  # Default tile size
				if parser.has_attribute("TileSize"):
					tile_size = parser.get_named_attribute_value("TileSize")
				
				var texture_info = {
					"name": parser.get_named_attribute_value("Name"),
					"albedo_file": albedo_file,
					"tile_size": tile_size,
					"metallic": parser.get_named_attribute_value("Metallic").to_float(),
					"smoothness": parser.get_named_attribute_value("Smoothness").to_float(),
					"color": parser.get_named_attribute_value("Color")
				}
				textures.append(texture_info)
	
	metadata.textures = textures
	return metadata

# Helper function to create resource directory
func _create_resource_directory(dir_path: String) -> void:
	var global_path = ProjectSettings.globalize_path(dir_path)
	
	if not DirAccess.dir_exists_absolute(global_path):
		var err = DirAccess.make_dir_recursive_absolute(global_path)
		if err != OK:
			push_error("Failed to create directory: %s (Error: %d)" % [dir_path, err])

# Fixed _import_heightmap_tiles - Calculate tile dimensions dynamically with proper world_scale
func _import_heightmap_tiles(xml_path: String, data: Dictionary, terrain_name: String, resource_dir: String, vertex_spacing: float, world_scale: float, height_scale: float) -> void:
	var heightmap_path = xml_path.get_base_dir()
	
	# World Creator tiles terrains into chunks, each up to tile_resolution pixels
	var max_tile_px = data.tile_resolution  # Usually 4096
	
	# Calculate how many meters each tile represents
	# Since precision = pixels/meter, tile_meters = tile_pixels / precision
	var tile_meters_x = float(max_tile_px) / data.precision_x
	var tile_meters_y = float(max_tile_px) / data.precision_y
	
	# Calculate how many tiles World Creator created
	var tiles_x = int(ceil(data.width / tile_meters_x))
	var tiles_y = int(ceil(data.length / tile_meters_y))
	
	print("Importing %d tile(s): %d x %d" % [tiles_x * tiles_y, tiles_x, tiles_y])
	
	# Create the Terrain3D node
	if not Engine.has_singleton("EditorInterface"):
		push_error("Could not access EditorInterface. Is the script running as an @tool?")
		return
	
	var editor_interface = Engine.get_singleton("EditorInterface")
	var scene_root = editor_interface.get_edited_scene_root()
	
	if not scene_root:
		push_error("Cannot create node: No scene is currently open.")
		return
	
	# Check if terrain already exists and replace it
	var existing_terrain = scene_root.find_child(terrain_name, false, false)
	if existing_terrain and existing_terrain is Terrain3D:
		scene_root.remove_child(existing_terrain)
		existing_terrain.queue_free()
	
	# Create and add Terrain3D node
	var terrain_node = Terrain3D.new()
	terrain_node.name = terrain_name
	scene_root.add_child(terrain_node)
	terrain_node.owner = scene_root
	terrain_node.vertex_spacing = vertex_spacing
	
	# Set storage directory for Terrain3D data
	terrain_node.data_directory = resource_dir
	
	# Configure material settings - set world background to none (value 0)
	var material = terrain_node.material
	if material:
		material.set_world_background(0)  # 0 = None/Disabled
	
	# Apply textures before importing heightmaps
	_apply_textures(terrain_node, data, heightmap_path, resource_dir)
	
	# Process each tile
	for ty in range(tiles_y):
		for tx in range(tiles_x):
			var file_name = "heightmap_%d_%d.raw" % [tx, ty]
			var full_path = heightmap_path.path_join(file_name)
			
			if not FileAccess.file_exists(full_path):
				push_error("Heightmap tile not found: " + full_path)
				continue
			
			# Read the raw heightmap file
			var file = FileAccess.open(full_path, FileAccess.READ)
			
			# Each tile might be different size if it's at the edge
			# Calculate actual pixel dimensions for this specific tile
			var tile_start_x_meters = tx * tile_meters_x
			var tile_start_y_meters = ty * tile_meters_y
			var tile_end_x_meters = min((tx + 1) * tile_meters_x, data.width)
			var tile_end_y_meters = min((ty + 1) * tile_meters_y, data.length)
			
			var actual_tile_meters_x = tile_end_x_meters - tile_start_x_meters
			var actual_tile_meters_y = tile_end_y_meters - tile_start_y_meters
			
			var actual_tile_px_x = int(actual_tile_meters_x * data.precision_x)
			var actual_tile_px_y = int(actual_tile_meters_y * data.precision_y)
			
			# Read raw data
			var raw_data_size = actual_tile_px_x * actual_tile_px_y
			var raw_data = file.get_buffer(raw_data_size * 2)  # 16-bit = 2 bytes per pixel
			file.close()
			
			# Convert raw 16-bit data to heights in meters
			var tile_heightmap = PackedFloat32Array()
			tile_heightmap.resize(raw_data_size)
			var height_range = data.max_height - data.min_height
			var height_scale_factor = (height_range * height_scale) / 65535.0
			
			for i in range(raw_data_size):
				var raw_value = raw_data.decode_u16(i * 2)
				tile_heightmap[i] = data.min_height + raw_value * height_scale_factor
			
			# Downsample to Terrain3D's resolution
			# Calculate target resolution based on vertex_spacing and world_scale
			# vertex_spacing determines the distance between vertices in meters
			# Fewer vertices are needed when vertex_spacing is larger
			var target_size_x = int((actual_tile_meters_x * world_scale) / vertex_spacing)
			var target_size_y = int((actual_tile_meters_y * world_scale) / vertex_spacing)
			
			# Create downsampled image
			var img = Image.create(target_size_x, target_size_y, false, Image.FORMAT_RF)
			
			for y in range(target_size_y):
				for x in range(target_size_x):
					# Sample from source at correct position based on precision
					# We need to map scaled coordinates back to original coordinates
					# vertex_spacing affects the sampling: larger spacing = fewer samples over same area
					var unscaled_x = (x * vertex_spacing) / world_scale
					var unscaled_y = (y * vertex_spacing) / world_scale
					var src_x = int(unscaled_x * data.precision_x)
					var src_y = int(unscaled_y * data.precision_y)
					var src_index = src_y * actual_tile_px_x + src_x
					
					if src_index < tile_heightmap.size():
						img.set_pixel(x, y, Color(tile_heightmap[src_index], 0, 0, 1))
			
			# Calculate world position for this tile with world_scale applied
			# In Godot: X = right, Y = up, Z = forward (negative Z = back)
			# For tile (0,0), start at origin. Each tile extends in its dimensions.
			var pos := Vector3(
				tx * tile_meters_x * world_scale,
				0,
				(-ty * tile_meters_y - tile_meters_y) * world_scale
			)
			
			# Load control map for this tile
			var control_img = _load_splatmaps_for_tile(
				heightmap_path, tx, ty, 
				data.textures.size(), 
				data.precision_x, data.precision_y,
				actual_tile_px_x, actual_tile_px_y,
				target_size_x, target_size_y,
				world_scale, vertex_spacing
			)
			
			# Load color map for this tile
			var color_img = _load_colormap_for_tile(
				heightmap_path, tx, ty,
				data.precision_x, data.precision_y,
				actual_tile_px_x, actual_tile_px_y,
				target_size_x, target_size_y,
				world_scale, vertex_spacing
			)
			
			# Import into Terrain3D
			var imported_images: Array[Image]
			imported_images.resize(Terrain3DRegion.TYPE_MAX)
			imported_images[Terrain3DRegion.TYPE_HEIGHT] = img
			if control_img:
				imported_images[Terrain3DRegion.TYPE_CONTROL] = control_img
			if color_img:
				imported_images[Terrain3DRegion.TYPE_COLOR] = color_img
			
			terrain_node.data.import_images(imported_images, pos, data.min_height, height_scale)
	
	# Select the newly created terrain
	editor_interface.get_selection().add_node(terrain_node)
	
	print("Successfully created: %s (%d tiles, %.0f-%.0fm height)" % [terrain_name, tiles_x * tiles_y, data.min_height, data.max_height])

# Load and process splatmaps for a tile
func _load_splatmaps_for_tile(base_path: String, tx: int, ty: int, texture_count: int, precision_x: float, precision_y: float,
	tile_px_x: int, tile_px_y: int, target_size_x: int, target_size_y: int, world_scale: float, vertex_spacing: float) -> Image:
	
	var splatmap_count = int(ceil(texture_count / 4.0))
	var control_img = Image.create(target_size_x, target_size_y, false, Image.FORMAT_RF)
	
	# Pre-allocate texture strengths dictionary for better performance
	var total_pixels = target_size_x * target_size_y
	var texture_strengths = []
	texture_strengths.resize(total_pixels)
	
	for i in range(total_pixels):
		texture_strengths[i] = {}
	
	# Reuse Terrain3DUtil instance for encoding
	var util := Terrain3DUtil.new()
	
	for splatmap_idx in range(splatmap_count):
		var splatmap_file = "splatmap_%d_%d_%d.tga" % [splatmap_idx, tx, ty]
		var splatmap_path = base_path.path_join(splatmap_file)
		
		if not FileAccess.file_exists(splatmap_path):
			continue
		
		var splatmap = Image.load_from_file(splatmap_path)
		if not splatmap:
			continue
		
		var base_texture_idx = splatmap_idx * 4
		var textures_in_this_splatmap = min(4, texture_count - base_texture_idx)
		
		# Sample and downsample the splatmap
		for y in range(target_size_y):
			for x in range(target_size_x):
				var pixel_idx = y * target_size_x + x
				
				# Map scaled coordinates back to original coordinates
				# Account for vertex_spacing in the coordinate transformation
				var unscaled_x = (x * vertex_spacing) / world_scale
				var unscaled_y = (y * vertex_spacing) / world_scale
				
				# Sample from source position based on precision
				var src_x = int(unscaled_x * precision_x)
				var src_y = int(unscaled_y * precision_y)
				
				# Clamp to splatmap bounds
				src_x = clamp(src_x, 0, splatmap.get_width() - 1)
				src_y = clamp(src_y, 0, splatmap.get_height() - 1)
				
				var pixel = splatmap.get_pixel(src_x, src_y)
				
				# Store texture strengths
				if textures_in_this_splatmap >= 1 and pixel.r > 0.0:
					texture_strengths[pixel_idx][base_texture_idx + 0] = pixel.r
				if textures_in_this_splatmap >= 2 and pixel.g > 0.0:
					texture_strengths[pixel_idx][base_texture_idx + 1] = pixel.g
				if textures_in_this_splatmap >= 3 and pixel.b > 0.0:
					texture_strengths[pixel_idx][base_texture_idx + 2] = pixel.b
				if textures_in_this_splatmap >= 4 and pixel.a > 0.0:
					texture_strengths[pixel_idx][base_texture_idx + 3] = pixel.a
	
	# Encode control map with blending
	for y in range(target_size_y):
		for x in range(target_size_x):
			var pixel_idx = y * target_size_x + x
			var strengths = texture_strengths[pixel_idx]
			
			# Find two strongest textures
			var base_id = 0
			var overlay_id = 0
			var base_strength = 0.0
			var overlay_strength = 0.0
			
			for tex_id in strengths.keys():
				var strength = strengths[tex_id]
				if strength > base_strength:
					overlay_id = base_id
					overlay_strength = base_strength
					base_id = tex_id
					base_strength = strength
				elif strength > overlay_strength:
					overlay_id = tex_id
					overlay_strength = strength
			
			# Calculate blend
			var blend = 0
			if overlay_strength > 0.0 and base_strength > 0.0:
				var total = base_strength + overlay_strength
				blend = int((overlay_strength / total) * 255.0)
			
			# Encode and store
			var packed: int = util.enc_base(base_id) | util.enc_overlay(overlay_id) | util.enc_blend(blend) | util.enc_auto(false) | util.enc_hole(false)
			var float_value: float = util.as_float(packed)
			control_img.set_pixel(x, y, Color(float_value, 0, 0, 0))
	
	return control_img

# Load and process colormap for a tile
func _load_colormap_for_tile(base_path: String, tx: int, ty: int, precision_x: float, precision_y: float,
	tile_px_x: int, tile_px_y: int, target_size_x: int, target_size_y: int, world_scale: float, vertex_spacing: float) -> Image:
	
	var colormap_file = "colormap_%d_%d.png" % [tx, ty]
	var colormap_path = base_path.path_join(colormap_file)
	
	# Check if colormap exists
	if not FileAccess.file_exists(colormap_path):
		return null
	
	var colormap = Image.load_from_file(colormap_path)
	if not colormap:
		return null
	
	# Create downsampled color image to match terrain resolution
	var color_img = Image.create(target_size_x, target_size_y, false, Image.FORMAT_RGBA8)
	
	# Sample and downsample the colormap
	for y in range(target_size_y):
		for x in range(target_size_x):
			# Map scaled coordinates back to original coordinates
			var unscaled_x = (x * vertex_spacing) / world_scale
			var unscaled_y = (y * vertex_spacing) / world_scale
			
			# Sample from source position based on precision
			var src_x = int(unscaled_x * precision_x)
			var src_y = int(unscaled_y * precision_y)
			
			# Clamp to colormap bounds
			src_x = clamp(src_x, 0, colormap.get_width() - 1)
			src_y = clamp(src_y, 0, colormap.get_height() - 1)
			
			var pixel = colormap.get_pixel(src_x, src_y)
			color_img.set_pixel(x, y, pixel)
	
	return color_img
	
	
# Apply textures from World Creator to Terrain3D
func _apply_textures(terrain_node: Terrain3D, data: Dictionary, base_path: String, resource_dir: String) -> void:
	if not data.has("textures") or data.textures.is_empty():
		return
	
	print("Applying %d texture(s)..." % data.textures.size())
	
	# Get or create the assets
	var assets = terrain_node.assets
	if not assets:
		assets = Terrain3DAssets.new()
		terrain_node.assets = assets
	
	# First pass: determine the smallest texture size and load all textures
	var min_size = 99999
	var temp_images = []
	
	for i in range(min(data.textures.size(), 32)):
		var tex_info = data.textures[i]
		
		# Skip textures without an albedo file (color-only materials)
		if tex_info.albedo_file == "" or tex_info.albedo_file == null:
			temp_images.append(null)
			continue
		
		var source_path = base_path.path_join("Assets").path_join(tex_info.albedo_file)
		
		if not FileAccess.file_exists(source_path):
			push_warning("Texture file not found: %s" % source_path)
			temp_images.append(null)
			continue
		
		# Load albedo image
		var albedo_img = Image.load_from_file(source_path)
		if not albedo_img:
			temp_images.append(null)
			continue
		
		min_size = min(min_size, min(albedo_img.get_width(), albedo_img.get_height()))
		
		# Try to load normal map (if exists)
		var normal_img: Image = null
		if tex_info.has("normal_file") and tex_info.normal_file != "" and tex_info.normal_file != null:
			var normal_path = base_path.path_join("Assets").path_join(tex_info.normal_file)
			if FileAccess.file_exists(normal_path):
				normal_img = Image.load_from_file(normal_path)
		
		# Try to load roughness map (if exists)
		var roughness_img: Image = null
		if tex_info.has("roughness_file") and tex_info.roughness_file != "" and tex_info.roughness_file != null:
			var roughness_path = base_path.path_join("Assets").path_join(tex_info.roughness_file)
			if FileAccess.file_exists(roughness_path):
				roughness_img = Image.load_from_file(roughness_path)
		
		# Try to load height map (if exists)
		var height_img: Image = null
		if tex_info.has("height_file") and tex_info.height_file != "" and tex_info.height_file != null:
			var height_path = base_path.path_join("Assets").path_join(tex_info.height_file)
			if FileAccess.file_exists(height_path):
				height_img = Image.load_from_file(height_path)
		
		temp_images.append({
			"info": tex_info,
			"albedo": albedo_img,
			"normal": normal_img,
			"roughness": roughness_img,
			"height": height_img
		})
	
	# Use default size if no textures with files were found
	if min_size == 99999:
		min_size = 2048
	
	print("Processing textures at size: %dx%d" % [min_size, min_size])
	
	# Second pass: pack channels and create textures
	for i in range(data.textures.size()):
		var tex_info = data.textures[i]
		
		# Handle color-only materials (no texture file)
		if tex_info.albedo_file == "" or tex_info.albedo_file == null:
			# Parse color from XML
			var albedo_color = Color.WHITE
			if tex_info.has("color") and tex_info.color != "":
				var color_str = tex_info.color
				if color_str.begins_with("#") and color_str.length() == 9:
					# Convert ARGB to RGBA: #AARRGGBB -> #RRGGBBAA
					var a = color_str.substr(1, 2)
					var r = color_str.substr(3, 2)
					var g = color_str.substr(5, 2)
					var b = color_str.substr(7, 2)
					albedo_color = Color.html(r + g + b)
					albedo_color.a = float(("0x" + a).hex_to_int()) / 255.0
				else:
					albedo_color = Color.html(color_str)
			
			# Convert smoothness to roughness
			var roughness = 1.0 - tex_info.smoothness
			
			# Create packed albedo texture: RGB = white albedo, A = flat height (0.5)
			var albedo_packed = Image.create(min_size, min_size, false, Image.FORMAT_RGBA8)
			albedo_packed.fill(Color(1.0, 1.0, 1.0, 0.5))  # White with mid-height
			albedo_packed.generate_mipmaps()
			var albedo_texture = ImageTexture.create_from_image(albedo_packed)
			
			# Create packed normal texture: RGB = flat normal (0.5, 0.5, 1.0), A = roughness
			var normal_packed = Image.create(min_size, min_size, false, Image.FORMAT_RGBA8)
			normal_packed.fill(Color(0.5, 0.5, 1.0, roughness))  # Flat normal + roughness
			normal_packed.generate_mipmaps()
			var normal_texture = ImageTexture.create_from_image(normal_packed)
			
			# Create a texture asset with color tint
			var texture_asset = Terrain3DTextureAsset.new()
			texture_asset.set_albedo_texture(albedo_texture)
			texture_asset.set_normal_texture(normal_texture)
			texture_asset.set_albedo_color(albedo_color)
			
			assets.set_texture(i, texture_asset)
			continue
		
		# Handle textured materials
		if i >= temp_images.size() or temp_images[i] == null:
			continue
		
		var tex_data = temp_images[i]
		var tex_info_data = tex_data.info
		var albedo_img = tex_data.albedo
		var normal_img = tex_data.normal
		var roughness_img = tex_data.roughness
		var height_img = tex_data.height
		
		# Resize all images to min_size if needed
		if albedo_img.get_width() != min_size or albedo_img.get_height() != min_size:
			albedo_img.resize(min_size, min_size, Image.INTERPOLATE_LANCZOS)
		
		if normal_img and (normal_img.get_width() != min_size or normal_img.get_height() != min_size):
			normal_img.resize(min_size, min_size, Image.INTERPOLATE_LANCZOS)
		
		if roughness_img and (roughness_img.get_width() != min_size or roughness_img.get_height() != min_size):
			roughness_img.resize(min_size, min_size, Image.INTERPOLATE_LANCZOS)
		
		if height_img and (height_img.get_width() != min_size or height_img.get_height() != min_size):
			height_img.resize(min_size, min_size, Image.INTERPOLATE_LANCZOS)
		
		# Convert albedo to RGBA8 for packing
		if albedo_img.get_format() != Image.FORMAT_RGBA8:
			albedo_img.convert(Image.FORMAT_RGBA8)
		
		# Pack albedo texture: RGB = Albedo, A = Height
		var albedo_packed = Image.create(min_size, min_size, false, Image.FORMAT_RGBA8)
		for y in range(min_size):
			for x in range(min_size):
				var albedo_pixel = albedo_img.get_pixel(x, y)
				var height_value = 0.5  # Default mid-height if no height map
				
				if height_img:
					var height_pixel = height_img.get_pixel(x, y)
					height_value = height_pixel.r  # Use red channel for height
				
				albedo_packed.set_pixel(x, y, Color(albedo_pixel.r, albedo_pixel.g, albedo_pixel.b, height_value))
		
		albedo_packed.generate_mipmaps()
		
		# Pack normal texture: RGB = Normal (OpenGL +Y), A = Roughness
		var normal_packed = Image.create(min_size, min_size, false, Image.FORMAT_RGBA8)
		var roughness_value = 1.0 - tex_info_data.smoothness  # Convert smoothness to roughness
		
		for y in range(min_size):
			for x in range(min_size):
				var normal_pixel = Color(0.5, 0.5, 1.0)  # Default flat normal
				
				if normal_img:
					normal_pixel = normal_img.get_pixel(x, y)
				
				var roughness_px = roughness_value  # Use material roughness
				if roughness_img:
					roughness_px = roughness_img.get_pixel(x, y).r  # Override with roughness map if available
				
				normal_packed.set_pixel(x, y, Color(normal_pixel.r, normal_pixel.g, normal_pixel.b, roughness_px))
		
		normal_packed.generate_mipmaps()
		
		# Save packed textures to resource directory
		var albedo_dest_path = resource_dir.path_join(tex_info_data.albedo_file.get_basename() + "_packed.png")
		var normal_dest_path = resource_dir.path_join(tex_info_data.albedo_file.get_basename() + "_normal_packed.png")
		
		var albedo_dest_global = ProjectSettings.globalize_path(albedo_dest_path)
		var normal_dest_global = ProjectSettings.globalize_path(normal_dest_path)
		
		if not FileAccess.file_exists(albedo_dest_global):
			var err = albedo_packed.save_png(albedo_dest_global)
			if err != OK:
				push_error("Failed to save packed albedo texture: %s (Error: %d)" % [tex_info_data.albedo_file, err])
				continue
		
		if not FileAccess.file_exists(normal_dest_global):
			var err = normal_packed.save_png(normal_dest_global)
			if err != OK:
				push_error("Failed to save packed normal texture: %s (Error: %d)" % [tex_info_data.albedo_file, err])
				continue
		
		# Create textures from packed images
		var albedo_texture = ImageTexture.create_from_image(albedo_packed)
		var normal_texture = ImageTexture.create_from_image(normal_packed)
		
		# Parse tile size (format is "1500,1500")
		# In WC: tile_size = how many meters one texture tile covers
		# In Terrain3D shader: id_scale = _texture_uv_scale_array[id] * 0.5
		# Then: id_uv = uv * id_scale
		# To make texture tile every X meters: uv_scale = 2.0 / tile_size_meters
		var tile_size_parts = tex_info_data.tile_size.split(",")
		var uv_scale = 1.0
		if tile_size_parts.size() >= 1:
			var tile_size_meters = tile_size_parts[0].to_float()
			if tile_size_meters > 0:
				uv_scale = 2.0 / tile_size_meters
		
		# Parse color tint from XML (format is "#ffffffff" - ARGB hex)
		var albedo_color = Color.WHITE
		if tex_info_data.has("color") and tex_info_data.color != "":
			var color_str = tex_info_data.color
			if color_str.begins_with("#") and color_str.length() == 9:
				# Convert ARGB to RGBA: #AARRGGBB -> #RRGGBBAA
				var a = color_str.substr(1, 2)
				var r = color_str.substr(3, 2)
				var g = color_str.substr(5, 2)
				var b = color_str.substr(7, 2)
				albedo_color = Color.html(r + g + b)
			else:
				albedo_color = Color.html(color_str)
		
		# Create a Terrain3DTextureAsset with packed textures
		var texture_asset = Terrain3DTextureAsset.new()
		texture_asset.set_albedo_texture(albedo_texture)
		texture_asset.set_normal_texture(normal_texture)
		texture_asset.set_albedo_color(albedo_color)
		texture_asset.set_uv_scale(uv_scale)
		
		# Set the texture asset in the slot
		assets.set_texture(i, texture_asset)
	
	print("Applied %d texture(s) with channel packing" % assets.get_texture_count())
