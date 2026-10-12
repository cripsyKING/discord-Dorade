class_name FabricLibrary
extends RefCounted
## Replaces the imported glTF materials of an outfit by textile-specific materials.
##
## The base colour / texture of the imported material is kept; the surface response
## (roughness, weave, sheen, thickness, translucency) comes from the textile preset.

const SHADER := preload("res://addons/secondary_cloth/fabric/fabric.gdshader")
const WOOL_N := preload("res://addons/secondary_cloth/fabric/weave_wool_twill_n.png")
const COTTON_N := preload("res://addons/secondary_cloth/fabric/weave_cotton_plain_n.png")
const LEATHER_N := preload("res://addons/secondary_cloth/fabric/grain_leather_n.png")

const PRESETS := {
	# heavy woven wool (military uniform, coats)
	"wool": {"normal": "wool", "roughness": 0.86, "specular": 0.22, "weave_scale": 55.0,
		"weave_strength": 0.35, "sheen": 0.18, "sheen_tint": 0.8, "inner_darkening": 0.4,
		"translucency": 0.0, "fold_shadow": 0.4},
	# canvas / gabardine coat with a printed texture atlas
	"canvas": {"normal": "wool", "roughness": 0.8, "specular": 0.25, "weave_scale": 70.0,
		"weave_strength": 0.3, "sheen": 0.12, "sheen_tint": 0.7, "inner_darkening": 0.45,
		"translucency": 0.05, "fold_shadow": 0.4},
	# cotton: gloves, trims, piping
	"cotton": {"normal": "cotton", "roughness": 0.78, "specular": 0.3, "weave_scale": 90.0,
		"weave_strength": 0.25, "sheen": 0.08, "sheen_tint": 0.5, "inner_darkening": 0.3,
		"translucency": 0.12, "fold_shadow": 0.3},
	# light fabric: scarves, shirts, cords
	"light": {"normal": "cotton", "roughness": 0.7, "specular": 0.35, "weave_scale": 120.0,
		"weave_strength": 0.2, "sheen": 0.15, "sheen_tint": 0.6, "inner_darkening": 0.15,
		"translucency": 0.35, "fold_shadow": 0.25},
	# leather keeps the imported roughness (polished boots stay glossy)
	"leather": {"normal": "leather", "roughness": -1.0, "specular": 0.45, "weave_scale": 35.0,
		"weave_strength": 0.12, "sheen": 0.0, "sheen_tint": 0.0, "inner_darkening": 0.5,
		"translucency": 0.0, "fold_shadow": 0.25},
}

## Name keywords → preset, tested in order. Anything not matched keeps its imported material
## (metals: buttons, buckles, gold braid).
const KEYWORDS := [
	["revers", "cotton"], ["cuir", "leather"], ["leather", "leather"], ["botte", "leather"], ["semelle", "leather"],
	["holster", "leather"], ["ceinture", "leather"], ["belt", "leather"],
	["metal", ""], ["argent", ""], ["or_", ""], ["gold", ""], ["bouton", ""], ["boucle", ""],
	["gant", "cotton"], ["glove", "cotton"], ["galon", "cotton"], ["bordure", "cotton"],
	["trim", "cotton"], ["manteau", "canvas"], ["coat", "canvas"],
	["tissu", "wool"], ["bleu", "wool"], ["veste", "wool"], ["pantalon", "wool"], ["cloth", "wool"],
]


## Preset name for a glTF material name ("" = keep the imported material).
static func preset_for(material_name: String, overrides: Dictionary = {}) -> String:
	if overrides.has(material_name):
		return overrides[material_name]
	var low := material_name.to_lower()
	for kw in KEYWORDS:
		if low.contains(kw[0]):
			return kw[1]
	return ""


static func make_material(source: Material, preset_name: String) -> Material:
	var p: Dictionary = PRESETS[preset_name]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.resource_name = (source.resource_name if source else "fabric") + " (" + preset_name + ")"
	var rough := 0.8
	if source is BaseMaterial3D:
		var s: BaseMaterial3D = source
		m.set_shader_parameter("albedo", s.albedo_color)
		if s.albedo_texture:
			m.set_shader_parameter("albedo_texture", s.albedo_texture)
		rough = s.roughness
	m.set_shader_parameter("roughness", rough if p.roughness < 0.0 else p.roughness)
	for k in ["specular", "weave_scale", "weave_strength", "sheen", "sheen_tint",
			"inner_darkening", "translucency", "fold_shadow"]:
		m.set_shader_parameter(k, p[k])
	m.set_shader_parameter("weave_normal", {"wool": WOOL_N, "cotton": COTTON_N, "leather": LEATHER_N}[p.normal])
	return m


## Applies textile materials to every mesh under [param root]. Returns the number of surfaces changed.
static func apply(root: Node, overrides: Dictionary = {}) -> int:
	var count := 0
	var cache := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src: Material = mi.get_active_material(s)
			var mat_name: String = src.resource_name if src else ""
			var preset: String = preset_for(mat_name, overrides)
			if preset == "":
				continue
			if not cache.has(mat_name):
				cache[mat_name] = make_material(src, preset)
			mi.set_surface_override_material(s, cache[mat_name])
			count += 1
	return count
