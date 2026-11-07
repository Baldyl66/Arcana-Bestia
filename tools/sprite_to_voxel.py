"""Convertit un sprite pixel art (fond magenta uni) en données de voxels Luau.

Usage : python tools/sprite_to_voxel.py <sprite.png> <id> [taille_max]

- retire le fond magenta (#FF00FF et voisins) ;
- détecte la taille des « gros pixels » d'une image agrandie et revient à la
  vraie grille (ou réduit à `taille_max` cases de large) ;
- limite la palette (10 couleurs par défaut) et lisse les pixels isolés ;
- regroupe les cases de même couleur en rectangles (peu de pièces Roblox).

Écrit src/shared/Voxels/<id>.luau : { W, H, Palette = {...}, Boxes = { {x, y, w, h, couleur, épaisseur}, ... } }
(x vers la droite = tête de la créature, y vers le haut).
"""
import os
import sys
from collections import Counter

from PIL import Image

src, cid = sys.argv[1], sys.argv[2]
max_w = int(sys.argv[3]) if len(sys.argv) > 3 else 48
colors = int(sys.argv[4]) if len(sys.argv) > 4 else 10
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

im = Image.open(src).convert("RGB")
w, h = im.size
px = im.load()


def is_bg(c):
    r, g, b = c
    return r > 150 and b > 150 and g < 110 and abs(r - b) < 90


# Taille d'un « gros pixel » : longueur de plage la plus fréquente.
runs = Counter()
for y in range(0, h, max(1, h // 60)):
    run, prev = 0, None
    for x in range(w):
        c = px[x, y]
        if prev is not None and sum(abs(a - b) for a, b in zip(c, prev)) < 24:
            run += 1
        else:
            if run >= 2:
                runs[run] += 1
            run = 1
        prev = c
cell = max(1, runs.most_common(1)[0][0]) if runs else 1
gw = max(1, round(w / cell))
if gw > max_w:
    gw = max_w
gh = max(1, round(h * gw / w))
sx, sy = w / gw, h / gh

# Échantillonnage : couleur majoritaire au centre de chaque case.
grid = [[None] * gw for _ in range(gh)]
for j in range(gh):
    for i in range(gw):
        votes = Counter()
        for dx in (0.3, 0.5, 0.7):
            for dy in (0.3, 0.5, 0.7):
                c = px[min(w - 1, int((i + dx) * sx)), min(h - 1, int((j + dy) * sy))]
                votes[None if is_bg(c) else c] += 1
        c = votes.most_common(1)[0][0]
        grid[j][i] = c

# Recadrage sur la créature.
cols = [i for i in range(gw) if any(grid[j][i] for j in range(gh))]
rows = [j for j in range(gh) if any(grid[j][i] for i in range(gw))]
i0, i1, j0, j1 = min(cols), max(cols), min(rows), max(rows)
grid = [row[i0:i1 + 1] for row in grid[j0:j1 + 1]]
gh, gw = len(grid), len(grid[0])

# Palette réduite.
cells = [(i, j, grid[j][i]) for j in range(gh) for i in range(gw) if grid[j][i]]
strip = Image.new("RGB", (len(cells), 1))
strip.putdata([c for _, _, c in cells])
q = strip.quantize(colors=colors, method=Image.Quantize.MEDIANCUT)
pal = q.getpalette()[: colors * 3]
idx = list(q.get_flattened_data() if hasattr(q, "get_flattened_data") else q.getdata())
used = sorted(set(idx))
remap = {old: n + 1 for n, old in enumerate(used)}
palette = [tuple(pal[o * 3: o * 3 + 3]) for o in used]
cgrid = [[0] * gw for _ in range(gh)]
for (i, j, _), k in zip(cells, idx):
    cgrid[j][i] = remap[k]

# Lissage : une case entourée d'au moins 5 voisines d'une même autre couleur
# prend cette couleur (moins de « bruit », donc moins de blocs).
for _ in range(2):
    nxt = [row[:] for row in cgrid]
    for j in range(gh):
        for i in range(gw):
            c = cgrid[j][i]
            if not c:
                continue
            votes = Counter()
            for dj in (-1, 0, 1):
                for di in (-1, 0, 1):
                    if (di or dj) and 0 <= j + dj < gh and 0 <= i + di < gw and cgrid[j + dj][i + di]:
                        votes[cgrid[j + dj][i + di]] += 1
            if votes:
                best, n = votes.most_common(1)[0]
                if best != c and n >= 5:
                    nxt[j][i] = best
    cgrid = nxt

# Relief : épaisseur selon la distance au bord de la silhouette (fin sur les
# contours, bombé au centre du corps), par paliers impairs pour rester centré.
INF = 10 ** 6
dist = [[INF if cgrid[j][i] else 0 for i in range(gw)] for j in range(gh)]
changed = True
while changed:
    changed = False
    for j in range(gh):
        for i in range(gw):
            if not cgrid[j][i]:
                continue
            best = dist[j][i]
            for dj, di in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                jj, ii = j + dj, i + di
                neighbour = dist[jj][ii] if 0 <= jj < gh and 0 <= ii < gw else 0
                best = min(best, neighbour + 1)
            if best < dist[j][i]:
                dist[j][i] = best
                changed = True
MAX_DEPTH = 11
depth = [[min(MAX_DEPTH, 2 * dist[j][i] - 1) if cgrid[j][i] else 0 for i in range(gw)] for j in range(gh)]

# Regroupement glouton en rectangles (même couleur ET même épaisseur).
done = [[False] * gw for _ in range(gh)]
boxes = []
for j in range(gh):
    for i in range(gw):
        c = cgrid[j][i]
        if not c or done[j][i]:
            continue
        d = depth[j][i]

        def same(jj, ii):
            return cgrid[jj][ii] == c and depth[jj][ii] == d and not done[jj][ii]

        bw = 1
        while i + bw < gw and same(j, i + bw):
            bw += 1
        bh = 1
        while j + bh < gh and all(same(j + bh, i + k) for k in range(bw)):
            bh += 1
        for jj in range(j, j + bh):
            for ii in range(i, i + bw):
                done[jj][ii] = True
        # y vers le haut : la ligne 0 de l'image est en haut.
        boxes.append((i, gh - (j + bh), bw, bh, c, d))

out = os.path.join(root, "src", "shared", "Voxels", cid + ".luau")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write("-- Voxels générés par tools/sprite_to_voxel.py depuis %s (ne pas modifier à la main).\n" % os.path.basename(src))
    f.write("return {\n\tW = %d,\n\tH = %d,\n\tPalette = {\n" % (gw, gh))
    for r, g, b in palette:
        f.write("\t\tColor3.fromRGB(%d, %d, %d),\n" % (r, g, b))
    f.write("\t},\n\tBoxes = {\n")
    for b in boxes:
        f.write("\t\t{ %d, %d, %d, %d, %d, %d },\n" % b)
    f.write("\t},\n}\n")
print("cellule %d px -> grille %dx%d, %d couleurs, %d blocs -> %s" % (cell, gw, gh, len(palette), len(boxes), out))

# Aperçu agrandi pour contrôle.
prev = Image.new("RGB", (gw, gh), (40, 30, 50))
pp = prev.load()
for j in range(gh):
    for i in range(gw):
        if cgrid[j][i]:
            pp[i, j] = palette[cgrid[j][i] - 1]
prev.resize((gw * 8, gh * 8), Image.NEAREST).save(os.path.join(os.environ.get("TEMP", "."), cid + "_voxel_apercu.png"))
