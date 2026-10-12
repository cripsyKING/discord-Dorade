"""Rebuild an outfit GLB: material fixes, geometry cleanup, body + cloth skeleton, procedural skinning.

usage: python3 build_outfit.py <mustang|edward|riza|olivier|scar|winry> <in.glb> <out.glb>
(riza / olivier / scar / winry come from generate_fma_outfits.py)
Blender axes: +Y = character front, +Z = up, +X = side of the ".L" bones.
"""
import bpy, bmesh, sys, math
from mathutils import Vector
from collections import defaultdict

OUTFIT, SRC, DST = sys.argv[1], sys.argv[2], sys.argv[3]

# --------------------------------------------------------------------------- body skeletons
def mirror(bones):
    out = dict(bones)
    for n, (p, h, t) in bones.items():
        if n.endswith(".L"):
            m = lambda v: (-v[0], v[1], v[2])
            out[n[:-2] + ".R"] = (p[:-2] + ".R" if p and p.endswith(".L") else p, m(h), m(t))
    return out

BODY = {
    "mustang": mirror({
        "pelvis": (None, (0, 0, 0.96), (0, 0, 1.056)),
        "spine": ("pelvis", (0, 0, 1.1), (0, 0, 1.28)),
        "chest": ("spine", (0, 0, 1.28), (0, 0, 1.42)),
        "neck": ("chest", (0, 0, 1.44), (0, 0, 1.58)),
        "shoulder.L": ("chest", (0.0, 0, 1.42), (0.175, -0.008, 1.4)),
        "upper_arm.L": ("shoulder.L", (0.175, -0.008, 1.4), (0.233, -0.02, 1.18)),
        "forearm.L": ("upper_arm.L", (0.233, -0.02, 1.18), (0.275, -0.005, 0.96)),
        "hand.L": ("forearm.L", (0.275, -0.005, 0.96), (0.292, -0.005, 0.736)),
        "thigh.L": ("pelvis", (0.095, 0, 0.95), (0.095, 0, 0.5)),
        "shin.L": ("thigh.L", (0.095, 0, 0.5), (0.095, 0, 0.1)),
        "foot.L": ("shin.L", (0.095, 0, 0.1), (0.095, 0.2, 0.02)),
    }),
    "edward": mirror({
        "pelvis": (None, (0, 0, 0.93), (0, 0, 1.03)),
        "spine": ("pelvis", (0, 0, 1.05), (0, 0, 1.25)),
        "chest": ("spine", (0, 0, 1.25), (0, 0, 1.42)),
        "neck": ("chest", (0, 0, 1.43), (0, 0, 1.58)),
        "shoulder.L": ("chest", (0.0, -0.015, 1.40), (0.19, -0.015, 1.39)),
        "upper_arm.L": ("shoulder.L", (0.19, -0.015, 1.39), (0.45, -0.015, 1.225)),
        "forearm.L": ("upper_arm.L", (0.45, -0.015, 1.225), (0.66, -0.01, 1.09)),
        "hand.L": ("forearm.L", (0.66, -0.01, 1.09), (0.79, 0.0, 1.0)),
        "thigh.L": ("pelvis", (0.09, 0, 0.92), (0.09, 0, 0.52)),
        "shin.L": ("thigh.L", (0.09, 0, 0.52), (0.09, 0, 0.1)),
        "foot.L": ("shin.L", (0.09, 0, 0.1), (0.09, 0.15, 0.02)),
    }),
}["edward" if OUTFIT == "edward" else "mustang"]  # generated outfits use Mustang's proportions

# rough half-thickness of the body around each bone, used to normalise distances
BONE_RADIUS = {"pelvis": 0.14, "spine": 0.15, "chest": 0.16, "neck": 0.06, "shoulder": 0.07,
               "upper_arm": 0.05, "forearm": 0.045, "hand": 0.035, "thigh": 0.075, "shin": 0.055, "foot": 0.045}

TORSO = ["pelvis", "spine", "chest", "neck"]
ARMS = [f"{b}.{s}" for s in "LR" for b in ("shoulder", "upper_arm", "forearm", "hand")]
LEGS = [f"{b}.{s}" for s in "LR" for b in ("thigh", "shin")]
FEET = [f"{b}.{s}" for s in "LR" for b in ("shin", "foot")]
HANDS = [f"{b}.{s}" for s in "LR" for b in ("forearm", "hand")]

