"""Procedural FMA-style outfits (clothes only, no body), unrigged.

usage: python3 generate_fma_outfits.py <riza|olivier|scar|winry> <out.glb>
Then rig with: python3 build_outfit.py <name> <out.glb> <rigged.glb>

Proportions match the "mustang" skeleton of build_outfit.py.
Blender axes: +Y = front, +Z = up, +X = side of the ".L" bones.
"""
import bpy, bmesh, sys, math
from mathutils import Vector, noise

NAME, DST = sys.argv[1], sys.argv[2]
TAU = math.tau


# --------------------------------------------------------------------------- helpers
def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


_mats = {}


def mat(name, color, rough=0.8, metal=0.0, spec=0.3, coat=0.0):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*(srgb(color) if isinstance(color, str) else color), 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Specular IOR Level"].default_value = spec
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.15
    _mats[name] = m
    return m


def interp(profile, z):
    """profile: [(z, a, b, ...)] sorted by z descending. Smooth (cosine) interpolation."""
    if z >= profile[0][0]:
        return profile[0][1:]
    if z <= profile[-1][0]:
        return profile[-1][1:]
    for p, q in zip(profile, profile[1:]):
        if q[0] <= z <= p[0]:
            t = (p[0] - z) / (p[0] - q[0])
            t = 0.5 - 0.5 * math.cos(t * math.pi)
            return tuple(a + (b - a) * t for a, b in zip(p[1:], q[1:]))


def zrange(top, bottom, step=0.02):
    n = max(2, int(round((top - bottom) / step)))
    return [top - (top - bottom) * i / n for i in range(n + 1)]


def sup(t, p=2.4):
    """superellipse sin/cos: slightly square torso sections"""
    s, c = math.sin(t), math.cos(t)
    return math.copysign(abs(s) ** (2 / p), s), math.copysign(abs(c) ** (2 / p), c)


def loft(rows, closed, cuts=()):
    """rows: list of rows of Vectors (same length). cuts: [(column, split(row_index) -> bool)]
    splits the grid along a column (slits, vents)."""
    verts, idx = [], []
    for row in rows:
        idx.append(list(range(len(verts), len(verts) + len(row))))
        verts.extend(row)
    m = len(rows[0])
    dup = {}

    def dv(i, j):
        if (i, j) not in dup:
            dup[(i, j)] = len(verts)
            verts.append(rows[i][j].copy())
        return dup[(i, j)]

    cutmap = dict(cuts)
    faces = []
    for i in range(len(rows) - 1):
        for j in range(m if closed else m - 1):
            j2 = (j + 1) % m
            a, b, c, d = idx[i][j], idx[i][j2], idx[i + 1][j2], idx[i + 1][j]
            if j in cutmap:
                if cutmap[j](i):
                    a = dv(i, j)
                if cutmap[j](i + 1):
                    d = dv(i + 1, j)
            faces.append((a, b, c, d))
    return verts, faces


def build(name, parts, material, thickness=0.0, subdiv=1, smooth_iter=0):
    """parts: list of (verts, faces). Creates one object."""
    verts, faces = [], []
    for v, f in parts:
        o = len(verts)
        verts += v
        faces += [tuple(i + o for i in fc) for fc in f]
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(material)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    mods = []
    if smooth_iter:
        m = ob.modifiers.new("s", "LAPLACIANSMOOTH"); m.iterations = smooth_iter; m.lambda_factor = 0.4
        m.lambda_border = 0.0; m.use_volume_preserve = True; mods.append(m)
    if thickness:
        m = ob.modifiers.new("t", "SOLIDIFY"); m.thickness = thickness; m.offset = 0.0
        m.use_quality_normals = True; mods.append(m)
    if subdiv:
        m = ob.modifiers.new("d", "SUBSURF"); m.levels = subdiv; m.boundary_smooth = "PRESERVE_CORNERS"; mods.append(m)
    for m in mods:
        with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
            bpy.ops.object.modifier_apply(modifier=m.name)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


