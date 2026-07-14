extends Control
# 3D overworld map. Player walks a knight piece along a path of 12 level nodes
# laid out across three themed zones (Forest / Desert / Castle). Tap a level
# node to enter its puzzle.

const PlayerDataScript = preload("res://scripts/autoload/PlayerData.gd")

const ZONE_FOREST = 0
const ZONE_DESERT = 1
const ZONE_CASTLE = 2

const ZONE_COLORS := {
	ZONE_FOREST: {"ground": Color("#3A6B2E"), "accent": Color("#7FA650"), "sky": Color("#9CC4E4"), "props": Color("#2D4A1F")},
	ZONE_DESERT: {"ground": Color("#C9A04A"), "accent": Color("#E9B949"), "sky": Color("#F4D78E"), "props": Color("#8C6A28")},
	ZONE_CASTLE: {"ground": Color("#5A5A66"), "accent": Color("#B9473D"), "sky": Color("#7A8398"), "props": Color("#3A3A44")},
}

const NUM_LEVELS := 12
const PATH_RADIUS := 8.0
const NODE_SPACING := 2.2

var _subviewport: SubViewport = null
var _world: Node3D = null
var _camera: Camera3D = null
var _player: Node3D = null
var _zone_roots: Dictionary = {}  # zone_idx -> Node3D containing props
var _level_nodes: Array = []      # [Node3D, ...] one per level

var _player_data: PlayerDataScript = null
var _current_zone: int = ZONE_FOREST
var _target_pos: Vector3 = Vector3.ZERO
var _moving: bool = false
var _move_speed: float = 6.0
var _current_level_near: int = -1
var _interaction_cooldown: float = 0.0
var _hint_label: Label = null
var _current: Control = null

func _ready() -> void:
	_ensure_subviewport()
	# Defer world build so the SubViewport's World3D is fully initialized
	# (we need world_3d.direct_space_state for raycasting taps).
	call_deferred("_post_ready")

func _post_ready() -> void:
	_build_world()
	_build_ui()
	_player_data = PlayerDataScript.new()
	_spawn_player_at_current_level()
	_pulse_player()

func _ensure_subviewport() -> void:
	if _subviewport:
		return
	# Build a SubViewportContainer so the 3D render is actually visible on screen.
	var container := SubViewportContainer.new()
	container.name = "World3DContainer"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true  # auto-scale to container size
	add_child(container)
	move_child(container, 0)

	_subviewport = SubViewport.new()
	_subviewport.name = "SubViewport"
	_subviewport.size = Vector2i(430, 932)
	_subviewport.transparent_bg = false
	_subviewport.own_world_3d = true
	_subviewport.handle_input_locally = false
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_subviewport)

	_world = Node3D.new()
	_world.name = "World"
	_subviewport.add_child(_world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#9CC4E4")
	sky_mat.sky_horizon_color = Color("#D8E8F0")
	sky_mat.ground_bottom_color = Color("#3A6B2E")
	sky_mat.ground_horizon_color = Color("#7A6A4A")
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_color = Color("#FFFFFF")
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_subviewport.add_child(env)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 55.0
	_camera.position = Vector3(0, 14, 12)
	_subviewport.add_child(_camera)
	_camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	_camera.current = true
	_camera.position = Vector3(0, 16, 14)
	_camera.rotation_degrees = Vector3(-45, 0, 0)
	_camera.make_current()

	# Player placeholder; will be replaced below
	_player = Node3D.new()
	_player.name = "Player"
	_world.add_child(_player)

func _build_world() -> void:
	# Build the ground plane
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = ZONE_COLORS[ZONE_FOREST]["ground"]
	ground_mat.roughness = 0.95
	ground.material_override = ground_mat
	_world.add_child(ground)

	# Static body for raycast (invisible, but receives taps)
	var ground_body := StaticBody3D.new()
	ground_body.name = "GroundBody"
	var ground_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(60, 0.2, 60)
	ground_shape.shape = box_shape
	ground_shape.position = Vector3(0, -0.1, 0)
	ground_body.add_child(ground_shape)
	_world.add_child(ground_body)

	# Path ribbon winding through the world
	_build_path_ribbon()

	# Three zone sectors with props
	for zone_idx in ZONE_COLORS.keys():
		var zone_root := Node3D.new()
		zone_root.name = "Zone_%d" % zone_idx
		_world.add_child(zone_root)
		_zone_roots[zone_idx] = zone_root
		_build_zone_props(zone_idx, zone_root)

	# Build level nodes along the path
	for i in NUM_LEVELS:
		var level_node := _build_level_node(i)
		_level_nodes.append(level_node)
		_world.add_child(level_node)

func _build_path_ribbon() -> void:
	# A curving cobblestone path using a sequence of box segments
	var ribbon := Node3D.new()
	ribbon.name = "Path"
	_world.add_child(ribbon)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#8C8275")
	mat.roughness = 0.85
	for i in NUM_LEVELS - 1:
		var a := _level_position(i)
		var b := _level_position(i + 1)
		var mid := (a + b) * 0.5
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.4, 0.05, a.distance_to(b) + 0.4)
		seg.mesh = box
		seg.material_override = mat
		seg.position = mid
		ribbon.add_child(seg)
		seg.look_at(b, Vector3.UP)

