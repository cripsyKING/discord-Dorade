class_name OutfitClothPresets
extends RefCounted
## Cloth set-ups of the outfits shipped in assets/outfits (bone names from build_outfit.py).


static func body_colliders(hip_radius := 0.13, thigh_radius := 0.085, shin_radius := 0.065) -> Array[ClothCollider]:
	var out: Array[ClothCollider] = []
	out.append(ClothCollider.capsule("hips", "thigh.L", "thigh.R", hip_radius))
	out.append(ClothCollider.capsule("torso", "spine", "chest", 0.14))
	for s in ["L", "R"]:
		out.append(ClothCollider.capsule("thigh." + s, "thigh." + s, "shin." + s, thigh_radius))
		out.append(ClothCollider.capsule("shin." + s, "shin." + s, "foot." + s, shin_radius))
		out.append(ClothCollider.capsule("forearm." + s, "forearm." + s, "hand." + s, 0.045))
	return out


## Roy Mustang: heavy wool military coat split on both sides, leather holster,
## gold aiguillette cords, jodhpur trousers.
static func mustang() -> Dictionary:
	var coat_p := ClothProfile.long_coat()
	coat_p.resource_name = "Manteau militaire (laine lourde)"
	coat_p.pose_stiffness = 5.0
	coat_p.air_drag = 1.8
	coat_p.wind_sensitivity = 0.75
	coat_p.flutter = 0.08
	coat_p.inertia_transfer = 0.3
	coat_p.max_angle = 75.0
	coat_p.flare = 1.0
	coat_p.lateral_max_stretch = 1.25
	coat_p.max_bend = 28.0
	var coat := ClothChainGroup.make("coat", "coat_", coat_p)
	coat.closed_loop = true
	coat.slits = PackedStringArray(["coat_02:coat_03", "coat_08:coat_09"])  # side vents

	var holster_p := ClothProfile.thick()
	holster_p.max_angle = 35.0
	var holster := ClothChainGroup.make("holster", "holster_", holster_p)
	holster.link_neighbours = false
	holster.tip_length_scale = 1.35  # single bone: 0.15 m * 1.35
	holster.ignored_colliders = PackedStringArray(["torso", "forearm.L", "forearm.R"])

	var cord_p := ClothProfile.light()
	cord_p.wind_sensitivity = 0.6
	cord_p.max_angle = 55.0
	cord_p.air_drag = 2.5
	var cords := ClothChainGroup.make("aiguillette", "aiguillette_", cord_p)
	cords.link_neighbours = false
	cords.ignored_colliders = PackedStringArray(["hips", "thigh.L", "thigh.R", "shin.L", "shin.R"])

	var pants_p := ClothProfile.classic()
	pants_p.pose_stiffness = 14.0
	pants_p.max_angle = 22.0
	pants_p.air_drag = 0.8
	pants_p.wind_sensitivity = 0.3
	var pants := ClothChainGroup.make("trousers", "trouser_", pants_p)
	pants.link_neighbours = false
	pants.ignored_colliders = PackedStringArray(["hips", "thigh.L", "thigh.R", "shin.L", "shin.R", "torso"])

	return {
		"groups": [coat, holster, cords, pants] as Array[ClothChainGroup],
		"colliders": body_colliders(0.13, 0.095, 0.07),
	}


## Edward Elric: light red coat open on the front, behaves like a cape.
static func edward() -> Dictionary:
	var coat_p := ClothProfile.long_coat()
	coat_p.resource_name = "Manteau rouge (cape)"
	coat_p.pose_stiffness = 3.2
	coat_p.tip_stiffness_scale = 0.25
	coat_p.air_drag = 2.8
	coat_p.wind_sensitivity = 1.3
	coat_p.flutter = 0.3
	coat_p.inertia_transfer = 0.2
	coat_p.max_angle = 95.0
	coat_p.lateral_stiffness = 0.45
	coat_p.max_bend = 32.0
	var coat := ClothChainGroup.make("coat", "coat_", coat_p)
	coat.closed_loop = false
	coat.max_link_angle = 40.0  # the open front (144°) is never linked
	return {
		"groups": [coat] as Array[ClothChainGroup],
		"colliders": body_colliders(0.12, 0.08, 0.06),
	}


static func for_name(preset: String) -> Dictionary:
	match preset:
		"mustang":
			return mustang()
		"edward":
			return edward()
	return {}
