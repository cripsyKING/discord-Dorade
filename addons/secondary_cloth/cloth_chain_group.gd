@tool
class_name ClothChainGroup
extends Resource
## A set of bone chains simulated together with the same [ClothProfile].
##
## Chains are found automatically: every bone named [code]<prefix><id>_<index>[/code]
## ([code]coat_03_0, coat_03_1, ...[/code]) belongs to chain [code]<prefix><id>[/code].
## Chains are ordered by angle around the parent bone so neighbours can be linked
## (skirts, capes) to keep the fabric closed.

@export var name := "coat"
## Prefix of the bone names, e.g. [code]coat_[/code].
@export var bone_prefix := "coat_"
@export var profile: ClothProfile
## Link each chain to its angular neighbours (skirt, cape, coat tails).
@export var link_neighbours := true
## Also link the last chain to the first one (closed skirt).
@export var closed_loop := false
## Never link two chains separated by more than this angle (open coat fronts).
@export_range(0.0, 180.0) var max_link_angle := 50.0
## Pairs of chains that must stay independent (slits), e.g. [code]"coat_02:coat_03"[/code].
@export var slits: PackedStringArray = []
## Length of the virtual segment after the last bone, relative to the previous segment.
@export_range(0.1, 2.0) var tip_length_scale := 1.0
## Weight of this group in the final pose (0 = animation only).
@export_range(0.0, 1.0) var influence := 1.0
## Bones listed here (by collider name) are ignored by this group.
@export var ignored_colliders: PackedStringArray = []


static func make(group_name: String, prefix: String, cloth: ClothProfile) -> ClothChainGroup:
	var g := ClothChainGroup.new()
	g.name = group_name
	g.bone_prefix = prefix
	g.profile = cloth
	return g