func _build_zone_props(zone_idx: int, parent: Node3D) -> void:
	var cfg: Dictionary = ZONE_COLORS[zone_idx]
	var zone_center := _zone_center(zone_idx)

	# Zone marker signpost
	var sign := MeshInstance3D.new()
	var sign_box := BoxMesh.new()
	sign_box.size = Vector3(2.2, 0.2, 0.1)
	sign.mesh = sign_box
	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_color = cfg["accent"]
	sign.material_override = sign_mat
	sign.position = zone_center + Vector3(0, 1.6, -3.5)
	sign.rotation_degrees.y = 90 if zone_idx == ZONE_CASTLE else 0
	parent.add_child(sign)

	var pole := MeshInstance3D.new()
	var pole_box := CylinderMesh.new()
	pole_box.top_radius = 0.06
	pole_box.bottom_radius = 0.08
	pole_box.height = 1.8
	pole.mesh = pole_box
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color("#5C4630")
	pole.material_override = pole_mat
	pole.position = zone_center + Vector3(0, 0.9, -3.5)
	parent.add_child(pole)

	# Scattered themed props
	for i in 14:
		var angle := randf() * TAU
		var dist := 3.0 + randf() * 4.5
		var pos := zone_center + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		if _near_path(pos):
			continue
		var prop := MeshInstance3D.new()
		var m: Mesh
		match zone_idx:
			ZONE_FOREST:
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.6
				cone.height = 1.6 + randf() * 0.8
				m = cone
			ZONE_DESERT:
				var boulder := SphereMesh.new()
				boulder.radius = 0.5 + randf() * 0.4
				boulder.height = boulder.radius * 1.3
				m = boulder
			ZONE_CASTLE:
				var pillar := BoxMesh.new()
				pillar.size = Vector3(0.7, 1.2 + randf() * 1.0, 0.7)
				m = pillar
		prop.mesh = m
		var mat2 := StandardMaterial3D.new()
		mat2.albedo_color = cfg["props"]
		mat2.roughness = 0.9
		prop.material_override = mat2
		var y_offset := 0.5
		if m is CylinderMesh:
			y_offset = m.height * 0.5
		elif m is SphereMesh:
			y_offset = m.height * 0.5
		elif m is BoxMesh:
			y_offset = m.size.y * 0.5
		prop.position = pos + Vector3(0, y_offset, 0)
		parent.add_child(prop)