# --------------------------------------------------------------------------- per outfit config
# coat: chain angles in degrees (atan2(x, y), 0 = front), breaks = slits (pairs of neighbouring
# chain angles that must NOT be linked), loop = skirt closed all around.
if OUTFIT == "mustang":
    CFG = dict(
        materials={
            "Amestris_Bleu_Militaire": dict(base=(0.020, 0.040, 0.150), rough=0.82, spec=0.25, sheen=0.0),
            "Galon_Blanc_Officier": dict(rough=0.7, spec=0.3, sheen=0.0),
            "Ceinture_Cuir_Blanc": dict(rough=0.38, spec=0.5),
            "Or_Militaire_Officier": dict(base=(0.80, 0.56, 0.22), rough=0.32, metal=1.0),
            "Cuir_Bottes_Noir": dict(base=(0.008, 0.008, 0.010), rough=0.28, spec=0.5, coat=0.35),
            "Cuir_Holster_Marron": dict(base=(0.075, 0.025, 0.009), rough=0.5, spec=0.4),
            "Gants_Alchimie_Flamme": dict(rough=0.7, spec=0.2),
            "Semelles_Bottes_Gris": dict(rough=0.7, spec=0.3),
        },
        smooth={"Pans_Manteau_Fendu_Bleu": 4, "Pantalon_Bouffant_Bleu": 4, "Veste_Militaire_Officier": 1},
        subdiv={"Pans_Manteau_Fendu_Bleu": 2, "Pantalon_Bouffant_Bleu": 2, "Veste_Militaire_Officier": 1,
                "Bottes_Cavalerie_Noir": 1, "Gants_Flamme_Mustang": 1, "Ceinture_Officier_Blanche": 1},
        solidify={"Galons_Blancs_Manteau": 0.003, "Galons_Blancs_Officier": 0.003,
                  "Epaulettes_Aiguillette_Or": 0.004, "Boucle_Et_Anneaux_Argent": 0.003},
        coat=dict(meshes=["Pans_Manteau_Fendu_Bleu", "Galons_Blancs_Manteau"], top=0.96, hem=0.34, segs=4,
                  angles=[-165, -135, -105, -75, -45, -15, 15, 45, 75, 105, 135, 165],
                  breaks=[(-105, -75), (75, 105)], loop=True),
        body={
            "Veste_Militaire_Officier": TORSO + ARMS,
            "Galons_Blancs_Officier": TORSO + ARMS,
            "Boutons_Argent_Officier": ["spine", "chest", "pelvis"],
            "Ceinture_Officier_Blanche": ["pelvis"],
            "Boucle_Et_Anneaux_Argent": ["pelvis"],
            "Gants_Flamme_Mustang": HANDS,
            "Pantalon_Bouffant_Bleu": ["pelvis"] + LEGS,
            "Bottes_Cavalerie_Noir": FEET,
            "Semelles_Bottes_Gris": FEET,
            "Epaulettes_Aiguillette_Or": ["chest", "shoulder.L", "shoulder.R", "upper_arm.L", "upper_arm.R"],
        },
        rigid=["Boutons_Argent_Officier", "Boucle_Et_Anneaux_Argent"],
    )