# --------------------------------------------------------------------------- primitives
def body_rows(profile, top, bottom, n=40, gap=None, step=0.02, folds=None, square=2.4):
    """Horizontal sections. profile: (z, rx, ry, cy). gap(z) -> half opening angle at the
    front (open garments). folds(z, t) -> radial multiplier (fabric folds)."""
    rows = []
    for z in zrange(top, bottom, step):
        rx, ry, cy = interp(profile, z)
        g = gap(z) if gap else 0.0
        ts = ([g + (TAU - 2 * g) * k / n for k in range(n + 1)] if gap else [TAU * k / n for k in range(n)])
        row = []
        for t in ts:
            s, c = sup(t, square)
            f = folds(z, t) if folds else 1.0
            row.append(Vector((rx * s * f, cy + ry * c * f, z)))
        rows.append(row)
    return rows


def tube(path, radii, n=20, samples=24, closed_tip=False, front=Vector((0, 1, 0)), folds=None):
    """Tube along a polyline. radii: [(rx, ry)] per path point (rx across, ry front/back)."""
    lens = [0.0]
    for a, b in zip(path, path[1:]):
        lens.append(lens[-1] + (b - a).length)
    L = lens[-1]
    rows = []
    for k in range(samples + 1):
        s = L * k / samples
        i = max(0, min(len(path) - 2, next((j for j in range(len(lens) - 1) if lens[j + 1] >= s), len(path) - 2)))
        t = (s - lens[i]) / max(lens[i + 1] - lens[i], 1e-6)
        c = path[i].lerp(path[i + 1], t)
        rx = radii[i][0] + (radii[i + 1][0] - radii[i][0]) * t
        ry = radii[i][1] + (radii[i + 1][1] - radii[i][1]) * t
        # smooth tangent
        ta = (path[i + 1] - path[i]).normalized()
        if t > 0.5 and i + 2 < len(path):
            tb = (path[i + 2] - path[i + 1]).normalized()
            ta = ta.lerp(tb, (t - 0.5)).normalized()
        elif t < 0.5 and i > 0:
            tb = (path[i] - path[i - 1]).normalized()
            ta = tb.lerp(ta, t + 0.5).normalized()
        v = (front - ta * front.dot(ta)).normalized()
        u = v.cross(ta)
        if closed_tip and k == samples:
            rx, ry = rx * 0.15, ry * 0.15
        row = []
        for j in range(n):
            a = TAU * j / n
            f = folds(k / samples, a) if folds else 1.0
            row.append(c + u * (rx * math.sin(a) * f) + v * (ry * math.cos(a) * f))
        rows.append(row)
    return loft(rows, True)


def band(profile, z, height, n=48, out=0.004):
    """Belt / collar band around a body profile."""
    rows = []
    for zz in (z + height / 2, z - height / 2):
        rx, ry, cy = interp(profile, z)
        rows.append([Vector(((rx + out) * sup(TAU * k / n)[0], cy + (ry + out) * sup(TAU * k / n)[1], zz))
                     for k in range(n)])
    return loft(rows, True)


def surface(profile, z, t, out=0.0):
    rx, ry, cy = interp(profile, z)
    s, c = sup(t)
    return Vector(((rx + out) * s, cy + (ry + out) * c, z))


def blob(center, size, n=10, m=8):
    """ellipsoid (buttons, knots, buckles)"""
    rows = []
    for i in range(1, m):
        ph = math.pi * i / m
        rows.append([center + Vector((size[0] * math.sin(ph) * math.cos(TAU * k / n),
                                      size[1] * math.sin(ph) * math.sin(TAU * k / n),
                                      size[2] * math.cos(ph))) for k in range(n)])
    v, f = loft(rows, True)
    top = len(v); v.append(center + Vector((0, 0, size[2])))
    bot = len(v); v.append(center - Vector((0, 0, size[2])))
    f += [(top, (k + 1) % n, k) for k in range(n)]
    o = (m - 2) * n
    f += [(bot, o + k, o + (k + 1) % n) for k in range(n)]
    return v, f


