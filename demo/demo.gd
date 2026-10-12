extends Node3D
## Playable demo of the secondary cloth system (built in code so it stays engine-version proof).
##
## ZQSD / WASD / arrows: move   Shift: run   Space: jump   Mouse (click to capture): camera
## Tab: switch outfit   V: wind on/off   B: wind strength   F1: debug chains   F2: cloth on/off

const PlayerScript := preload("res://demo/demo_player.gd")
const OUTFITS := [
	{"name": "Roy Mustang", "glb": "res://assets/outfits/tenue_mustang.glb", "arm_down": 0.0,
		"skin": Color(0.93, 0.76, 0.64), "hair": Color(0.05, 0.05, 0.06)},
	{"name": "Edward Elric", "glb": "res://assets/outfits/tenue_edward.glb", "arm_down": 52.0,
		"skin": Color(0.95, 0.8, 0.68), "hair": Color(0.85, 0.66, 0.25)},
]
const WIND_LEVELS := [2.5, 6.0, 11.0]

var player: CharacterBody3D
var camera: Camera3D
var wind: ClothWindZone
var hud: Label
var outfit_index := 0
var wind_level := 1
var pitch := -0.25
var cam_distance := 3.4
## Extra yaw of the camera around the player that does not change the controls
## (C cycles back / side / front views).
var camera_orbit_offset := 0.0
var _cam_pos := Vector3.ZERO


func _ready() -> void:
	_setup_input()
	_build_world()
	_build_player()
	_spawn_outfit(0)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_Z, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_Q, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT], "jump": [KEY_SPACE],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _build_world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.47, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.82)
	sky_mat.ground_horizon_color = Color(0.6, 0.6, 0.62)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true  # contact shadows inside the folds
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.ssil_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor_mesh.mesh = plane
	var fm := ShaderMaterial.new()
	fm.shader = _checker_shader()
	floor_mesh.material_override = fm
	floor_body.add_child(floor_mesh)
	add_child(floor_body)

	# a few blocks to jump on and off
	for b in [[Vector3(4, 0.4, -4), Vector3(2, 0.8, 2)], [Vector3(7, 0.8, -4), Vector3(2, 1.6, 2)],
			[Vector3(-5, 0.3, -7), Vector3(3, 0.6, 3)], [Vector3(-3, 0.15, 3), Vector3(6, 0.3, 1.5)]]:
		var body := StaticBody3D.new()
		body.position = b[0]
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[1]
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.52, 0.48)
		mat.roughness = 0.9
		mi.material_override = mat
		body.add_child(mi)
		add_child(body)

	wind = ClothWindZone.new()
	wind.strength = WIND_LEVELS[wind_level]
	wind.enabled = false
	wind.rotation_degrees = Vector3(0, 70, 0)
	add_child(wind)

	camera = Camera3D.new()
	camera.fov = 55.0
	add_child(camera)

	var layer := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(14, 10)
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hud)
	add_child(layer)


func _checker_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 c = floor(wp.xz);
	float k = mod(c.x + c.y, 2.0);
	vec2 f = abs(fract(wp.xz) - 0.5);
	float line = smoothstep(0.49, 0.5, max(f.x, f.y));
	ALBEDO = mix(vec3(0.26, 0.28, 0.25), vec3(0.31, 0.33, 0.29), k) * (1.0 - line * 0.3);
	ROUGHNESS = 0.95;
}
"""
	return sh


func _build_player() -> void:
	player = PlayerScript.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	player.add_child(cs)
	player.visual = Node3D.new()
	player.add_child(player.visual)
	add_child(player)


func _spawn_outfit(index: int) -> void:
	outfit_index = index
	var info: Dictionary = OUTFITS[index]
	for c in player.visual.get_children():
		c.queue_free()
	var outfit := ClothOutfit.new()
	outfit.add_child(load(info.glb).instantiate())
	player.visual.add_child(outfit)
	var loco := ProceduralLocomotion.new()
	loco.arm_down = info.arm_down
	outfit.add_pose_modifier(loco)
	_add_head(outfit, info)
	player.outfit = outfit
	player.locomotion = loco


func _add_head(outfit: ClothOutfit, info: Dictionary) -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "neck"
	outfit.skeleton.add_child(att)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = info.skin
	skin.roughness = 0.6
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.105
	sm.height = 0.24
	head.mesh = sm
	head.material_override = skin
	head.position = Vector3(0, 0.17, 0)
	att.add_child(head)
	var hair := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.112
	hm.height = 0.17
	hm.is_hemisphere = true
	hair.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = info.hair
	hmat.roughness = 0.5
	hair.material_override = hmat
	hair.position = Vector3(0, 0.2, 0.01)
	att.add_child(hair)
	var neck := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.05
	cm.height = 0.12
	neck.mesh = cm
	neck.material_override = skin
	neck.position = Vector3(0, 0.07, 0)
	att.add_child(neck)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_distance = maxf(1.6, cam_distance - 0.25)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_distance = minf(8.0, cam_distance + 0.25)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.camera_yaw -= event.relative.x * 0.004
		pitch = clampf(pitch - event.relative.y * 0.003, -1.2, 0.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_TAB:
				_spawn_outfit((outfit_index + 1) % OUTFITS.size())
			KEY_V:
				wind.enabled = not wind.enabled
			KEY_B:
				wind_level = (wind_level + 1) % WIND_LEVELS.size()
				wind.strength = WIND_LEVELS[wind_level]
			KEY_F1:
				player.outfit.debug_draw = not player.outfit.debug_draw
			KEY_F2:
				player.outfit.simulate = not player.outfit.simulate
			KEY_C:
				camera_orbit_offset = fmod(camera_orbit_offset + PI * 0.5, TAU)


func _process(delta: float) -> void:
	var target := player.global_position + Vector3(0, 1.25, 0)
	var offset := Vector3(0, 0, cam_distance).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, player.camera_yaw + camera_orbit_offset)
	_cam_pos = _cam_pos.lerp(target + offset, 1.0 - exp(-10.0 * delta)) if _cam_pos != Vector3.ZERO else target + offset
	camera.global_position = _cam_pos
	camera.look_at(target)
	var sim: SecondaryClothSimulator = player.outfit.simulator if player.outfit else null
	hud.text = "%s  |  %d fps\nZQSD/WASD bouger · Shift courir · Espace sauter · clic + souris caméra\nTab tenue · C vue caméra · V vent (%s, %.1f m/s) · B force du vent · F1 debug chaînes · F2 tissu (%s)\nparticules simulées : %d" % [
		OUTFITS[outfit_index].name, Engine.get_frames_per_second(),
		"on" if wind.enabled else "off", wind.strength,
		"on" if player.outfit and player.outfit.simulate else "off",
		sim.get_particle_count() if sim else 0]