elif OUTFIT in ("riza", "olivier", "scar", "winry"):
    # generated outfits: materials, geometry and UVs are already final
    def ring(n, start=0.0):
        return [start + 360.0 * k / n - (360.0 if start + 360.0 * k / n > 180 else 0) for k in range(n)]
    CFG = dict(materials={}, smooth={}, subdiv={}, solidify={}, body={}, rigid=[], chains=[])
    if OUTFIT == "riza":
        CFG["coat"] = dict(meshes=["Veste_Riza"], top=0.97, hem=0.84, segs=2, exclude_x=0.212,
                           angles=sorted(ring(10, 18)), breaks=[], loop=True)
        CFG["chains"] = [dict(prefix="holster_00", parent="pelvis", meshes=["Holster_Riza"], auto=1, falloff=0.0)]
        CFG["rigid"] = ["Boutons_Riza", "Boucle_Riza"]
    elif OUTFIT == "olivier":
        CFG["coat"] = dict(meshes=["Capote_Pans_Olivier"], top=0.98, hem=0.22, segs=5,
                           angles=[-160, -130, -100, -70, -40, -12, 12, 40, 70, 100, 130, 160],
                           breaks=[(-12, 12)], loop=True)
        a, b = (0.2, 0.06, 0.93), (0.27, -0.32, 0.25)
        CFG["chains"] = [dict(prefix="sword_00", parent="pelvis", joints=[a, b], falloff=0.0,
                              meshes=["Fourreau_Sabre_Olivier", "Garde_Sabre_Olivier"])]
        CFG["rigid"] = ["Boutons_Olivier", "Epaulette_Or_L", "Epaulette_Or_R"]
    elif OUTFIT == "scar":
        CFG["coat"] = dict(meshes=["Veste_Ouverte_Scar"], top=1.0, hem=0.8, segs=2,
                           angles=[-150, -115, -80, -45, 45, 80, 115, 150, 180], breaks=[(-45, 45)], loop=True)
        k = (0.15, 0.08, 0.97)
        CFG["chains"] = [dict(prefix="sash_%02d" % i, parent="pelvis", meshes=["Echarpe_Taille_Scar"], falloff=0.25,
                              joints=[(k[0] + dx, k[1], k[2]), (k[0] + dx * 1.5 + 0.02, k[1] + 0.015, k[2] - 0.2),
                                      (k[0] + dx * 2 + 0.035, k[1] + 0.02, k[2] - 0.42 + dx * 2)])
                         for i, dx in enumerate((-0.015, 0.02))]
    elif OUTFIT == "winry":
        CFG["coat"] = dict(meshes=["Haut_Replie_Winry"], top=0.99, hem=0.7, segs=3,
                           angles=[-150, -125, 125, 150, 180], breaks=[], loop=False)
        k = (0.0, 0.145, 0.955)
        CFG["chains"] = [dict(prefix="sleeve_%02d" % i, parent="pelvis", meshes=["Manches_Nouees_Winry"],
                              falloff=0.35, joints=[(k[0] + sx * 0.02, k[1], k[2] - 0.01),
                                                    (k[0] + sx * 0.06, k[1] + 0.02, k[2] - 0.18),
                                                    (k[0] + sx * 0.07, k[1] + 0.015, k[2] - 0.36)])
                         for i, sx in enumerate((1, -1))]
        bk = (0.0, -0.12, 1.595)
        CFG["chains"] += [dict(prefix="bandana_%02d" % i, parent="neck", meshes=["Bandana_Winry"], falloff=0.6,
                               joints=[bk, (sx * 0.03, bk[1] - 0.03, bk[2] - 0.08),
                                       (sx * 0.05, bk[1] - 0.04, bk[2] - 0.17)])
                          for i, sx in enumerate((1, -1))]
else:
    CFG = dict(
        materials={
            "Manteau_Rouge_Tissu": dict(rough=0.78, spec=0.3, drop_normal=True),
            "Veste_Noire_Tissu": dict(base=(0.035, 0.035, 0.04), rough=0.8, spec=0.3),
            "Pantalon_Noir_Tissu": dict(base=(0.035, 0.035, 0.04), rough=0.8, spec=0.3),
            "Bottes_Cuir_Noir": dict(base=(0.012, 0.012, 0.014), rough=0.3, spec=0.5, coat=0.3),
            "Cuir_Ceinture_Brun": dict(base=(0.06, 0.035, 0.02), rough=0.5),
            "Gants_Blancs_Tissu": dict(rough=0.75, spec=0.25),
            "Revers_Blancs_Bottes": dict(rough=0.8, spec=0.25),
            "Bordures_Blanches_Trim": dict(rough=0.6, spec=0.3),
            "Boucle_Metal_Argent": dict(metal=1.0, rough=0.25),
        },
        smooth={}, subdiv={"Bottes_Cuir_Edward": 1, "Veste_Noire_Edward": 1},
        solidify={"Bordures_Blanches_Veste": 0.002},
        coat=dict(meshes=["Manteau_Rouge_Edward"], top=0.94, hem=0.39, segs=4, exclude_x=0.24,
                  angles=[-72, -99, -126, -153, 180, 153, 126, 99, 72], breaks=[], loop=False),
        body={
            "Manteau_Rouge_Edward": TORSO + ARMS,
            "Veste_Noire_Edward": TORSO + ARMS,
            "Bordures_Blanches_Veste": TORSO,
            "Ceinture_Cuir_Edward": ["pelvis"],
            "Boucle_Ceinture_Metal": ["pelvis"],
            "Gants_Blancs_Edward": HANDS,
            "Pantalon_Noir_Edward": ["pelvis"] + LEGS,
            "Revers_Blancs_Bottes": FEET,
            "Bottes_Cuir_Edward": FEET,
            "Semelles_Bottes_Edward": FEET,
        },
        rigid=["Boucle_Ceinture_Metal"],
    )

