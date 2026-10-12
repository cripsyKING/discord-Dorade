class_name ClothOutfit
extends Node3D
## Drop-in node for an outfit: finds the imported [Skeleton3D], applies textile materials,
## and adds the [SecondaryClothSimulator] (and optionally a [BonePoseCopier] so the outfit
## follows the skeleton of the character that wears it).
##
## Scene layout: ClothOutfit (this script) > instance of the outfit .glb

@export_enum("auto", "mustang", "edward", "riza", "olivier", "scar", "winry", "custom") var preset := "auto"
## Used when [member preset] is "custom".
@export var custom_groups: Array[ClothChainGroup] = []
@export var custom_colliders: Array[ClothCollider] = []
@export var fabric_materials := true
## glTF material name → textile preset ("wool", "canvas", "cotton", "light", "leather", "" = keep).
@export var material_overrides := {}
@export var simulate := true:
	set(v):
		simulate = v
		if simulator:
			simulator.active = v
@export var debug_draw := false:
	set(v):
		debug_draw = v
		if simulator:
			simulator.debug_draw = v
## Skeleton of the character wearing the outfit (same bone names). Leave empty when the
## outfit skeleton is animated directly.
@export var pose_source: Skeleton3D

var skeleton: Skeleton3D
var simulator: SecondaryClothSimulator
var copier: BonePoseCopier


func _ready() -> void:
	var found := find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_error("ClothOutfit: no Skeleton3D under %s" % name)
		return
	skeleton = found[0]
	if fabric_materials:
		FabricLibrary.apply(self, material_overrides)
	if pose_source:
		copier = BonePoseCopier.new()
		copier.name = "BonePoseCopier"
		copier.source = pose_source
		skeleton.add_child(copier)
	simulator = SecondaryClothSimulator.new()
	simulator.name = "SecondaryClothSimulator"
	var cfg := _config()
	simulator.groups = cfg.get("groups", [] as Array[ClothChainGroup])
	simulator.colliders = cfg.get("colliders", [] as Array[ClothCollider])
	simulator.debug_draw = debug_draw
	simulator.active = simulate
	skeleton.add_child(simulator)


## Inserts a pose modifier (IK, procedural animation...) so it runs before the cloth.
func add_pose_modifier(mod: SkeletonModifier3D) -> void:
	skeleton.add_child(mod)
	skeleton.move_child(mod, simulator.get_index())


func resolved_preset() -> String:
	if preset != "auto":
		return preset
	if skeleton.find_bone("sword_00_0") >= 0:
		return "olivier"
	if skeleton.find_bone("sash_00_0") >= 0:
		return "scar"
	if skeleton.find_bone("sleeve_00_0") >= 0:
		return "winry"
	if skeleton.find_bone("aiguillette_00_0") >= 0:
		return "mustang"
	if skeleton.find_bone("holster_00_0") >= 0:
		return "riza"
	if skeleton.find_bone("coat_00_0") >= 0:
		return "edward"
	return "custom"


func _config() -> Dictionary:
	var p := resolved_preset()
	if p == "custom":
		return {"groups": custom_groups, "colliders": custom_colliders}
	return OutfitClothPresets.for_name(p)