func _build_level_node(level_idx: int) -> Node3D:
	var node := Node3D.new()
	node.name = "Level_%d" % level_idx
	node.position = _level_position(level_idx)
	node.set_meta("level_idx", level_idx)

	# Pedestal
	var pedestal := MeshInstance3D.new()
	var ped_mesh := CylinderMesh.new()
	ped_mesh.top_radius = 0.7
	ped_mesh.bottom_radius = 0.85
	ped_mesh.height = 0.4
	pedestal.mesh = ped_mesh
	var ped_mat := StandardMaterial3D.new()
	var zone := _level_zone(level_idx)
	ped_mat.albedo_color = ZONE_COLORS[zone]["accent"]
	ped_mat.metallic = 0.2
	ped_mat.roughness = 0.5
	pedestal.material_override = ped_mat
	pedestal.position = Vector3(0, 0.2, 0)
	node.add_child(pedestal)

	# Top stone
	var top := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = 0.9
	top_mesh.bottom_radius = 0.9
	top_mesh.height = 0.18
	top.mesh = top_mesh
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Color("#E2D7B4")
	top_mat.roughness = 0.6
	top.material_override = top_mat
	top.position = Vector3(0, 0.49, 0)
	node.add_child(top)

	# Icon: a small chess-piece-like obelisk with the level number
	var icon := MeshInstance3D.new()
	var icon_mesh := BoxMesh.new()
	icon_mesh.size = Vector3(0.5, 1.1, 0.5)
	icon.mesh = icon_mesh
	var icon_mat := StandardMaterial3D.new()
	icon_mat.albedo_color = Color("#F0F1EC")
	icon_mat.emission_enabled = true
	icon_mat.emission = _level_color(level_idx)
	icon_mat.emission_energy_multiplier = 0.6
	icon.material_override = icon_mat
	icon.position = Vector3(0, 1.1, 0)
	icon.name = "Icon"
	node.add_child(icon)

	# Number label as a 3D label using a quick sprite-style MeshInstance3D with a billboard
	# (We render the digit as a small 3D plane in front of the icon for visual cue)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.55
	ring_mesh.outer_radius = 0.7
	ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = _level_color(level_idx)
	ring_mat.emission_enabled = true
	ring_mat.emission = _level_color(level_idx)
	ring_mat.emission_energy_multiplier = 0.4
	ring_mat.roughness = 0.4
	ring.material_override = ring_mat
	ring.position = Vector3(0, 1.7, 0)
	ring.rotation_degrees.x = 90
	ring.name = "Ring"
	node.add_child(ring)

	# Collision area for proximity detection
	var area := Area3D.new()
	area.name = "Proximity"
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.3
	shape.height = 2.2
	col.shape = shape
	col.position = Vector3(0, 1.0, 0)
	area.add_child(col)
	area.set_meta("level_idx", level_idx)
	# Connect to player body. We'll just use a per-frame proximity check instead,
	# since body_entered on Area3D requires the body to be a CollisionObject3D
	# descendant of a node with collision_layer set up.
	node.add_child(area)

	return node

func _build_ui() -> void:
	# Top bar with title + back button
	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_top = 20
	top_bar.offset_bottom = 80
	top_bar.add_theme_constant_override("separation", 8)
	add_child(top_bar)

	var back := Button.new()
	back.text = "‹ Back"
	back.custom_minimum_size = Vector2(96, 48)
	UITheme.apply_button(back, UITheme.BG_CARD2, UITheme.TEXT, UITheme.FS_SMALL, UITheme.R_MEDIUM)
	back.pressed.connect(func(): GameManager.show_puzzles())
	top_bar.add_child(back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	var title := Label.new()
	title.text = "Puzzle Campaign"
	title.add_theme_color_override("font_color", UITheme.TEXT)
	title.add_theme_font_size_override("font_size", UITheme.FS_H3)
	top_bar.add_child(title)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer2.custom_minimum_size.x = 80
	top_bar.add_child(spacer2)

	# Bottom hint bar
	_hint_label = Label.new()
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -100
	_hint_label.offset_bottom = -20
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", UITheme.TEXT)
	_hint_label.add_theme_font_size_override("font_size", UITheme.FS_SMALL)
	_hint_label.text = "Tap and hold to move. Walk to a level to begin."
	_hint_label.modulate.a = 0.9
	add_child(_hint_label)

	# Zone indicator pill (top center, below title)
	_build_zone_indicator()

func _build_zone_indicator() -> void:
	var pill := PanelContainer.new()
	pill.name = "ZonePill"
	pill.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	pill.offset_top = 90
	pill.offset_bottom = 130
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill.position.x = (size.x - 220) * 0.5
	pill.custom_minimum_size = Vector2(220, 40)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.13, 0.85)
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	pill.add_theme_stylebox_override("panel", style)
	add_child(pill)

	var lbl := Label.new()
	lbl.name = "ZoneLabel"
	lbl.text = "Forest"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", UITheme.TEXT)
	lbl.add_theme_font_size_override("font_size", UITheme.FS_SMALL)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pill.add_child(lbl)