# --------------------------------------------------------------------------- import & strip old rig
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = {o.name: o for o in bpy.data.objects if o.type == "MESH" and o.name != "Icosphere"}
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name not in meshes:
        bpy.data.objects.remove(o)
for o in meshes.values():
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
    for m in list(o.modifiers):
        o.modifiers.remove(m)
    o.vertex_groups.clear()
for o in list(bpy.data.objects):
    if o.type == "ARMATURE":
        bpy.data.objects.remove(o)
for o in meshes.values():  # bake transforms
    o.data.transform(o.matrix_world)
    o.matrix_world.identity()

# --------------------------------------------------------------------------- materials (no more "glitter")
for mat in bpy.data.materials:
    c = CFG["materials"].get(mat.name)
    if not mat.use_nodes:
        continue
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        continue
    bsdf.inputs["Sheen Weight"].default_value = 0.0  # white sheen on dark cloth = grey sparkle
    if not c:
        continue
    if "base" in c and not bsdf.inputs["Base Color"].is_linked:
        bsdf.inputs["Base Color"].default_value = (*c["base"], 1)
    if "rough" in c:
        bsdf.inputs["Roughness"].default_value = c["rough"]
    if "metal" in c:
        bsdf.inputs["Metallic"].default_value = c["metal"]
    if "spec" in c:
        bsdf.inputs["Specular IOR Level"].default_value = c["spec"]
        bsdf.inputs["Specular Tint"].default_value = (1, 1, 1, 1)
    if "coat" in c:
        bsdf.inputs["Coat Weight"].default_value = c["coat"]
        bsdf.inputs["Coat Roughness"].default_value = 0.15
    if c.get("drop_normal"):  # the shipped normal map is pure black -> invalid normals
        for l in list(bsdf.inputs["Normal"].links):
            mat.node_tree.links.remove(l)
        for n in list(mat.node_tree.nodes):
            if n.type in ("NORMAL_MAP",) or (n.type == "TEX_IMAGE" and n.image and "Normal" in n.image.name):
                mat.node_tree.nodes.remove(n)

# --------------------------------------------------------------------------- geometry cleanup
def apply_mod(o, mod):
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
        bpy.ops.object.modifier_apply(modifier=mod.name)

for name, o in meshes.items():
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(o.data); bm.free()
    if name in CFG["smooth"]:
        # laplacian smooth that keeps the volume: removes the shard-like spikes of the cloth
        m = o.modifiers.new("smooth", "LAPLACIANSMOOTH")
        m.iterations = CFG["smooth"][name]; m.lambda_factor = 0.6; m.lambda_border = 0.15
        m.use_volume_preserve = True; m.use_normalized = True
        apply_mod(o, m)
    if name in CFG["solidify"]:
        m = o.modifiers.new("thick", "SOLIDIFY")
        m.thickness = CFG["solidify"][name]; m.offset = 1.0; m.use_even_offset = False; m.use_quality_normals = True
        apply_mod(o, m)
    if name in CFG["subdiv"]:
        m = o.modifiers.new("sub", "SUBSURF")
        m.levels = CFG["subdiv"][name]; m.boundary_smooth = "PRESERVE_CORNERS"
        m.uv_smooth = "PRESERVE_BOUNDARIES"
        apply_mod(o, m)
    for p in o.data.polygons:
        p.use_smooth = True
    if not o.data.uv_layers:
        # box projection, 1 UV unit = 1 m: lets the Godot fabric shader tile its weave detail
        uv = o.data.uv_layers.new(name="UVMap")
        for p in o.data.polygons:
            n = p.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for li in p.loop_indices:
                c = o.data.vertices[o.data.loops[li].vertex_index].co
                uv.data[li].uv = {0: (c.y, c.z), 1: (c.x, c.z), 2: (c.x, c.y)}[ax]

