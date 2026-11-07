"""Convertit un modèle voxel animé (.glb, membres rigides, sans squelette) en
données Luau rejouées par le jeu (src/shared/Rigs/<id>.luau).

Usage : python tools/glb_to_rig.py "Modele 3D/flamichat.glb" flamichat

Pour chaque nœud qui porte un maillage, on retrouve les cubes (voxels) à partir
des faces : chaque face axiale marque la case qu'elle borde, et l'intérieur est
rempli par parité le long de X. Les cases de même couleur sont regroupées en
blocs. Les animations (translation / rotation / échelle par nœud) sont
exportées en images clés.
"""
import json
import math
import os
import struct
import sys

src, cid = sys.argv[1], sys.argv[2]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

data = open(src, "rb").read()
jlen, _ = struct.unpack("<II", data[12:20])
gl = json.loads(data[20:20 + jlen])
blen, _ = struct.unpack("<II", data[20 + jlen:28 + jlen])
binary = data[28 + jlen:28 + jlen + blen]

COMP = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4), 5121: ("B", 1)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor(i):
    a = gl["accessors"][i]
    bv = gl["bufferViews"][a["bufferView"]]
    fmt, size = COMP[a["componentType"]]
    n = NCOMP[a["type"]]
    stride = bv.get("byteStride", size * n)
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    out = []
    for k in range(a["count"]):
        vals = struct.unpack_from("<" + fmt * n, binary, off + k * stride)
        out.append(vals if n > 1 else vals[0])
    return out


def srgb(c):
    return max(0, min(255, round((max(c, 0) ** (1 / 2.2)) * 255)))


# Palette : une entrée par matériau (couleur sRGB, néon si émissif).
palette = []
for m in gl["materials"]:
    base = m.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
    emis = m.get("emissiveFactor")
    neon = bool(emis and max(emis) > 0.01) or "NEON" in m.get("name", "").upper()
    palette.append((srgb(base[0]), srgb(base[1]), srgb(base[2]), neon, round(1 - base[3], 2)))

VOX = 0.1  # 1 voxel = 0,1 m (voir extras du fichier)


def voxelize(mesh_index):
    """Renvoie les blocs { x, y, z, w, h, d, matériau } (en voxels) d'un maillage."""
    cells = {}  # (i, j, k) -> matériau
    for prim in gl["meshes"][mesh_index]["primitives"]:
        mat = prim.get("material", 0)
        pos = accessor(prim["attributes"]["POSITION"])
        idx = accessor(prim["indices"]) if "indices" in prim else list(range(len(pos)))
        crossings = {}  # (j, k) -> [(x, signe)]
        for t in range(0, len(idx), 3):
            p = [tuple(c / VOX for c in pos[idx[t + q]]) for q in range(3)]
            u = [p[1][q] - p[0][q] for q in range(3)]
            v = [p[2][q] - p[0][q] for q in range(3)]
            nrm = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
            axis = max(range(3), key=lambda q: abs(nrm[q]))
            if abs(nrm[axis]) < 1e-9:
                continue
            sign = 1 if nrm[axis] > 0 else -1
            a1, a2 = [q for q in range(3) if q != axis]
            plane = round(p[0][axis])
            # Cases couvertes par le triangle dans son plan (centres des cases).
            lo1, hi1 = math.floor(min(q[a1] for q in p)), math.ceil(max(q[a1] for q in p))
            lo2, hi2 = math.floor(min(q[a2] for q in p)), math.ceil(max(q[a2] for q in p))
            for c1 in range(lo1, hi1):
                for c2 in range(lo2, hi2):
                    x, y = c1 + 0.5, c2 + 0.5
                    (x0, y0), (x1, y1), (x2, y2) = [(q[a1], q[a2]) for q in p]
                    den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
                    if abs(den) < 1e-12:
                        continue
                    l0 = ((y1 - y2) * (x - x2) + (x2 - x1) * (y - y2)) / den
                    l1 = ((y2 - y0) * (x - x2) + (x0 - x2) * (y - y2)) / den
                    if l0 < -1e-6 or l1 < -1e-6 or l0 + l1 > 1 + 1e-6:
                        continue
                    # La case bordée par la face est du côté opposé à la normale.
                    cell = [0, 0, 0]
                    cell[axis] = plane - 1 if sign > 0 else plane
                    cell[a1], cell[a2] = c1, c2
                    cells[tuple(cell)] = mat
                    if axis == 0:
                        crossings.setdefault((c1, c2) if a1 == 1 else (c2, c1), []).append((plane, sign))
        # Intérieur : entre une face -X (entrée) et une face +X (sortie).
        for (j, k), lst in crossings.items():
            lst = sorted(set(lst))
            inside = None
            for x, sign in lst:
                if sign < 0:
                    inside = x
                elif inside is not None:
                    for i in range(inside, x):
                        cells.setdefault((i, j, k), mat)
                    inside = None
    # Regroupement glouton 3D par matériau.
    done = set()
    boxes = []
    for key in sorted(cells):
        if key in done:
            continue
        m = cells[key]
        i, j, k = key

        def ok(a, b, c):
            return cells.get((a, b, c)) == m and (a, b, c) not in done

        w = 1
        while ok(i + w, j, k):
            w += 1
        h = 1
        while all(ok(i + a, j + h, k) for a in range(w)):
            h += 1
        d = 1
        while all(ok(i + a, j + b, k + d) for a in range(w) for b in range(h)):
            d += 1
        for a in range(w):
            for b in range(h):
                for c in range(d):
                    done.add((i + a, j + b, k + c))
        boxes.append((i, j, k, w, h, d, m + 1))
    return boxes