func _spawn_player_at_current_level() -> void:
	# Find first unsolved level; if all solved, place at last node
	var start_idx := 0
	for i in NUM_LEVELS:
		if not _is_level_completed(i):
			start_idx = i
			break
	_player.position = _level_position(start_idx) + Vector3(0, 0.05, 0)
	_current_level_near = start_idx
	_current_zone = _level_zone(start_idx)
	_build_player_mesh()
	_update_camera()
	_update_zone_indicator()

func _build_player_mesh() -> void:
	# Clear any existing children
	for c in _player.get_children():
		c.queue_free()

	# Knight piece: base + body + head
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.32
	body_mesh.bottom_radius = 0.45
	body_mesh.height = 0.55
	body.mesh = body_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color("#F5F0E1")
	body_mat.roughness = 0.4
	body_mat.metallic = 0.1
	body.material_override = body_mat
	body.position = Vector3(0, 0.3, 0)
	_player.add_child(body)

	var neck := MeshInstance3D.new()
	var neck_mesh := CylinderMesh.new()
	neck_mesh.top_radius = 0.18
	neck_mesh.bottom_radius = 0.22
	neck_mesh.height = 0.3
	neck.mesh = neck_mesh
	var neck_mat := StandardMaterial3D.new()
	neck_mat.albedo_color = Color("#F5F0E1")
	neck_mat.roughness = 0.4
	neck.material_override = neck_mat
	neck.position = Vector3(0, 0.7, 0)
	_player.add_child(neck)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.28
	head_mesh.height = 0.5
	head.mesh = head_mesh
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color("#F5F0E1")
	head_mat.roughness = 0.4
	head.material_override = head_mat
	head.position = Vector3(0, 1.0, 0)
	_player.add_child(head)

	# Ears (knight-horse style)
	for side in [-1, 1]:
		var ear := MeshInstance3D.new()
		var ear_mesh := CylinderMesh.new()
		ear_mesh.top_radius = 0.0
		ear_mesh.bottom_radius = 0.08
		ear_mesh.height = 0.22
		ear.mesh = ear_mesh
		var ear_mat := StandardMaterial3D.new()
		ear_mat.albedo_color = Color("#E2D7B4")
		ear.material_override = ear_mat
		ear.position = Vector3(0.13 * side, 1.25, -0.05)
		ear.rotation_degrees.z = -25 * side
		_player.add_child(ear)

	# Soft glow ring on the ground beneath the player
	var glow := MeshInstance3D.new()
	var glow_mesh := CylinderMesh.new()
	glow_mesh.top_radius = 0.55
	glow_mesh.bottom_radius = 0.55
	glow_mesh.height = 0.02
	glow.mesh = glow_mesh
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color("#E9B949")
	glow_mat.emission_enabled = true
	glow_mat.emission = Color("#E9B949")
	glow_mat.emission_energy_multiplier = 0.6
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.albedo_color.a = 0.45
	glow.material_override = glow_mat
	glow.position = Vector3(0, 0.01, 0)
	_player.add_child(glow)