# --------------------------------------------------------------------------- skeleton
coat = CFG["coat"]
all_coat_verts = [v.co.copy() for n in coat["meshes"] for v in meshes[n].data.vertices]

def ang(v):
    return math.degrees(math.atan2(v.x, v.y))

def adiff(a, b):
    return (a - b + 180) % 360 - 180

def surface_point(theta, z):
    """Average coat surface position near (theta, z), slightly pushed inward."""
    for win_a, win_z in ((10, 0.03), (20, 0.05), (35, 0.09)):
        pts = [v for v in all_coat_verts if abs(v.z - z) < win_z and abs(adiff(ang(v), theta)) < win_a]
        if pts:
            break
    c = sum(pts, Vector()) / len(pts)
    c.z = z
    h = Vector((c.x, c.y, 0))
    return c - h.normalized() * 0.012 if h.length > 0.02 else c

chains = []  # (name prefix, angle, [joint positions])
for i, a in enumerate(coat["angles"]):
    zs = [coat["top"] - k * (coat["top"] - coat["hem"]) / coat["segs"] for k in range(coat["segs"] + 1)]
    chains.append((f"coat_{i:02d}", a, [surface_point(a, z) for z in zs]))

extra_chains = []  # (prefix, parent, joints)
for ch in CFG.get("chains", []):
    if ch.get("auto"):  # single bone from the top to the bottom of the mesh
        vs = [v.co for n in ch["meshes"] for v in meshes[n].data.vertices]
        cx = sum(v.x for v in vs) / len(vs); cy = sum(v.y for v in vs) / len(vs)
        ch["joints"] = [(cx, cy, max(v.z for v in vs)), (cx, cy, min(v.z for v in vs))]
    ch["joints"] = [Vector(j) for j in ch["joints"]]
    extra_chains.append((ch["prefix"], ch["parent"], ch["joints"]))
if OUTFIT == "mustang":
    # holster: heavy leather swinging from the belt
    hv = [v.co for v in meshes["Holster_Pistolet_Cuir"].data.vertices]
    top = max(v.z for v in hv); bot = min(v.z for v in hv)
    cx = sum(v.x for v in hv) / len(hv); cy = sum(v.y for v in hv) / len(hv)
    extra_chains.append(("holster_00", "pelvis", [Vector((cx, cy, top)), Vector((cx, cy, bot))]))
    # aiguillette cords: light cord loops hanging under the shoulder
    ev = [v.co for v in meshes["Epaulettes_Aiguillette_Or"].data.vertices if v.co.z < 1.40 and v.co.y > 0]
    if ev:
        cx = sum(v.x for v in ev) / len(ev); cy = max(v.y for v in ev)
        ztop = max(v.z for v in ev); zbot = min(v.z for v in ev)
        extra_chains.append(("aiguillette_00", "chest", [Vector((cx, cy, ztop)), Vector((cx, cy, (ztop + zbot) / 2)),
                                                          Vector((cx, cy, zbot))]))
    # jodhpur flare on the outer thighs (classic cloth)
    for side, sx in (("L", 1), ("R", -1)):
        extra_chains.append((f"trouser_{side}_00", f"thigh.{side}",
                             [Vector((sx * 0.17, 0, 0.86)), Vector((sx * 0.20, 0, 0.72)), Vector((sx * 0.18, 0, 0.58))]))

arm_data = bpy.data.armatures.new("Squelette_Tissu")
arm = bpy.data.objects.new("Squelette_Tissu", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones
for n, (p, h, t) in BODY.items():
    b = eb.new(n); b.head = h; b.tail = t
for n, (p, h, t) in BODY.items():
    if p:
        eb[n].parent = eb[p]
for prefix, _a, joints in chains:
    parent = eb["pelvis"]
    for k in range(len(joints) - 1):
        b = eb.new(f"{prefix}_{k}"); b.head = joints[k]; b.tail = joints[k + 1]; b.parent = parent
        parent = b
for prefix, par, joints in extra_chains:
    parent = eb[par]
    for k in range(len(joints) - 1):
        b = eb.new(f"{prefix}_{k}"); b.head = joints[k]; b.tail = joints[k + 1]; b.parent = parent
        parent = b
bpy.ops.object.mode_set(mode="OBJECT")
bones = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in arm_data.bones}

# --------------------------------------------------------------------------- skinning
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length

def radius(n):
    return BONE_RADIUS.get(n.split(".")[0], 0.05)