nodes = gl["nodes"]
parent = {}
for n_i, n in enumerate(nodes):
    for c in n.get("children", []):
        parent[c] = n_i

LOOPS = {"repos", "marche", "course", "victoire", "effet_braises"}


def fmt(x):
    return ("%.4f" % x).rstrip("0").rstrip(".") if x != int(x) else str(int(x))


lines = []
w = lines.append
w("-- Modèle animé généré par tools/glb_to_rig.py depuis %s (ne pas modifier à la main)." % os.path.basename(src))
w("-- Unités : mètres (1 voxel = %s). Nœuds : parent, transformation de repos, blocs." % VOX)
w("return {")
w("\tVoxel = %s," % VOX)
w("\tPalette = {")
for r, g, b, neon, tr in palette:
    w("\t\t{ Color3.fromRGB(%d, %d, %d), %s, %s }," % (r, g, b, "true" if neon else "false", fmt(tr)))
w("\t},")
w("\tNodes = {")
total = 0
for n_i, n in enumerate(nodes):
    t = n.get("translation", [0, 0, 0])
    r = n.get("rotation", [0, 0, 0, 1])
    s = n.get("scale", [1, 1, 1])
    boxes = voxelize(n["mesh"]) if "mesh" in n else []
    total += len(boxes)
    w("\t\t{ Name = %s, Parent = %d, T = { %s }, R = { %s }, S = { %s }," % (
        json.dumps(n.get("name", "n%d" % n_i)), parent.get(n_i, -1) + 1,
        ", ".join(fmt(x) for x in t), ", ".join(fmt(x) for x in r), ", ".join(fmt(x) for x in s)))
    w("\t\t\tBoxes = {")
    for b in boxes:
        w("\t\t\t\t{ %s }," % ", ".join(str(x) for x in b))
    w("\t\t\t} },")
w("\t},")
events = nodes[0].get("extras", {}).get("evenements", {})
w("\tAnimations = {")
for anim in gl["animations"]:
    name = anim["name"]
    length = 0
    w("\t\t[%s] = {" % json.dumps(name))
    w("\t\t\tLoop = %s," % ("true" if name in LOOPS else "false"))
    ev = events.get(name, [])
    w("\t\t\tEvents = { %s }," % ", ".join("{ %s, %s }" % (fmt(e["t"]), json.dumps(e["nom"])) for e in ev))
    w("\t\t\tTracks = {")
    for ch in anim["channels"]:
        path = ch["target"]["path"]
        if path not in ("translation", "rotation", "scale"):
            continue
        smp = anim["samplers"][ch["sampler"]]
        times = accessor(smp["input"])
        vals = accessor(smp["output"])
        length = max(length, max(times))
        flat = []
        for v in vals:
            flat.extend(v if isinstance(v, tuple) else (v,))
        w("\t\t\t\t{ %d, %s, { %s }, { %s } }," % (ch["target"]["node"] + 1, json.dumps(path[0].upper()),
                                                  ", ".join(fmt(x) for x in times), ", ".join(fmt(x) for x in flat)))
    w("\t\t\t},")
    w("\t\t\tLength = %s," % fmt(length))
    w("\t\t},")
w("\t},")
w("}")

out = os.path.join(root, "src", "shared", "Rigs", cid + ".luau")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
print("%d nœuds, %d blocs, %d animations -> %s" % (len(nodes), total, len(gl["animations"]), out))