func _pulse_player() -> void:
	# Idle bob
	var tween := create_tween().set_loops()
	tween.tween_property(_player, "position:y", _player.position.y + 0.08, 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_player, "position:y", _player.position.y, 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ── Input ──────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _interaction_cooldown > 0.0:
		_interaction_cooldown -= get_process_delta_time()

	# Tap to move: when the player taps a point on the ground, walk there.
	if event is InputEventScreenTouch and event.pressed:
		_handle_tap(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_tap(event.position)

	# Tap a level node to enter (when close)
	if _current_level_near >= 0 and _interaction_cooldown <= 0.0:
		if event is InputEventScreenTouch and event.pressed and not event.is_echo():
			_try_enter_nearby_level(event.position)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_try_enter_nearby_level(event.position)

func _handle_tap(screen_pos: Vector2) -> void:
	if _subviewport == null or _subviewport.world_3d == null or _camera == null:
		return
	# Project a ray from the camera and find the ground intersection.
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var space := _subviewport.world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var target: Vector3 = hit.position
	# Clamp to world bounds
	target.x = clamp(target.x, -PATH_RADIUS, PATH_RADIUS)
	target.z = clamp(target.z, -PATH_RADIUS, PATH_RADIUS)
	target.y = 0
	_moving = true
	_target_pos = target
	_hint_label.text = "Walking…"

func _try_enter_nearby_level(_screen_pos: Vector2) -> void:
	if _current_level_near < 0:
		return
	if not _is_level_unlocked(_current_level_near):
		_hint_label.text = "Locked — solve previous levels first"
		_interaction_cooldown = 1.0
		return
	_hint_label.text = "Entering level %d…" % (_current_level_near + 1)
	_interaction_cooldown = 0.5
	# Defer so the label is visible briefly
	get_tree().create_timer(0.25).timeout.connect(func():
		GameManager.feature_flags["campaign"] = true
		_enter_level(_current_level_near)
	)

func _enter_level(level_idx: int) -> void:
	# Launch PuzzlesScreen with the specific level pre-selected and auto-expanded.
	if _current and is_instance_valid(_current):
		_current.queue_free()
	var screen_script := load("res://scripts/ui/PuzzlesScreen.gd")
	var screen: Control = screen_script.new()
	screen.set_meta("preselect_level", level_idx)
	screen.set_meta("preselect_first_unsolved", true)
	_current = screen
	_root_or_self().add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(screen, "modulate:a", 1.0, 0.18)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _root_or_self() -> Node:
	var n: Node = self
	while n.get_parent():
		n = n.get_parent()
	return n

# ── Per-frame ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _moving:
		var to_target := _target_pos - _player.position
		to_target.y = 0
		var dist := to_target.length()
		if dist < 0.05:
			_moving = false
			_hint_label.text = "Walk to a level node to begin."
		else:
			var step := _move_speed * delta
			var move: Vector3 = to_target.normalized() * min(step, dist)
			_player.position += move
			_player.rotation.y = atan2(move.x, move.z)
	# Update zone indicator based on player position
	var new_zone := _zone_at(_player.position)
	if new_zone != _current_zone:
		_current_zone = new_zone
		_update_zone_indicator()
	# Camera follow
	if _camera and _camera.is_inside_tree():
		var target_pos := _player.position + Vector3(0, 16, 14)
		_camera.position = _camera.position.lerp(target_pos, delta * 4.0)
		var look := _camera.position + (_player.position - _camera.position) * 0.3
		_camera.look_at(look, Vector3.UP)
	# Proximity check for level nodes
	_update_proximity()

func _zone_at(pos: Vector3) -> int:
	# Three vertical zones: forest (z < -3), desert (-3..3), castle (z > 3)
	if pos.z < -3.0:
		return ZONE_FOREST
	elif pos.z < 3.0:
		return ZONE_DESERT
	else:
		return ZONE_CASTLE

func _update_zone_indicator() -> void:
	# Find pill by name across children
	for child in get_children():
		if child.name == "ZonePill":
			var lbl := child.get_node_or_null("ZoneLabel")
			if lbl:
				lbl.text = _zone_name(_current_zone)
				lbl.add_theme_color_override("font_color", ZONE_COLORS[_current_zone]["accent"])
			return

func _update_camera() -> void:
	if _camera and _camera.is_inside_tree():
		_camera.look_at_from_position(_player.position + Vector3(0, 16, 14), _player.position, Vector3.UP)

# ── Helpers ────────────────────────────────────────────────────────────────────

func _level_position(idx: int) -> Vector3:
	# Path winds through three zones
	var t := float(idx) / float(NUM_LEVELS - 1)
	var angle := t * TAU * 1.5  # 1.5 turns
	var x := sin(angle) * PATH_RADIUS * 0.7
	var z := cos(angle) * PATH_RADIUS * 0.6
	# Spread zones along z
	var zone_offset := -6.0 + t * 12.0
	return Vector3(x, 0, z * 0.6 + zone_offset * 0.4)

func _level_zone(idx: int) -> int:
	if idx < 4: return ZONE_FOREST
	if idx < 8: return ZONE_DESERT
	return ZONE_CASTLE

func _zone_center(zone_idx: int) -> Vector3:
	match zone_idx:
		ZONE_FOREST: return Vector3(-2.0, 0, -7.0)
		ZONE_DESERT: return Vector3(0.0, 0, 0.0)
		ZONE_CASTLE: return Vector3(2.0, 0, 7.0)
	return Vector3.ZERO

func _zone_name(zone_idx: int) -> String:
	match zone_idx:
		ZONE_FOREST: return "Forest of First Moves"
		ZONE_DESERT: return "Desert of Tactics"
		ZONE_CASTLE: return "Castle of Combinations"
	return ""

func _level_color(idx: int) -> Color:
	# Smooth color ramp by level
	var t := float(idx) / float(NUM_LEVELS - 1)
	return Color(0.5 + t * 0.5, 0.9 - t * 0.3, 0.4).lerp(UITheme.GOLD, t * 0.4)

func _near_path(pos: Vector3) -> bool:
	for i in NUM_LEVELS - 1:
		var a := _level_position(i)
		var b := _level_position(i + 1)
		var ab := b - a
		var len2: float = ab.length_squared()
		if len2 < 0.01:
			continue
		var t: float = clampf(((pos - a).dot(ab)) / len2, 0.0, 1.0)
		var closest: Vector3 = a + ab * t
		if pos.distance_to(closest) < 0.9:
			return true
	return false

func _is_level_unlocked(idx: int) -> bool:
	# Use PuzzleManager if available, otherwise all unlocked in dev/test
	if PuzzleManager and PuzzleManager.has_method("is_level_unlocked"):
		return PuzzleManager.is_level_unlocked(idx)
	return true

func _is_level_completed(idx: int) -> bool:
	if PuzzleManager and PuzzleManager.has_method("level_solved"):
		var lv: Dictionary = PuzzleManager.levels[idx]
		return PuzzleManager.level_solved(idx) >= lv["puzzles"].size()
	return false

# ── Proximity (per-frame) ──────────────────────────────────────────────────────

func _update_proximity() -> void:
	var nearest := -1
	var nearest_dist := 2.0  # Max interaction distance
	for i in _level_nodes.size():
		var n: Node3D = _level_nodes[i]
		var d := n.position.distance_to(_player.position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = i
	if nearest != _current_level_near:
		_current_level_near = nearest
		if nearest >= 0:
			if not _is_level_unlocked(nearest):
				_hint_label.text = "🔒 Level %d locked" % (nearest + 1)
			else:
				_hint_label.text = "Tap to enter Level %d" % (nearest + 1)
		else:
			_hint_label.text = "Walk to a level node to begin."