def box(center, size):
    x, y, z = (s / 2 for s in size)
    c = center
    v = [c + Vector((sx * x, sy * y, sz * z)) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return v, f


def ribbon(path, width, normal=Vector((0, 1, 0))):
    rows = []
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        side = t.cross(normal).normalized() * (width / 2)
        rows.append([p - side, p + side])
    return loft(rows, False)


# --------------------------------------------------------------------------- body-fitted pieces
SHOULDER = {"L": [Vector((0.12, -0.004, 1.435)), Vector((0.18, -0.008, 1.40)), Vector((0.233, -0.02, 1.18)),
                  Vector((0.275, -0.005, 0.965))]}
SHOULDER["R"] = [Vector((-p.x, p.y, p.z)) for p in SHOULDER["L"]]
HAND = {"L": [Vector((0.274, -0.005, 0.975)), Vector((0.284, -0.005, 0.86)), Vector((0.292, -0.005, 0.75))]}
HAND["R"] = [Vector((-p.x, p.y, p.z)) for p in HAND["L"]]


def sleeves(radii=((0.07, 0.07), (0.068, 0.066), (0.056, 0.054), (0.05, 0.048)), folds=True):
    def f(s, a):  # soft wrinkles at the elbow and the wrist
        return 1 + 0.035 * math.sin(a * 3 + s * 30) * math.exp(-((s - 0.55) / 0.12) ** 2) \
            + 0.03 * math.sin(a * 4 + s * 50) * max(0, s - 0.8) * 4
    return [tube(SHOULDER[s], list(radii), folds=f if folds else None) for s in "LR"]


def cuffs(r=0.054, h=0.035):
    out = []
    for s in "LR":
        a, b = SHOULDER[s][-2], SHOULDER[s][-1]
        d = (b - a).normalized()
        out.append(tube([b - d * h, b + d * 0.004], [(r, r), (r, r)], samples=2))
    return out


def gloves(r=(0.042, 0.026)):
    return [tube(HAND[s], [r, (r[0] * 1.05, r[1] * 1.05), (r[0] * 0.75, r[1] * 0.85)], samples=12,
                 closed_tip=True) for s in "LR"]


def trousers(hip=0.175, thigh=0.095, knee=0.07, ankle=0.062, baggy=0.0, bottom=0.12):
    hips = [(1.02, 0.16, 0.115, 0.0), (0.95, hip, 0.12, 0.0), (0.86, hip + 0.01, 0.12, 0.0)]
    parts = [loft(body_rows(hips, 1.02, 0.86, n=40), True)]
    for sx in (1, -1):
        path = [Vector((sx * 0.095, 0.0, 0.95)), Vector((sx * 0.097, 0.0, 0.72)), Vector((sx * 0.095, 0.01, 0.5)),
                Vector((sx * 0.095, 0.0, bottom))]
        radii = [(thigh + 0.01, thigh), (thigh + baggy * 1.2, thigh + baggy * 0.8), (knee + baggy, knee + baggy * 0.6),
                 (ankle, ankle)]

        def f(s, a, b=baggy):  # bunching above the boots, folds on the thighs for baggy trousers
            return 1 + 0.03 * math.sin(s * 70 + a * 2) * max(0, s - 0.75) * 4 \
                + b * 0.6 * math.sin(a * 5 + s * 9) * math.sin(s * math.pi)
        parts.append(tube(path, radii, n=24, samples=30, folds=f))
    return parts


def boots(top=0.42, r=0.068, toe=0.2, color_cuff=None):
    parts, soles = [], []
    for sx in (1, -1):
        x = sx * 0.095
        parts.append(tube([Vector((x, 0, top)), Vector((x, 0.005, 0.2)), Vector((x, 0.01, 0.026))],
                          [(r, r), (r * 0.9, r * 0.92), (r * 0.8, r * 0.9)], samples=16))
        # foot: sections in the XZ plane along +Y
        # the shaft goes down to the sole and forms the heel; the foot starts inside it
        prof = [(-0.01, 0.045, 0.05, 0.075), (0.02, 0.05, 0.06, 0.07), (0.06, 0.05, 0.055, 0.06),
                (0.14, 0.052, 0.045, 0.045), (toe - 0.01, 0.038, 0.03, 0.035), (toe, 0.012, 0.012, 0.03)]
        rows = []
        for y, rx, hz, zc in prof:
            rows.append([Vector((x + rx * math.sin(TAU * k / 20), y, max(0.022, zc + hz * math.cos(TAU * k / 20))))
                         for k in range(20)])
        v, f = loft(rows, True)
        for ring, flip in ((0, True), (len(rows) - 1, False)):  # close heel and toe
            c = len(v)
            v.append(sum(rows[ring], Vector()) / len(rows[ring]))
            o = ring * 20
            f += [((c, o + (k + 1) % 20, o + k) if flip else (c, o + k, o + (k + 1) % 20)) for k in range(20)]
        parts.append((v, f))
        soles.append(box(Vector((x, (toe - 0.08) / 2, 0.011)), (0.105, toe + 0.09, 0.022)))
    return parts, soles


def collar(z0=1.465, z1=1.535, r0=(0.078, 0.074), r1=(0.07, 0.068), cy=-0.005, gap=0.25):
    rows = []
    for z, (rx, ry) in ((z1, r1), (z0, r0)):
        rows.append([Vector((rx * math.sin(t), cy + ry * math.cos(t), z))
                     for t in [gap + (TAU - 2 * gap) * k / 30 for k in range(31)]])
    return loft(rows, False)


# --------------------------------------------------------------------------- outfits
JACKET = [(1.54, 0.074, 0.07, -0.005), (1.47, 0.085, 0.08, -0.005), (1.43, 0.17, 0.11, -0.005),
          (1.40, 0.2, 0.12, -0.005), (1.30, 0.178, 0.125, 0.0), (1.16, 0.158, 0.112, 0.0),
          (1.02, 0.165, 0.118, 0.0), (0.96, 0.172, 0.122, 0.0)]


def riza():
    blue = mat("Laine_Bleu_Amestris_Riza", (0.020, 0.040, 0.150), rough=0.84, spec=0.25)
    black = mat("Col_Roule_Jersey_Noir", "#16161a", rough=0.85, spec=0.2)
    leather = mat("Cuir_Bottes_Noir", "#0b0b0d", rough=0.3, spec=0.5, coat=0.3)
    brown = mat("Cuir_Ceinture_Holster_Brun", "#3a2414", rough=0.5, spec=0.4)
    metal = mat("Metal_Argent_Boucle", "#c8ccd2", rough=0.25, metal=1.0)
    gold = mat("Or_Insignes", "#d4a849", rough=0.3, metal=1.0)

    # jacket: torso + short peplum below the belt
    prof = JACKET + [(0.92, 0.185, 0.13, 0.0), (0.84, 0.198, 0.142, -0.004)]
    folds = lambda z, t: 1 + (0.025 * math.sin(t * 9) if z < 0.95 else 0.0) * min(1, (0.95 - z) / 0.08 + 0.2)
    torso = loft(body_rows(prof, 1.47, 0.84, folds=folds), True)
    build("Veste_Riza", [torso], blue, thickness=0.004)
    build("Manches_Riza", sleeves() + cuffs(), blue, thickness=0.004)
    build("Col_Roule_Riza", [collar(1.455, 1.56, (0.075, 0.072), (0.068, 0.066), gap=0.0001)], black, thickness=0.003)
    build("Pantalon_Riza", trousers(hip=0.17, thigh=0.088, knee=0.068, ankle=0.058, bottom=0.34), blue,
          thickness=0.003)  # tucked into the boots
    bt, soles = boots(top=0.4, r=0.072)
    build("Bottes_Riza", bt, leather)
    build("Semelles_Riza", soles, leather, subdiv=0)
    build("Ceinture_Riza", [band(prof, 0.975, 0.04, out=0.008)], brown, thickness=0.004)
    build("Boucle_Riza", [box(surface(prof, 0.975, 0.0, 0.014), (0.05, 0.012, 0.045))], metal, subdiv=0)
    # holster on the back right hip
    hp = surface(prof, 0.9, math.radians(-150), 0.03)
    build("Holster_Riza", [box(hp, (0.055, 0.04, 0.17)), box(hp + Vector((0, 0.0, 0.1)), (0.04, 0.03, 0.06))],
          brown, subdiv=1)
    build("Boutons_Riza", [blob(surface(prof, z, 0.0, 0.006), (0.009, 0.004, 0.009))
                           for z in (1.38, 1.28, 1.18, 1.08)], gold, subdiv=0)
    for sx in (1, -1):  # shoulder boards
        build("Epaulette_" + ("L" if sx > 0 else "R"),
              [box(Vector((sx * 0.13, -0.005, 1.442)), (0.11, 0.06, 0.012))], blue, subdiv=1)


def olivier():
    navy = mat("Laine_Capote_Bleu_Briggs", "#141c33", rough=0.88, spec=0.2)
    fur = mat("Fourrure_Col_Creme", "#d9cdb4", rough=1.0, spec=0.15)
    leather = mat("Cuir_Bottes_Noir", "#0a0a0c", rough=0.28, spec=0.5, coat=0.4)
    glove = mat("Gants_Cuir_Noir", "#101012", rough=0.45, spec=0.4)
    brown = mat("Cuir_Ceinture_Brun", "#2c1a10", rough=0.5)
    gold = mat("Or_Epaulettes", "#d6ad52", rough=0.3, metal=1.0)
    steel = mat("Metal_Fourreau_Acier", "#3a3d44", rough=0.35, metal=1.0)

    top = [(1.54, 0.08, 0.075, -0.005), (1.47, 0.09, 0.085, -0.005), (1.43, 0.18, 0.115, -0.005),
           (1.40, 0.21, 0.125, -0.005), (1.30, 0.19, 0.13, 0.0), (1.16, 0.168, 0.12, 0.0),
           (1.02, 0.172, 0.125, 0.0)]
    build("Capote_Torse_Olivier", [loft(body_rows(top, 1.47, 0.98), True)], navy, thickness=0.005)
    build("Manches_Olivier", sleeves(((0.078, 0.078), (0.074, 0.072), (0.06, 0.058), (0.058, 0.056))), navy,
          thickness=0.005)
    # long skirt: open at the front below the belt, back vent below 0.7 m, vertical folds
    skirt = [(1.0, 0.18, 0.13, 0.0), (0.8, 0.22, 0.17, -0.01), (0.5, 0.29, 0.24, -0.02), (0.2, 0.35, 0.3, -0.03)]
    n = 48
    gap = lambda z: 0.06 + 0.12 * max(0.0, (0.95 - z) / 0.75)
    fold = lambda z, t: 1 + 0.045 * math.sin(t * 11 + 0.7) * min(1.0, (1.0 - z) / 0.5) ** 1.5
    rows = body_rows(skirt, 1.0, 0.2, n=n, gap=gap, folds=fold, square=2.0)
    back = n // 2
    split = lambda i, rows=rows: rows[i][0].z < 0.7
    build("Capote_Pans_Olivier", [loft(rows, False, cuts=[(back, split)])], navy, thickness=0.005)
    # fur collar: fluffy torus around the neck, bigger at the back
    rows = []
    for k in range(48):
        ph = TAU * k / 48
        c = Vector((0.14 * math.sin(ph), -0.01 + 0.115 * math.cos(ph), 1.47))
        radial = Vector((math.sin(ph), math.cos(ph), 0))
        r0 = 0.05 + 0.025 * (0.5 - 0.5 * math.cos(ph))  # back (ph = pi) is fuller
        row = []
        for j in range(16):
            ps = TAU * j / 16
            p = c + radial * (r0 * math.cos(ps)) + Vector((0, 0, 1)) * (r0 * 0.85 * math.sin(ps))
            r = 1 + 0.18 * noise.noise(p * 40) + 0.08 * noise.noise(p * 120)
            row.append(c + (p - c) * r)
        rows.append(row)
    build("Col_Fourrure_Olivier", [loft([rows[i] for i in range(48)] + [rows[0]], True)], fur, subdiv=1)
    build("Gants_Olivier", gloves((0.044, 0.028)), glove)
    build("Pantalon_Olivier", trousers(hip=0.17, thigh=0.09, knee=0.068, ankle=0.058, bottom=0.42), navy,
          thickness=0.003)
    bt, soles = boots(top=0.48, r=0.074)
    build("Bottes_Olivier", bt, leather)
    build("Semelles_Olivier", soles, leather, subdiv=0)
    build("Ceinture_Olivier", [band(top + [(0.96, 0.18, 0.13, 0.0)], 0.985, 0.05, out=0.012)], brown, thickness=0.004)
    for sx in (1, -1):
        build("Epaulette_Or_" + ("L" if sx > 0 else "R"),
              [box(Vector((sx * 0.14, -0.005, 1.448)), (0.12, 0.07, 0.014))]
              + [ribbon([Vector((sx * (0.19 + 0.008 * i), 0.03 - 0.012 * i, 1.445)),
                         Vector((sx * (0.2 + 0.008 * i), 0.03 - 0.012 * i, 1.40))], 0.008) for i in range(6)],
              gold, subdiv=0)
    build("Boutons_Olivier", [blob(surface(top, z, sx * 0.35, 0.007), (0.01, 0.005, 0.01))
                              for z in (1.36, 1.24, 1.12) for sx in (1, -1)], gold, subdiv=0)
    # sabre on the left hip: scabbard hangs backwards, hilt in front of the belt
    a, b = Vector((0.2, 0.06, 0.93)), Vector((0.27, -0.32, 0.25))
    build("Fourreau_Sabre_Olivier", [tube([a, a.lerp(b, 0.5), b], [(0.016, 0.024), (0.015, 0.022), (0.012, 0.018)],
                                          n=12, samples=16, closed_tip=True)], steel, subdiv=0)
    hilt = a + (a - b).normalized() * 0.13
    build("Garde_Sabre_Olivier", [tube([a, hilt], [(0.011, 0.011), (0.01, 0.01)], n=10, samples=4),
                                  blob(a, (0.03, 0.02, 0.008))], gold, subdiv=0)


def scar():
    jacket = mat("Toile_Veste_Jaune_Scar", "#d8a848", rough=0.78, spec=0.3)
    black = mat("Jersey_Maillot_Noir", "#141416", rough=0.85, spec=0.2)
    pants = mat("Toile_Pantalon_Gris", "#2e2f33", rough=0.85, spec=0.25)
    boots_m = mat("Cuir_Bottes_Brun", "#2a1b12", rough=0.45, spec=0.4)
    sash = mat("Tissu_Echarpe_Rouge", "#7a1414", rough=0.75, spec=0.3)
    wrap = mat("Coton_Bandes_Blanc", "#d8d2c4", rough=0.85, spec=0.2)

    # fitted black undershirt
    under = [(1.54, 0.07, 0.066, -0.005), (1.47, 0.08, 0.077, -0.005), (1.43, 0.165, 0.105, -0.005),
             (1.40, 0.19, 0.115, -0.005), (1.30, 0.17, 0.118, 0.0), (1.16, 0.15, 0.105, 0.0),
             (1.0, 0.158, 0.11, 0.0), (0.95, 0.165, 0.115, 0.0)]
    build("Maillot_Scar", [loft(body_rows(under, 1.5, 0.95), True)], black, thickness=0.003)
    # open jacket: wide at the bottom, high collar, short sleeves rolled to the elbow
    prof = [(1.55, 0.085, 0.08, -0.008), (1.47, 0.095, 0.09, -0.008), (1.43, 0.185, 0.12, -0.005),
            (1.40, 0.212, 0.13, -0.005), (1.30, 0.19, 0.135, 0.0), (1.16, 0.172, 0.126, 0.0),
            (1.0, 0.185, 0.135, 0.0), (0.8, 0.205, 0.15, -0.005)]
    gap = lambda z: 0.12 + 0.35 * max(0.0, min(1.0, (1.42 - z) / 0.5))
    fold = lambda z, t: 1 + 0.03 * math.sin(t * 7 + z * 20) * max(0.0, (1.0 - z) / 0.2)
    build("Veste_Ouverte_Scar", [loft(body_rows(prof, 1.55, 0.8, gap=gap, folds=fold), False)], jacket,
          thickness=0.004)
    build("Manches_Veste_Scar", [tube(SHOULDER[s][:3], [(0.075, 0.074), (0.072, 0.07), (0.064, 0.062)])
                                 for s in "LR"], jacket, thickness=0.004)
    for s in "LR":  # bandaged forearms
        a, b = SHOULDER[s][2], SHOULDER[s][3]
        build("Bandes_Avant_Bras_" + s, [tube([a.lerp(b, 0.15), b], [(0.046, 0.044), (0.04, 0.038)], samples=16,
                                              folds=lambda u, t: 1 + 0.06 * abs(math.sin(u * 40 + t)))], wrap,
              subdiv=0)
    build("Pantalon_Scar", trousers(hip=0.178, thigh=0.1, knee=0.08, ankle=0.06, baggy=0.035, bottom=0.2), pants,
          thickness=0.003)
    bt, soles = boots(top=0.3, r=0.066)
    build("Bottes_Scar", bt, boots_m)
    build("Semelles_Scar", soles, boots_m, subdiv=0)
    # sash: knot on the left hip, two tails hanging
    knot = Vector((0.15, 0.08, 0.97))
    band_prof = under
    build("Echarpe_Taille_Scar", [band(band_prof, 0.975, 0.06, out=0.02), blob(knot, (0.035, 0.03, 0.04))]
          + [ribbon([knot + Vector((dx, 0.0, 0)), knot + Vector((dx * 1.5 + 0.02, 0.015, -0.2)),
                     knot + Vector((dx * 2 + 0.035, 0.02, -0.42 + dx * 2))], 0.07, Vector((0.6, 0.8, 0)))
             for dx in (-0.015, 0.02)], sash, thickness=0.004, subdiv=1)


def winry():
    top_m = mat("Jersey_Bustier_Noir", "#121214", rough=0.6, spec=0.35)
    suit = mat("Toile_Combinaison_Beige", "#d9c9a0", rough=0.82, spec=0.25)
    shoes = mat("Cuir_Chaussures_Noir", "#1a1414", rough=0.45, spec=0.4)
    bandana = mat("Coton_Bandana_Blanc", "#e8e4dc", rough=0.8, spec=0.25)

    tube_top = [(1.38, 0.17, 0.125, 0.008), (1.3, 0.165, 0.128, 0.01), (1.2, 0.148, 0.108, 0.0)]
    build("Bustier_Winry", [loft(body_rows(tube_top, 1.37, 1.2), True)], top_m, thickness=0.003)
    build("Combinaison_Pantalon_Winry", trousers(hip=0.172, thigh=0.098, knee=0.08, ankle=0.072, baggy=0.015,
                                                bottom=0.13), suit, thickness=0.003)
    # the upper half of the jumpsuit, folded down at the back
    drape = [(1.0, 0.18, 0.13, 0.0), (0.85, 0.2, 0.15, -0.01), (0.7, 0.2, 0.155, -0.02)]
    fold = lambda z, t: 1 + 0.04 * math.sin(t * 8) * (1.0 - z) / 0.3
    rows = body_rows(drape, 1.0, 0.7, n=30, gap=lambda z: math.radians(105), folds=fold, square=2.0)
    build("Haut_Replie_Winry", [loft(rows, False)], suit, thickness=0.004)
    # sleeves wrapped around the waist, knotted at the front, hanging
    knot = Vector((0.0, 0.145, 0.955))
    wrap = band([(1.0, 0.175, 0.125, 0.0)], 0.975, 0.07, out=0.015)
    tails = [tube([knot + Vector((sx * 0.02, 0.0, -0.01)), knot + Vector((sx * 0.06, 0.02, -0.18)),
                   knot + Vector((sx * 0.07, 0.015, -0.36))], [(0.04, 0.03), (0.045, 0.032), (0.048, 0.034)],
                  n=14, samples=14) for sx in (1, -1)]
    build("Manches_Nouees_Winry", [wrap, blob(knot, (0.05, 0.035, 0.035))] + tails, suit, thickness=0.003)
    bt, soles = boots(top=0.2, r=0.07, toe=0.19)
    build("Chaussures_Winry", bt, shoes)
    build("Semelles_Winry", soles, shoes, subdiv=0)
    # bandana on the head: cap + knot + two tails at the back
    rows = []
    hc = Vector((0.0, 0.0, 1.615))
    for i in range(1, 9):
        ph = math.radians(8 + i * 11)  # from the top down to the hairline
        rows.append([hc + Vector((0.118 * math.sin(ph) * math.sin(t), 0.124 * math.sin(ph) * math.cos(t),
                                  0.125 * math.cos(ph) - (0.02 if math.cos(t) > 0 else 0.0) * (i / 8)))
                     for t in [TAU * k / 32 for k in range(32)]])
    cap = loft(rows, True)
    bk = hc + Vector((0, -0.12, -0.02))
    btails = [ribbon([bk, bk + Vector((sx * 0.03, -0.03, -0.08)), bk + Vector((sx * 0.05, -0.04, -0.17))], 0.045,
                     Vector((0, -1, 0))) for sx in (1, -1)]
    build("Bandana_Winry", [cap, blob(bk, (0.025, 0.02, 0.02))] + btails, bandana, thickness=0.003)


bpy.ops.wm.read_factory_settings(use_empty=True)
{"riza": riza, "olivier": olivier, "scar": scar, "winry": winry}[NAME]()
bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_animations=False, export_yup=True)
print("GENERATED", NAME, len([o for o in bpy.data.objects if o.type == "MESH"]), "meshes")
