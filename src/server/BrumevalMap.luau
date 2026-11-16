--!nonstrict
--[[
	BrumevalMap : la ville de Brumeval (blockout), d'après le plan vue de dessus
	(plan-brumeval.html, 1 unité du plan = 1 stud).

	Repère : le centre du plan (340, 340) est l'origine du monde.
	  X monde = x plan - 340   (est = +X)
	  Z monde = y plan - 340   (nord = -Z, sud = +Z)

	Construit par World.server dans workspace.World.Brumeval. Le reste est fait
	ailleurs, au-dessus de ce décor :
	  • l'autel arcanique, la place ronde et les apparitions : World (buildArena) ;
	  • les six arènes de combat des colisées : ArenaBuilder ;
	  • les PNJ, la boutique et le Comptoir des Merveilles : Village ;
	  • les tables d'échange de la Bourse aux cartes : Trade.
	Le terrain est abaissé sous la ville : le sol visible est la dalle « Sol ».
]]

local BrumevalMap = {}

----------------------------------------------------------------------
-- CONFIG : hauteurs (en studs)
----------------------------------------------------------------------
local CONFIG = {
	Rempart = 30,
	TourAngle = 42,
	Tour = 36,
	Batiment = 18,
	Forge = 22,
	HautFourneau = 30,
	Haie = 4,
	MuretForge = 3,
	Colonne = 14,
	Lanterne = 9,
	TroncArbre = 60,
	Belvedere = 92,
	PlateformesArbre = 46,
}

-- Hauteurs des couches au sol (évite le scintillement entre surfaces)
local SOL = {
	Zone = 0.05,
	Rue = 0.2,
	Bordure = 0.22,
	Place = 0.3,
	Allee = 0.4,
	Tapis = 0.45,
}

local C = {
	Herbe = Color3.fromRGB(169, 201, 139),
	Pelouse = Color3.fromRGB(185, 215, 156),
	Pave = Color3.fromRGB(224, 212, 187),
	Bordure = Color3.fromRGB(150, 136, 112),
	Dalle = Color3.fromRGB(226, 218, 203),
	Terre = Color3.fromRGB(214, 191, 144),
	Gravier = Color3.fromRGB(236, 226, 203),
	Pierre = Color3.fromRGB(149, 140, 128),
	PierreSombre = Color3.fromRGB(122, 114, 104),
	Bois = Color3.fromRGB(138, 100, 64),
	BoisSombre = Color3.fromRGB(91, 63, 38),
	Eau = Color3.fromRGB(124, 186, 208),
	Violet = Color3.fromRGB(127, 94, 166),
	VioletSombre = Color3.fromRGB(74, 49, 112),
	Rouge = Color3.fromRGB(142, 59, 59),
	Tuile = Color3.fromRGB(196, 106, 82),
	Feuillage = Color3.fromRGB(95, 143, 69),
	FeuillageSombre = Color3.fromRGB(63, 107, 52),
	Haie = Color3.fromRGB(95, 143, 69),
	Feu = Color3.fromRGB(255, 154, 60),
	Fusion = Color3.fromRGB(180, 143, 240),
}

local OX, OZ = 340, 340

-- Convertit un point du plan en position monde au sol.
function BrumevalMap.world(x: number, y: number): Vector2
	return Vector2.new(x - OX, y - OZ)
end