def body_weights(p, cands):
    ws = {}
    for n in cands:
        d = max(seg_dist(p, *bones[n]) - radius(n) * 0.6, 0.004)
        ws[n] = 1.0 / d ** 4
    return ws

order = list(range(len(chains)))
order.sort(key=lambda i: chains[i][1] % 360)
broken = {frozenset(b) for b in coat["breaks"]}

def neighbours_ok(i, j):
    return frozenset((chains[i][1], chains[j][1])) not in broken

def coat_weights(p):
    a = ang(p)
    # bracket the vertex angle between two consecutive chains
    best = None
    seq = order + ([order[0]] if coat["loop"] else [])
    for i, j in zip(seq, seq[1:]):
        ai, aj = chains[i][1], chains[j][1]
        span = (aj - ai) % 360
        off = (a - ai) % 360
        if span > 0 and off <= span:
            best = (i, j, off / span)
            break
    if best is None or not neighbours_ok(best[0], best[1]):
        near = min(range(len(chains)), key=lambda i: abs(adiff(a, chains[i][1])))
        mix = [(near, 1.0)]
    else:
        i, j, t = best
        t = t * t * (3 - 2 * t)
        mix = [(i, 1 - t), (j, t)]
    s = (coat["top"] - p.z) / (coat["top"] - coat["hem"]) * coat["segs"]  # 0 at waist, segs at hem
    ws = defaultdict(float)
    w_pelvis = max(0.0, min(1.0, 1 - s / 0.35)) ** 2
    for ci, wa in mix:
        along = {}
        for k in range(coat["segs"]):
            along[k] = max(0.0, 1 - abs(min(max(s, 0.0), coat["segs"] - 0.5) - (k + 0.5)))
        tot = sum(along.values()) or 1
        for k, w in along.items():
            if w > 0:
                ws[f"{chains[ci][0]}_{k}"] += wa * w / tot * (1 - w_pelvis)
    ws["pelvis"] += w_pelvis
    return ws

def chain_weights(prefix, parent, joints, p, falloff):
    s_total = len(joints) - 1
    # projection on the polyline
    best = (1e9, 0)
    for k in range(s_total):
        a, b = joints[k], joints[k + 1]
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        d = (p - (a + ab * t)).length
        if d < best[0]:
            best = (d, k + t)
    s = best[1]
    ws = defaultdict(float)
    w_root = max(0.0, 1 - s / falloff) if falloff > 0 else 0.0
    for k in range(s_total):
        ws[f"{prefix}_{k}"] += max(0.0, 1 - abs(min(s, s_total - 0.5) - (k + 0.5))) * (1 - w_root)
    ws[parent] += w_root
    return ws

def body_for(name):
    """candidate bones from the mesh name (generated outfits)"""
    low = name.lower()
    if any(k in low for k in ("botte", "semelle", "chaussure")):
        return FEET
    if any(k in low for k in ("gant", "bandes_avant")):
        return HANDS
    if any(k in low for k in ("pantalon", "combinaison")):
        return ["pelvis"] + LEGS
    if any(k in low for k in ("ceinture", "boucle", "holster")):
        return ["pelvis"]
    if any(k in low for k in ("col_", "bandana")):
        return ["neck", "chest"]
    if "epaulette" in low:
        return ["chest", "shoulder.L", "shoulder.R"]
    if "manche" in low:
        return ["chest"] + ARMS
    if "bustier" in low or "maillot" in low or "bouton" in low:
        return TORSO
    # torso garments never take arm weights: a swinging arm would drag the chest
    return TORSO + ["shoulder.L", "shoulder.R"]


def islands(me):
    adj = defaultdict(set)
    for e in me.edges:
        a, b = e.vertices
        adj[a].add(b); adj[b].add(a)
    seen, out = set(), []
    for v in range(len(me.vertices)):
        if v in seen:
            continue
        st, isl = [v], []
        seen.add(v)
        while st:
            x = st.pop(); isl.append(x)
            for y in adj[x]:
                if y not in seen:
                    seen.add(y); st.append(y)
        out.append(isl)
    return out, adj

def smooth_weights(W, adj, iters, frozen=()):
    for _ in range(iters):
        new = []
        for i, w in enumerate(W):
            if i in frozen or not adj[i]:
                new.append(w); continue
            acc = defaultdict(float)
            for n, x in w.items():
                acc[n] += x * 0.5
            share = 0.5 / len(adj[i])
            for j in adj[i]:
                for n, x in W[j].items():
                    acc[n] += x * share
            new.append(acc)
        W = new
    return W

