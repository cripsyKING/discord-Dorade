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


## Riza Hawkeye: military jacket with a short peplum (classic wool), holster at the back.
static func riza() -> Dictionary:
	var hem_p := ClothProfile.classic()
	hem_p.resource_name = "Basque de veste (laine)"
	hem_p.pose_stiffness = 4.5
	hem_p.tip_stiffness_scale = 0.6
	hem_p.air_drag = 2.4
	hem_p.max_angle = 45.0
	hem_p.max_bend = 25.0
	hem_p.flare = 1.2
	var hem := ClothChainGroup.make("coat", "coat_", hem_p)
	hem.closed_loop = true
	var holster_p := ClothProfile.thick()
	holster_p.max_angle = 30.0
	var holster := ClothChainGroup.make("holster", "holster_", holster_p)
	holster.link_neighbours = false
	holster.tip_length_scale = 1.15
	holster.ignored_colliders = PackedStringArray(["torso", "forearm.L", "forearm.R"])
	return {"groups": [hem, holster] as Array[ClothChainGroup], "colliders": body_colliders(0.13, 0.09, 0.07)}


## Olivier Mira Armstrong: heavy Briggs greatcoat down to the ankles, open at the front
## below the belt, sabre swinging at the hip.
static func olivier() -> Dictionary:
	var coat_p := ClothProfile.long_coat()
	coat_p.resource_name = "Capote de Briggs (laine épaisse)"
	coat_p.pose_stiffness = 5.0
	coat_p.tip_stiffness_scale = 0.35
	coat_p.gravity_scale = 1.1
	coat_p.air_drag = 1.7
	coat_p.wind_sensitivity = 0.7
	coat_p.flutter = 0.06
	coat_p.flare = 0.9
	coat_p.inertia_transfer = 0.3
	coat_p.max_angle = 80.0
	coat_p.max_bend = 26.0
	coat_p.lateral_max_stretch = 1.2
	var coat := ClothChainGroup.make("coat", "coat_", coat_p)
	coat.closed_loop = true
	coat.slits = PackedStringArray(["coat_05:coat_06"])  # front opening
	var sword_p := ClothProfile.thick()
	sword_p.resource_name = "Sabre (rigide)"
	sword_p.max_angle = 28.0
	sword_p.air_drag = 0.3
	var sword := ClothChainGroup.make("sword", "sword_", sword_p)
	sword.link_neighbours = false
	sword.tip_length_scale = 5.2  # single 0.78 m bone
	sword.ignored_colliders = PackedStringArray(["torso", "forearm.L", "forearm.R", "hips"])
	return {"groups": [coat, sword] as Array[ClothChainGroup], "colliders": body_colliders(0.13, 0.095, 0.075)}


## Scar: open canvas jacket (front flaps) and a light sash knotted on the hip.
static func scar() -> Dictionary:
	var jacket_p := ClothProfile.classic()
	jacket_p.resource_name = "Veste ouverte (toile)"
	jacket_p.pose_stiffness = 6.0
	jacket_p.air_drag = 2.0
	jacket_p.max_angle = 55.0
	jacket_p.max_bend = 30.0
	jacket_p.flutter = 0.15
	var jacket := ClothChainGroup.make("coat", "coat_", jacket_p)
	jacket.closed_loop = true
	jacket.slits = PackedStringArray(["coat_03:coat_04"])
	var sash_p := ClothProfile.light()
	sash_p.resource_name = "Écharpe nouée (léger)"
	var sash := ClothChainGroup.make("sash", "sash_", sash_p)
	sash.link_neighbours = true
	sash.max_link_angle = 90.0
	sash.ignored_colliders = PackedStringArray(["torso", "forearm.L", "forearm.R"])
	return {"groups": [jacket, sash] as Array[ClothChainGroup], "colliders": body_colliders(0.13, 0.1, 0.075)}


## Winry Rockbell: jumpsuit top folded down at the back, sleeves knotted at the waist,
## bandana tails.
static func winry() -> Dictionary:
	var drape_p := ClothProfile.classic()
	drape_p.resource_name = "Haut de combinaison replié"
	drape_p.pose_stiffness = 6.0
	drape_p.max_angle = 60.0
	drape_p.max_bend = 32.0
	var drape := ClothChainGroup.make("coat", "coat_", drape_p)
	var sleeve_p := ClothProfile.classic()
	sleeve_p.resource_name = "Manches nouées"
	sleeve_p.pose_stiffness = 4.0
	sleeve_p.air_drag = 2.2
	sleeve_p.max_angle = 70.0
	var sleeves := ClothChainGroup.make("sleeves", "sleeve_", sleeve_p)
	sleeves.max_link_angle = 120.0
	sleeves.ignored_colliders = PackedStringArray(["torso", "hips"])
	var band_p := ClothProfile.light()
	band_p.resource_name = "Pans de bandana"
	var bandana := ClothChainGroup.make("bandana", "bandana_", band_p)
	bandana.max_link_angle = 120.0
	bandana.ignored_colliders = PackedStringArray(["hips", "thigh.L", "thigh.R", "shin.L", "shin.R", "forearm.L", "forearm.R"])
	return {"groups": [drape, sleeves, bandana] as Array[ClothChainGroup], "colliders": body_colliders(0.13, 0.098, 0.08)}


static func for_name(preset: String) -> Dictionary:
	match preset:
		"mustang":
			return mustang()
		"edward":
			return edward()
		"riza":
			return riza()
		"olivier":
			return olivier()
		"scar":
			return scar()
		"winry":
			return winry()
	return {}