function BrumevalMap.build(parent: Instance): Folder
	local old = parent:FindFirstChild("Brumeval")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Brumeval"

	local folders = {}
	local function zone(name)
		if not folders[name] then
			local f = Instance.new("Folder")
			f.Name = name
			f.Parent = root
			folders[name] = f
		end
		return folders[name]
	end

	local function newPart(z, name, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Parent = zone(z)
		return p
	end

	-- Rectangle donné par son coin haut-gauche (x, y) et sa taille (w, h) sur le plan
	local function rect(z, name, x, y, w, h, height, y0, color, material)
		local p = newPart(z, name, color, material)
		p.Size = Vector3.new(w, height, h)
		p.Position = Vector3.new(x + w / 2 - OX, y0 + height / 2, y + h / 2 - OZ)
		return p
	end

	-- Disque / colonne : centre (cx, cy), rayon r
	local function cyl(z, name, cx, cy, r, height, y0, color, material)
		local p = newPart(z, name, color, material)
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(height, r * 2, r * 2)
		p.CFrame = CFrame.new(cx - OX, y0 + height / 2, cy - OZ) * CFrame.Angles(0, 0, math.rad(90))
		return p
	end

	local function ball(z, name, cx, cy, r, yCenter, color, material)
		local p = newPart(z, name, color, material)
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(r * 2, r * 2, r * 2)
		p.Position = Vector3.new(cx - OX, yCenter, cy - OZ)
		return p
	end

	-- Segment de largeur w entre deux points du plan
	local function seg(z, name, x1, y1, x2, y2, w, height, y0, color, material)
		local dx, dz = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 0.01 then
			return nil
		end
		local p = newPart(z, name, color, material)
		p.Size = Vector3.new(w, height, len + w * 0.5)
		local mid = Vector3.new((x1 + x2) / 2 - OX, y0 + height / 2, (y1 + y2) / 2 - OZ)
		p.CFrame = CFrame.lookAt(mid, mid + Vector3.new(dx, 0, dz))
		return p
	end

	local function polyline(z, name, pts, w, height, y0, color, material)
		for i = 1, #pts - 1 do
			seg(z, name, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], w, height, y0, color, material)
		end
	end

	local function bezier(p0, p1, p2, p3, n)
		local pts = {}
		for i = 0, n do
			local t = i / n
			local u = 1 - t
			local x = u ^ 3 * p0[1] + 3 * u ^ 2 * t * p1[1] + 3 * u * t ^ 2 * p2[1] + t ^ 3 * p3[1]
			local y = u ^ 3 * p0[2] + 3 * u ^ 2 * t * p1[2] + 3 * u * t ^ 2 * p2[2] + t ^ 3 * p3[2]
			table.insert(pts, { x, y })
		end
		return pts
	end

	local function ellipsePts(cx, cy, rx, ry, n)
		local pts = {}
		for i = 0, n do
			local a = i / n * math.pi * 2
			table.insert(pts, { cx + math.cos(a) * rx, cy + math.sin(a) * ry })
		end
		return pts
	end

	-- Disque elliptique plat (étang)
	local function ellipseDisc(z, name, cx, cy, rx, ry, height, y0, color, material)
		local p = newPart(z, name, color, material)
		p.Size = Vector3.new(rx * 2, height, ry * 2)
		p.Position = Vector3.new(cx - OX, y0 + height / 2, cy - OZ)
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
		p.CanCollide = false
		return p
	end

	local function lantern(z, x, y)
		cyl(z, "Lanterne_Poteau", x, y, 0.4, CONFIG.Lanterne, 0, C.BoisSombre, Enum.Material.Wood)
		local l = rect(z, "Lanterne_Lumiere", x - 0.8, y - 0.8, 1.6, 1.6, 1.6, CONFIG.Lanterne, Color3.fromRGB(255, 200, 120), Enum.Material.Neon)
		l.CastShadow = false
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 190, 120)
		light.Parent = l
	end

	local function tree(z, x, y, r)
		cyl(z, "Arbre_Tronc", x, y, math.max(0.6, r * 0.18), r * 1.6, 0, C.BoisSombre, Enum.Material.Wood)
		ball(z, "Arbre_Feuillage", x, y, r, r * 1.6 + r * 0.6, C.Feuillage, Enum.Material.Grass)
	end

	local function wall(z, name, x1, y1, x2, y2, t, height, color, material)
		return seg(z, name, x1, y1, x2, y2, t, height, 0, color, material)
	end

	----------------------------------------------------------------------
	-- SOL, REMPARTS, TOURS, PORTE DU SUD (les douves sont dans le terrain)
	----------------------------------------------------------------------
	local Z = "Remparts"
	rect(Z, "Sol", 0, 0, 680, 680, 1, -1, C.Herbe, Enum.Material.Grass)
	rect(Z, "Rempart_Nord", 0, 0, 680, 10, CONFIG.Rempart, 0, C.Pierre, Enum.Material.Cobblestone)
	rect(Z, "Rempart_Ouest", 0, 10, 10, 660, CONFIG.Rempart, 0, C.Pierre, Enum.Material.Cobblestone)
	rect(Z, "Rempart_Est", 670, 10, 10, 660, CONFIG.Rempart, 0, C.Pierre, Enum.Material.Cobblestone)
	rect(Z, "Rempart_Sud_Ouest", 0, 670, 330, 10, CONFIG.Rempart, 0, C.Pierre, Enum.Material.Cobblestone)
	rect(Z, "Rempart_Sud_Est", 350, 670, 330, 10, CONFIG.Rempart, 0, C.Pierre, Enum.Material.Cobblestone)
	rect(Z, "Porte_Sud_Linteau", 330, 670, 20, 10, 8, CONFIG.Rempart - 8, C.Pierre, Enum.Material.Cobblestone)
	for _, c in ipairs({ { 5, 5 }, { 675, 5 }, { 5, 675 }, { 675, 675 } }) do
		cyl(Z, "Tour_Angle", c[1], c[2], 15, CONFIG.TourAngle, 0, C.PierreSombre, Enum.Material.Cobblestone)
	end
	for _, v in ipairs({ 110, 215, 465, 570 }) do
		local r = (v == 215 or v == 465) and 11 or 8
		for _, c in ipairs({ { v, 5 }, { v, 675 }, { 5, v }, { 675, v } }) do
			cyl(Z, "Tour", c[1], c[2], r, CONFIG.Tour, 0, C.PierreSombre, Enum.Material.Cobblestone)
		end
	end
	cyl(Z, "Tour_Porte_Ouest", 318, 675, 11, CONFIG.Tour, 0, C.PierreSombre, Enum.Material.Cobblestone)
	cyl(Z, "Tour_Porte_Est", 362, 675, 11, CONFIG.Tour, 0, C.PierreSombre, Enum.Material.Cobblestone)
	rect(Z, "Pont_Levis", 324, 678, 32, 20, 0.6, 0, C.Bois, Enum.Material.WoodPlanks)

	----------------------------------------------------------------------
	-- RUES (grille, avenues, chemins diagonaux) + bordures au ras du sol
	----------------------------------------------------------------------
	Z = "Rues"
	local function street(name, x, y, w, h)
		rect(Z, name, x, y, w, h, SOL.Rue, 0, C.Pave, Enum.Material.Cobblestone)
		if w > h then
			rect(Z, name .. "_Bordure", x, y, w, 1, SOL.Bordure, 0, C.Bordure, Enum.Material.Slate)
			rect(Z, name .. "_Bordure", x, y + h - 1, w, 1, SOL.Bordure, 0, C.Bordure, Enum.Material.Slate)
		else
			rect(Z, name .. "_Bordure", x, y, 1, h, SOL.Bordure, 0, C.Bordure, Enum.Material.Slate)
			rect(Z, name .. "_Bordure", x + w - 1, y, 1, h, SOL.Bordure, 0, C.Bordure, Enum.Material.Slate)
		end
	end
	street("Rue_Nord", 10, 209, 660, 12)
	street("Rue_Sud", 10, 459, 660, 12)
	street("Rue_Ouest", 209, 10, 12, 660)
	street("Rue_Est", 459, 10, 12, 660)
	street("Avenue_Nord", 331, 196, 18, 40)
	street("Avenue_Sud", 331, 444, 18, 254)
	street("Avenue_Est", 444, 331, 78, 18)
	street("Avenue_Ouest", 158, 331, 78, 18)
	street("Rue_Echanges_Ouest", 194, 559, 35, 12)
	street("Rue_Echanges_Est", 451, 560, 37, 10)
	street("Acces_Bourse_Nord", 106, 465, 8, 25)
	street("Acces_Arbre_Nord", 565, 465, 10, 18)
	street("Acces_Galerie_Ouest", 215, 111, 22, 8)
	street("Acces_Galerie_Est", 443, 111, 22, 8)
	street("Acces_Forge_Sud", 105, 198, 10, 17)
	street("Acces_Forge_Est", 198, 145, 17, 10)
	for _, d in ipairs({ { 215, 215, 290, 290 }, { 465, 215, 390, 290 }, { 215, 465, 290, 390 }, { 465, 465, 390, 390 } }) do
		seg(Z, "Chemin_Diagonal", d[1], d[2], d[3], d[4], 10, SOL.Rue - 0.02, 0, C.Terre, Enum.Material.Ground)
	end

	-- Panneaux d'orientation
	local signs = {
		{ 205, 205, "Nord : forge · Est : galerie des collections · Sud : colisée Ouest" },
		{ 455, 205, "Ouest : galerie des collections · Est : parc · Sud : colisée Est" },
		{ 205, 455, "Nord : colisée Ouest · Sud : bourse aux cartes · Est : Grand-Place" },
		{ 475, 455, "Nord : colisée Est · Sud : arbre géant · Ouest : Grand-Place" },
		{ 322, 654, "Nord : Grand-Place puis arène · Ouest : rue des Échanges" },
	}
	for _, s in ipairs(signs) do
		local post = cyl(Z, "Panneau", s[1], s[2], 0.35, 8, 0, C.BoisSombre, Enum.Material.Wood)
		post:SetAttribute("Directions", s[3])
		rect(Z, "Panneau_Fleche", s[1] - 3, s[2] - 0.2, 6, 0.4, 1.2, 6.2, C.Bois, Enum.Material.Wood)
	end

	----------------------------------------------------------------------
	-- CENTRE : pelouse, lanternes et poteaux (place, arène et autel : World)
	----------------------------------------------------------------------
	Z = "Centre"
	rect(Z, "Pelouse", 221, 221, 238, 238, SOL.Zone, 0, C.Pelouse, Enum.Material.Grass)
	for i = 0, 11 do
		local a = i * math.pi / 6 + math.pi / 12
		lantern(Z, 340 + math.cos(a) * 92, 340 + math.sin(a) * 92)
	end
	for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local k, o = 120 / math.sqrt(2), 10 / math.sqrt(2)
		local px, py = 340 + d[1] * k, 340 + d[2] * k
		cyl(Z, "Poteau", px + d[2] * o, py - d[1] * o, 1.7, 4, 0, C.Bois, Enum.Material.Wood)
		cyl(Z, "Poteau", px - d[2] * o, py + d[1] * o, 1.7, 4, 0, C.Bois, Enum.Material.Wood)
	end

	----------------------------------------------------------------------
	-- NORD : galerie des collections (zone ouverte)
	----------------------------------------------------------------------
	Z = "Galerie"
	rect(Z, "Sol", 221, 10, 238, 199, SOL.Zone, 0, C.Pelouse, Enum.Material.Grass)
	rect(Z, "Esplanade", 237, 38, 206, 155, SOL.Place, 0, C.Dalle, Enum.Material.Slate)
	wall(Z, "Haie", 235, 36, 445, 36, 4, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	wall(Z, "Haie", 235, 195, 328, 195, 4, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	wall(Z, "Haie", 352, 195, 445, 195, 4, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	wall(Z, "Haie", 235, 36, 235, 104, 4, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	wall(Z, "Haie", 235, 126, 235, 195, 4, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	wall(Z, "Haie", 445, 36, 445, 104, 4, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	wall(Z, "Haie", 445, 126, 445, 195, 4, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	rect(Z, "Tapis_NordSud", 330, 38, 20, 160, SOL.Tapis, 0, C.Violet, Enum.Material.Fabric)
	rect(Z, "Tapis_EstOuest", 232, 106, 216, 18, SOL.Tapis, 0, C.Violet, Enum.Material.Fabric)
	for _, x in ipairs({ 246, 280, 372, 406 }) do
		for _, y in ipairs({ 48, 76, 134, 162 }) do
			rect(Z, "Vitrine_Socle", x, y, 28, 18, 3, 0, Color3.fromRGB(107, 93, 82), Enum.Material.Wood)
			local v = rect(Z, "Vitrine_Verre", x + 2, y + 2, 24, 14, 3, 3, Color3.fromRGB(217, 238, 245), Enum.Material.Glass)
			v.Transparency = 0.5
		end
	end
	for _, l in ipairs({ { 319, 52 }, { 361, 52 }, { 319, 90 }, { 361, 90 }, { 319, 140 }, { 361, 140 }, { 319, 178 }, { 361, 178 } }) do
		lantern(Z, l[1], l[2])
	end

	----------------------------------------------------------------------
	-- NORD-OUEST : forge de Borin
	----------------------------------------------------------------------
	Z = "Forge"
	rect(Z, "Cour", 22, 22, 176, 176, SOL.Place, 0, C.Pave, Enum.Material.Cobblestone)
	-- muret (entrées au sud x 100-120 et à l'est y 140-160)
	wall(Z, "Muret", 22, 22, 198, 22, 4, CONFIG.MuretForge, C.Pierre, Enum.Material.Cobblestone)
	wall(Z, "Muret", 22, 22, 22, 198, 4, CONFIG.MuretForge, C.Pierre, Enum.Material.Cobblestone)
	wall(Z, "Muret", 22, 198, 100, 198, 4, CONFIG.MuretForge, C.Pierre, Enum.Material.Cobblestone)
	wall(Z, "Muret", 120, 198, 198, 198, 4, CONFIG.MuretForge, C.Pierre, Enum.Material.Cobblestone)
	wall(Z, "Muret", 198, 22, 198, 140, 4, CONFIG.MuretForge, C.Pierre, Enum.Material.Cobblestone)
	wall(Z, "Muret", 198, 160, 198, 198, 4, CONFIG.MuretForge, C.Pierre, Enum.Material.Cobblestone)
	rect(Z, "Allee_Principale", 98, 72, 24, 126, SOL.Allee, 0, C.Dalle, Enum.Material.Slate)
	rect(Z, "Allee_Est", 122, 140, 76, 20, SOL.Allee, 0, C.Dalle, Enum.Material.Slate)
	rect(Z, "Forge_Batiment", 34, 28, 152, 44, CONFIG.Forge, 0, Color3.fromRGB(107, 93, 82), Enum.Material.Brick)
	rect(Z, "Forge_Cheminee", 160, 34, 12, 12, CONFIG.Forge + 8, 0, C.PierreSombre, Enum.Material.Brick)
	cyl(Z, "Haut_Fourneau", 48, 50, 15, CONFIG.HautFourneau, 0, Color3.fromRGB(110, 95, 85), Enum.Material.Brick)
	local feu = cyl(Z, "Haut_Fourneau_Feu", 48, 50, 6.5, 1, CONFIG.HautFourneau, C.Feu, Enum.Material.Neon)
	local fl = Instance.new("PointLight")
	fl.Range = 28
	fl.Color = C.Feu
	fl.Parent = feu
	rect(Z, "Enclume", 80, 80, 14, 7, 3, 0, Color3.fromRGB(75, 71, 68), Enum.Material.Metal)
	rect(Z, "Enclume", 126, 80, 14, 7, 3, 0, Color3.fromRGB(75, 71, 68), Enum.Material.Metal)
	rect(Z, "Armurerie", 30, 84, 44, 56, CONFIG.Batiment, 0, Color3.fromRGB(143, 120, 98), Enum.Material.Brick)
	rect(Z, "Comptoir_Vente", 146, 84, 44, 50, CONFIG.Batiment, 0, Color3.fromRGB(125, 106, 142), Enum.Material.Brick)
	rect(Z, "Bac_Charbon", 30, 168, 60, 22, 2, 0, Color3.fromRGB(47, 42, 39), Enum.Material.Slate)
	rect(Z, "Bac_Minerai", 130, 168, 60, 22, 2, 0, Color3.fromRGB(154, 163, 173), Enum.Material.Rock)
	cyl(Z, "Autel_Fusion", 110, 116, 13, 1.5, 0, Color3.fromRGB(233, 225, 244), Enum.Material.Marble)
	local af = cyl(Z, "Autel_Fusion_Cristal", 110, 116, 3, 4, 1.5, C.Fusion, Enum.Material.Neon)
	local afl = Instance.new("PointLight")
	afl.Range = 20
	afl.Color = C.Fusion
	afl.Parent = af
	lantern(Z, 92, 180)
	lantern(Z, 128, 180)

	----------------------------------------------------------------------
	-- NORD-EST : parc
	----------------------------------------------------------------------
	Z = "Parc"
	rect(Z, "Pelouse", 471, 10, 199, 199, SOL.Zone, 0, C.Pelouse, Enum.Material.Grass)
	-- haie (entrées ouest y 112-128 et sud x 567-583)
	wall(Z, "Haie", 475, 14, 475, 112, 5, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	wall(Z, "Haie", 475, 128, 475, 205, 5, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	wall(Z, "Haie", 475, 14, 666, 14, 5, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	wall(Z, "Haie", 666, 14, 666, 205, 5, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	wall(Z, "Haie", 475, 205, 567, 205, 5, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	wall(Z, "Haie", 583, 205, 666, 205, 5, CONFIG.Haie, C.Haie, Enum.Material.Grass)
	local G = Enum.Material.Pebble
	polyline(Z, "Allee", bezier({ 471, 120 }, { 495, 120 }, { 508, 150 }, { 530, 160 }, 12), 8, SOL.Allee, 0, C.Gravier, G)
	polyline(Z, "Allee", bezier({ 530, 160 }, { 552, 170 }, { 575, 182 }, { 575, 209 }, 12), 8, SOL.Allee, 0, C.Gravier, G)
	polyline(Z, "Allee_Etang", ellipsePts(595, 80, 50, 36, 48), 7, SOL.Allee, 0, C.Gravier, G)
	polyline(Z, "Allee", bezier({ 530, 160 }, { 540, 140 }, { 548, 122 }, { 560, 105 }, 10), 6, SOL.Allee, 0, C.Gravier, G)
	polyline(Z, "Allee", bezier({ 595, 116 }, { 596, 145 }, { 588, 168 }, { 574, 190 }, 10), 6, SOL.Allee, 0, C.Gravier, G)
	polyline(Z, "Allee", bezier({ 545, 80 }, { 535, 78 }, { 526, 68 }, { 512, 58 }, 8), 6, SOL.Allee, 0, C.Gravier, G)
	seg(Z, "Allee", 606, 104, 606, 115, 5, SOL.Allee, 0, C.Gravier, G)
	ellipseDisc(Z, "Etang_Berge", 595, 80, 39, 26.5, 0.5, 0, Color3.fromRGB(185, 167, 138), Enum.Material.Sand)
	local etang = ellipseDisc(Z, "Etang", 595, 80, 37, 24.5, 0.7, 0, C.Eau, Enum.Material.Glass)
	etang.Transparency = 0.2
	cyl(Z, "Ile", 606, 76, 9, 1.2, 0, C.Pelouse, Enum.Material.Grass)
	rect(Z, "Pont", 602, 83, 8, 23, 1.4, 0, C.Bois, Enum.Material.WoodPlanks)
	cyl(Z, "Roseraie", 512, 58, 20, 0.8, 0, C.Haie, Enum.Material.Grass)
	cyl(Z, "Roseraie_Fontaine", 512, 58, 5.5, 2.5, 0, C.Dalle, Enum.Material.Marble)
	cyl(Z, "Kiosque_Parvis", 530, 160, 15, SOL.Place, 0, C.Dalle, Enum.Material.Slate)
	cyl(Z, "Kiosque_Sol", 530, 160, 11, 1.5, 0, Color3.fromRGB(243, 236, 223), Enum.Material.WoodPlanks)
	for i = 0, 7 do
		local a = i * math.pi / 4
		cyl(Z, "Kiosque_Colonne", 530 + math.cos(a) * 10, 160 + math.sin(a) * 10, 0.5, 9, 1.5, Color3.fromRGB(243, 236, 223), Enum.Material.Marble)
	end
	cyl(Z, "Kiosque_Toit", 530, 160, 12, 1.2, 10.5, Color3.fromRGB(243, 236, 223), Enum.Material.SmoothPlastic)
	for _, b in ipairs({ { 595, 123, 0 }, { 595, 37, 0 }, { 652, 80, 90 } }) do
		local p = rect(Z, "Banc", b[1] - 6, b[2] - 2, 12, 4, 1.8, 0, C.Bois, Enum.Material.Wood)
		p.CFrame = p.CFrame * CFrame.Angles(0, math.rad(b[3]), 0)
	end
	for _, l in ipairs({ { 482, 112 }, { 482, 128 }, { 568, 206 }, { 582, 206 } }) do
		lantern(Z, l[1], l[2])
	end
	for _, t in ipairs({ { 548, 34, 6 }, { 563, 28, 4 }, { 634, 32, 5 }, { 648, 40, 7 }, { 638, 150, 8 }, { 624, 170, 6 }, { 644, 176, 6 }, { 630, 190, 4 }, { 496, 174, 8 }, { 502, 192, 5 }, { 606, 75, 4.5 }, { 570, 140, 5 } }) do
		tree(Z, t[1], t[2], t[3])
	end

	----------------------------------------------------------------------
	-- OUEST et EST : colisées (sol et parvis ; les arènes : ArenaBuilder)
	----------------------------------------------------------------------
	Z = "ColiseeOuest"
	rect(Z, "Sol", 10, 221, 199, 238, SOL.Zone, 0, Color3.fromRGB(205, 196, 166), Enum.Material.Ground)
	rect(Z, "Parvis", 164, 228, 40, 224, SOL.Place, 0, C.Pave, Enum.Material.Cobblestone)
	Z = "ColiseeEst"
	rect(Z, "Sol", 471, 221, 199, 238, SOL.Zone, 0, Color3.fromRGB(205, 196, 166), Enum.Material.Ground)
	rect(Z, "Parvis", 476, 228, 40, 224, SOL.Place, 0, C.Pave, Enum.Material.Cobblestone)

	----------------------------------------------------------------------
	-- SUD-OUEST : bourse aux cartes (tables d'échange : Trade)
	----------------------------------------------------------------------
	Z = "BourseAuxCartes"
	rect(Z, "Place", 16, 477, 188, 187, SOL.Place, 0, C.Pave, Enum.Material.Cobblestone)
	rect(Z, "Pavillon_Sol", 30, 492, 160, 152, SOL.Allee, 0, C.VioletSombre, Enum.Material.Slate)
	rect(Z, "Pavillon_Dallage", 35, 497, 150, 142, SOL.Allee + 0.02, 0, C.Dalle, Enum.Material.Marble)
	rect(Z, "Tapis_NordSud", 102, 497, 16, 142, SOL.Tapis + 0.02, 0, C.Rouge, Enum.Material.Fabric)
	rect(Z, "Tapis_EstOuest", 35, 560, 150, 16, SOL.Tapis + 0.02, 0, C.Rouge, Enum.Material.Fabric)
	for _, x in ipairs({ 35, 65, 95, 125, 155, 185 }) do
		cyl(Z, "Colonne", x, 497, 3, CONFIG.Colonne, 0, Color3.fromRGB(230, 220, 196), Enum.Material.Marble)
		cyl(Z, "Colonne", x, 639, 3, CONFIG.Colonne, 0, Color3.fromRGB(230, 220, 196), Enum.Material.Marble)
	end
	for _, y in ipairs({ 532, 604 }) do
		cyl(Z, "Colonne", 35, y, 3, CONFIG.Colonne, 0, Color3.fromRGB(230, 220, 196), Enum.Material.Marble)
		cyl(Z, "Colonne", 185, y, 3, CONFIG.Colonne, 0, Color3.fromRGB(230, 220, 196), Enum.Material.Marble)
	end
	for _, l in ipairs({ { 22, 483 }, { 198, 483 }, { 22, 658 }, { 198, 658 } }) do
		lantern(Z, l[1], l[2])
	end

	----------------------------------------------------------------------
	-- SUD : Grand-Place
	----------------------------------------------------------------------
	Z = "GrandePlace"
	rect(Z, "Place", 229, 479, 222, 183, SOL.Place, 0, C.Pave, Enum.Material.Cobblestone)
	rect(Z, "Allee_NordSud", 328, 479, 24, 183, SOL.Allee, 0, C.Dalle, Enum.Material.Slate)
	rect(Z, "Allee_EstOuest", 229, 553, 222, 24, SOL.Allee, 0, C.Dalle, Enum.Material.Slate)
	rect(Z, "Comptoir_des_Merveilles", 237, 489, 87, 30, CONFIG.Batiment, 0, C.Violet, Enum.Material.Brick)
	rect(Z, "Boutique_Elya", 356, 489, 87, 30, CONFIG.Batiment, 0, C.Tuile, Enum.Material.Brick)
	local awn = { Color3.fromRGB(196, 65, 47), Color3.fromRGB(63, 111, 168) }
	for side, xs in ipairs({ { 252, 280, 308 }, { 372, 400, 428 } }) do
		for _, x in ipairs(xs) do
			rect(Z, "Etal", x - 11, 529, 22, 14, 3, 0, C.Bois, Enum.Material.Wood)
			rect(Z, "Etal_Auvent", x - 12, 528, 24, 16, 0.4, 7, awn[side], Enum.Material.Fabric)
		end
	end
	rect(Z, "Terrasse_Plancher", 241, 586, 76, 62, 0.6, 0, C.Bois, Enum.Material.WoodPlanks)
	for _, c in ipairs({ { 241, 586 }, { 305, 586 }, { 241, 636 }, { 305, 636 } }) do
		rect(Z, "Bac_Fleurs", c[1], c[2], 12, 12, 2.5, 0.6, C.Bois, Enum.Material.Wood)
	end
	for _, x in ipairs({ 262, 296 }) do
		for _, y in ipairs({ 600, 617, 634 }) do
			rect(Z, "Table", x - 12, y - 3.5, 24, 7, 3, 0.6, Color3.fromRGB(201, 167, 122), Enum.Material.Wood)
			rect(Z, "Banc", x - 11, y - 7, 22, 2.6, 1.6, 0.6, C.BoisSombre, Enum.Material.Wood)
			rect(Z, "Banc", x - 11, y + 4.4, 22, 2.6, 1.6, 0.6, C.BoisSombre, Enum.Material.Wood)
		end
	end
	rect(Z, "Estrade", 370, 586, 60, 22, 3, 0, C.Bois, Enum.Material.WoodPlanks)
	rect(Z, "Estrade_Rideau", 370, 586, 60, 3, 12, 3, C.Rouge, Enum.Material.Fabric)
	for _, y in ipairs({ 620, 632, 644 }) do
		for _, x in ipairs({ 382, 418 }) do
			rect(Z, "Banc_Public", x - 14, y - 2, 28, 4, 1.6, 0, C.Bois, Enum.Material.Wood)
		end
	end
	for _, l in ipairs({ { 322, 547 }, { 358, 547 }, { 322, 583 }, { 358, 583 } }) do
		lantern(Z, l[1], l[2])
	end

	----------------------------------------------------------------------
	-- SUD-EST : arbre géant
	----------------------------------------------------------------------
	Z = "ArbreGeant"
	local CX, CY = 570, 565
	rect(Z, "Sol", 471, 471, 199, 199, SOL.Zone, 0, C.Herbe, Enum.Material.Grass)
	polyline(Z, "Allee_Circulaire", ellipsePts(CX, CY, 84, 84, 64), 9, SOL.Allee, 0, C.Gravier, Enum.Material.Pebble)
	seg(Z, "Allee_Escalier", 511, 624, 519, 616, 6, SOL.Allee, 0, C.Gravier, Enum.Material.Pebble)
	cyl(Z, "Pied", CX, CY, 79, 0.2, 0, C.Pelouse, Enum.Material.Grass)
	cyl(Z, "Tronc", CX, CY, 20, CONFIG.TroncArbre, 0, Color3.fromRGB(93, 65, 40), Enum.Material.Wood)
	for i, deg in ipairs({ 20, 65, 110, 155, 245, 290, 335 }) do
		local a = math.rad(deg)
		seg(Z, "Racine", CX + math.cos(a) * 18, CY + math.sin(a) * 18, CX + math.cos(a) * 76, CY + math.sin(a) * 76, i % 2 == 0 and 4 or 6, 3, 0, Color3.fromRGB(93, 65, 40), Enum.Material.Wood)
	end
	for i = 0, 13 do
		local a = i * math.pi / 7 + 0.2
		local r = (i % 2 == 1) and 54 or 50
		ball(Z, "Feuillage", CX + math.cos(a) * r, CY + math.sin(a) * r, (i % 2 == 1) and 20 or 23, CONFIG.TroncArbre + 8, (i % 2 == 1) and C.Feuillage or C.FeuillageSombre, Enum.Material.Grass)
	end
	for i = 0, 6 do
		local a = i * math.pi * 2 / 7 + 0.6
		ball(Z, "Feuillage", CX + math.cos(a) * 30, CY + math.sin(a) * 30, 22, CONFIG.TroncArbre + 16, C.Feuillage, Enum.Material.Grass)
	end
	ball(Z, "Feuillage", CX, CY, 24, CONFIG.TroncArbre + 18, C.Feuillage, Enum.Material.Grass)
	for _, d in ipairs(zone(Z):GetChildren()) do
		if d.Name == "Feuillage" then
			d.CanCollide = false -- on traverse le feuillage pour monter l'escalier
			d.CanQuery = false
			d.Transparency = 0.15
		end
	end
	cyl(Z, "Belvedere", CX, CY, 15, 1, CONFIG.Belvedere, C.Bois, Enum.Material.WoodPlanks)
	for i = 0, 15 do
		local a = i * math.pi / 8
		cyl(Z, "Belvedere_Rambarde", CX + math.cos(a) * 14, CY + math.sin(a) * 14, 0.3, 3.5, CONFIG.Belvedere + 1, C.BoisSombre, Enum.Material.Wood)
	end
	-- plateformes et ponts de corde
	local decks = { 315, 45, 135 }
	for k, deg in ipairs(decks) do
		local a = math.rad(deg)
		local x, y = CX + math.cos(a) * 62, CY + math.sin(a) * 62
		local d = rect(Z, "Plateforme", x - 11, y - 8, 22, 16, 1, CONFIG.PlateformesArbre, C.Bois, Enum.Material.WoodPlanks)
		d.CFrame = d.CFrame * CFrame.Angles(0, -math.rad(deg + 90), 0)
		lantern(Z, x, y)
		local a1, a2 = math.rad(deg), math.rad(decks[k % #decks + 1])
		if a2 < a1 then
			a2 += math.pi * 2
		end
		local pts = {}
		for t = 0, 12 do
			local aa = a1 + (a2 - a1) * t / 12
			table.insert(pts, { CX + math.cos(aa) * 62, CY + math.sin(aa) * 62 })
		end
		polyline(Z, "Pont_Corde", pts, 3, 0.4, CONFIG.PlateformesArbre + 0.3, Color3.fromRGB(201, 167, 122), Enum.Material.WoodPlanks)
	end
	-- Escalier en spirale, du sol (sud-ouest) jusqu'au belvédère. Marches
	-- serrées qui se chevauchent (0,72 stud de montée chacune) : on y monte
	-- en marchant, sans sauter.
	local steps = 128
	for t = 0, steps do
		local a = math.rad(135 + t * 3)
		local r = 72 - t * 0.42
		local x, y = CX + math.cos(a) * r, CY + math.sin(a) * r
		local h = CONFIG.Belvedere * t / steps
		local p = newPart(Z, "Escalier_Marche", C.Bois, Enum.Material.WoodPlanks)
		p.Size = Vector3.new(6, 0.8, 8) -- X vers l'extérieur, Z le long de la spirale
		p.CFrame = CFrame.new(x - OX, h + 0.4, y - OZ) * CFrame.Angles(0, -a, 0)
	end

	-- Petits décors : pas d'ombre (fluidité).
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.Size.Y < 1 and d.Name ~= "Sol" then
			d.CastShadow = false
		end
	end

	root.Parent = parent
	return root
end

return BrumevalMap