def finalize(o, W):
    for i, w in enumerate(W):
        top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
        tot = sum(x for _, x in top)
        for n, x in top:
            if x / tot < 0.01:
                continue
            vg = o.vertex_groups.get(n) or o.vertex_groups.new(name=n)
            vg.add([i], x / tot, "REPLACE")

def norm(ws):
    tot = sum(ws.values()) or 1
    return {n: x / tot for n, x in ws.items()}

for name, o in meshes.items():
    me = o.data
    isl, adj = islands(me)
    W = [None] * len(me.vertices)
    for i, v in enumerate(me.vertices):
        p = v.co
        gen = [ch for ch in CFG.get("chains", []) if name in ch["meshes"]]
        if gen:
            # nearest chain of this mesh; the part around the attachment stays on the parent bone
            def dist(ch):
                return min(seg_dist(p, a, b) for a, b in zip(ch["joints"], ch["joints"][1:]))
            ch = min(gen, key=dist)
            W[i] = norm(chain_weights(ch["prefix"], ch["parent"], ch["joints"], p, ch["falloff"]))
        elif name in coat["meshes"] and p.z < coat["top"] + 0.03 and abs(p.x) <= coat.get("exclude_x", 9.0):
            cw = coat_weights(p)
            if p.z > coat["top"] - 0.02 and name in CFG["body"]:
                # blend into the torso just above the waist
                t = max(0.0, min(1.0, (p.z - (coat["top"] - 0.02)) / 0.05))
                bw = norm(body_weights(p, CFG["body"][name]))
                cw = {k: cw.get(k, 0) * (1 - t) + bw.get(k, 0) * t for k in set(cw) | set(bw)}
            W[i] = norm(cw)
        elif name == "Holster_Pistolet_Cuir":
            W[i] = norm(chain_weights("holster_00", "pelvis", extra_chains[0][2], p, 0.25))
        elif name == "Epaulettes_Aiguillette_Or" and p.z < 1.40 and p.y > 0:
            ch = [c for c in extra_chains if c[0] == "aiguillette_00"][0]
            cw = chain_weights(*ch, p, 0.0)
            # cord ends stay sewn on the jacket, the sag swings
            ends = min((p - ch[2][0]).length, abs(p.x) * 2.5)
            free = max(0.0, min(1.0, (ends - 0.02) / 0.06))
            bw = norm(body_weights(p, ["chest"]))
            W[i] = {k: cw.get(k, 0) * free + bw.get(k, 0) * (1 - free) for k in set(cw) | set(bw)}
        elif name == "Pantalon_Bouffant_Bleu":
            bw = norm(body_weights(p, CFG["body"][name]))
            side = "L" if p.x > 0 else "R"
            if 0.52 < p.z < 0.92:
                r = abs(p.x) - 0.095
                flare = max(0.0, min(1.0, (r - 0.05) / 0.06)) * 0.6
                ch = [c for c in extra_chains if c[0] == f"trouser_{side}_00"][0]
                cw = norm(chain_weights(*ch, p, 0.0))
                bw = {k: bw.get(k, 0) * (1 - flare) + cw.get(k, 0) * flare for k in set(cw) | set(bw)}
            W[i] = bw
        else:
            W[i] = norm(body_weights(p, CFG["body"].get(name) or body_for(name)))
    rigid = name in CFG["rigid"] or name == "Holster_Pistolet_Cuir"
    if name in CFG["rigid"]:
        for il in isl:  # buttons / buckles never bend
            acc = defaultdict(float)
            for i in il:
                for n, x in W[i].items():
                    acc[n] += x / len(il)
            for i in il:
                W[i] = dict(acc)
    elif not rigid:
        W = smooth_weights(W, adj, 3)
    finalize(o, W)
    o.parent = arm
    m = o.modifiers.new("Armature", "ARMATURE"); m.object = arm

# --------------------------------------------------------------------------- export
bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_skins=True, export_animations=False,
                          export_yup=True, export_apply=False, export_def_bones=False)
print("CHAINS", [(c[0], c[1]) for c in chains], [c[0] for c in extra_chains])
print("BUILT", DST)
