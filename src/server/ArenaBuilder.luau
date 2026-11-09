--!nonstrict
--[[
	ArenaBuilder : les Arènes des Champions (Arcana Bestia, cité de Brumeval)

	Six arènes rectangulaires identiques (trois à l'est, trois à l'ouest), une par
	duel simultané. Tout est construit par script, rien ne vole ni ne tourne.

	Contrat avec le client (Arena3D) pour chaque arène :
	  • Model nommé comme son emplacement (« Est1 »…), dans workspace.World.Arenes
	  • <arène>.Runes   : UNIQUEMENT des BasePart Neon violet (150,110,255), Transparency 0.25
	                      (Arena3D:lightCircle) ; le sceau central porte un PointLight « Halo »
	  • <arène>.Piliers : 6 Models (Feu, Eau, Nature, Foudre, Ombre, Lumiere), attribut Element,
	                      enfant « Cristal » (PointLight + ParticleEmitter « Eclat »), posé dans
	                      sa griffe dorée (Arena3D:lightPillars)
	  • « Sol » : dessus plat à FloorHeight, CanQuery = true ; toute la déco est CanQuery = false
	  • Rien de haut dans le rectangle de combat : seuls des parapets bas (2,4 studs) le bordent

	Repère local d'une arène : origine au centre, au sol extérieur ; axe Z = axe des
	duellistes (-Z vers l'entrée de la zone), X en travers.
]]

local VillageData = require(game:GetService("ReplicatedStorage"):WaitForChild("Configs"):WaitForChild("VillageData"))

local ArenaBuilder = {}

local DIM = VillageData.Arena
local HL, HW, FY = DIM.Length / 2, DIM.Width / 2, DIM.FloorHeight -- 42, 19, 1.5

----------------------------------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------------------------------

local ARCANE = Color3.fromRGB(150, 110, 255)
local OR = Color3.fromRGB(214, 172, 74)
local OR_CLAIR = Color3.fromRGB(247, 216, 128)
local MARBRE = Color3.fromRGB(226, 221, 211)
local MARBRE_VEINE = Color3.fromRGB(176, 166, 154)
local PIERRE = Color3.fromRGB(150, 142, 132)
local PIERRE_SOMBRE = Color3.fromRGB(78, 74, 88)
local ARDOISE = Color3.fromRGB(36, 32, 50)

local ELEMENTS = {
	Feu = { couleur = Color3.fromRGB(255, 110, 40), tissu = Color3.fromRGB(120, 30, 18), pierre = Color3.fromRGB(52, 44, 44), mat = Enum.Material.Basalt },
	Eau = { couleur = Color3.fromRGB(70, 170, 255), tissu = Color3.fromRGB(22, 60, 120), pierre = Color3.fromRGB(176, 202, 222), mat = Enum.Material.Marble },
	Nature = { couleur = Color3.fromRGB(110, 220, 80), tissu = Color3.fromRGB(34, 86, 34), pierre = Color3.fromRGB(108, 112, 96), mat = Enum.Material.Slate },
	Foudre = { couleur = Color3.fromRGB(255, 220, 60), tissu = Color3.fromRGB(120, 96, 20), pierre = Color3.fromRGB(92, 98, 112), mat = Enum.Material.DiamondPlate },
	Ombre = { couleur = Color3.fromRGB(135, 60, 210), tissu = Color3.fromRGB(40, 20, 62), pierre = Color3.fromRGB(30, 26, 40), mat = Enum.Material.Basalt },
	Lumiere = { couleur = Color3.fromRGB(255, 236, 160), tissu = Color3.fromRGB(230, 222, 200), pierre = Color3.fromRGB(242, 238, 230), mat = Enum.Material.Marble },
}
-- Coins : Feu / Eau face à face, Nature / Foudre face à face ; milieux des longs côtés : Lumière / Ombre.
local PLACES_PILIERS = {
	{ "Feu", Vector3.new(HW - 0.4, 0, -(HL - 4)) },
	{ "Eau", Vector3.new(-(HW - 0.4), 0, HL - 4) },
	{ "Nature", Vector3.new(-(HW - 0.4), 0, -(HL - 4)) },
	{ "Foudre", Vector3.new(HW - 0.4, 0, HL - 4) },
	{ "Lumiere", Vector3.new(HW - 0.4, 0, 0) },
	{ "Ombre", Vector3.new(-(HW - 0.4), 0, 0) },
}

----------------------------------------------------------------------------------------------
-- Utilitaires (repère local de l'arène en cours)
----------------------------------------------------------------------------------------------

local origine = CFrame.new()
local nbParts = 0

local function part(parent: Instance, props): BasePart
	local p = Instance.new(props.Class or "Part")
	p.Name = props.Name or "Pierre"
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Size = props.Size
	p.CFrame = origine * props.CFrame
	p.Color = props.Color or PIERRE
	p.Material = props.Material or Enum.Material.Slate
	p.Transparency = props.Transparency or 0
	p.Parent = parent
	nbParts += 1
	return p
end

-- Décor : aucune collision, invisible aux raycasts, pas d'ombre s'il est petit
local function decorative(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	if math.max(p.Size.X, p.Size.Y, p.Size.Z) < 6 then
		p.CastShadow = false
	end
	return p
end
local function deco(parent: Instance, props): BasePart
	return decorative(part(parent, props))
end

local function vertical(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.pi / 2)
end

-- Cylindre vertical dont la base est en cfBase
local function cylindre(parent: Instance, cfBase: CFrame, d: number, h: number, props): BasePart
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(h, d, d)
	props.CFrame = vertical(cfBase * CFrame.new(0, h / 2, 0))
	return part(parent, props)
end

-- Segment plat entre deux points du sol (local)
local function trait(parent: Instance, a: Vector3, b: Vector3, largeur: number, epaisseur: number, props, fabrique)
	local cf = CFrame.lookAt((a + b) / 2, b)
	props.Size = Vector3.new(largeur, epaisseur, (b - a).Magnitude + largeur * 0.5)
	props.CFrame = cf
	return (fabrique or deco)(parent, props)
end

-- Anneau en segments dans le plan horizontal
local function anneau(parent: Instance, centre: CFrame, r: number, largeur: number, epaisseur: number, n: number, props, fabrique)
	local creer = fabrique or deco
	local longueur = 2 * r * math.sin(math.pi / n) + largeur * 0.2
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local p = Vector3.new(math.sin(a) * r, 0, -math.cos(a) * r)
		local copie = table.clone(props)
		copie.Size = Vector3.new(longueur, epaisseur, largeur)
		copie.CFrame = centre * CFrame.lookAt(p, p * 2)
		creer(parent, copie)
	end
end

local function lumiere(parent: Instance, couleur: Color3, portee: number, intensite: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = couleur
	l.Range = portee
	l.Brightness = intensite
	l.Shadows = false
	l.Parent = parent
	return l
end

local function feu(parent: Instance, couleur: Color3, couleur2: Color3, taille: number)
	local f = Instance.new("Fire")
	f.Color = couleur
	f.SecondaryColor = couleur2
	f.Size = taille
	f.Heat = 6
	f.Parent = parent
end

local function eclat(parent: Instance, couleur: Color3)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Eclat"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(couleur, Color3.new(1, 1, 1))
	e.LightEmission = 1
	e.Rate = 4
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.35, 0)
	e.Parent = parent
end

-- Texte gravé sur une face (enseigne)
local function inscription(p: BasePart, texte: string, couleur: Color3)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0.3
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = p
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.Fantasy
		t.TextScaled = true
		t.Text = texte
		t.TextColor3 = couleur
		t.Parent = gui
	end
end

----------------------------------------------------------------------------------------------
-- 1. Estrade et sol
----------------------------------------------------------------------------------------------

local function construireEstrade(m: Model): BasePart
	-- Socle enterré de 3 studs (absorbe le terrain), bord en granit sombre
	part(m, { Name = "Socle", Size = Vector3.new(DIM.Width + 2, FY + 2.9, DIM.Length + 2), CFrame = CFrame.new(0, (FY - 0.1 - 3) / 2, 0), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
	local sol = part(m, { Name = "Sol", Size = Vector3.new(DIM.Width - 1, 1, DIM.Length - 2), CFrame = CFrame.new(0, FY - 0.5, 0), Color = MARBRE, Material = Enum.Material.Marble })
	sol.CanQuery = true
	-- Liserés dorés au bord du dallage
	for _, s in { -1, 1 } do
		deco(m, { Name = "Liseré", Size = Vector3.new(0.3, 0.06, DIM.Length - 2), CFrame = CFrame.new(s * (DIM.Width / 2 - 0.5), FY + 0.02, 0), Color = OR, Material = Enum.Material.Metal })
		deco(m, { Name = "Liseré", Size = Vector3.new(DIM.Width - 1, 0.06, 0.3), CFrame = CFrame.new(0, FY + 0.02, s * (HL - 1)), Color = OR, Material = Enum.Material.Metal })
	end
	-- Dallage : larges bandes de marbre veiné en travers, tous les 6 studs
	for z = -36, 36, 6 do
		if math.abs(z) > 30 then
			deco(m, { Name = "Joint", Size = Vector3.new(DIM.Width - 2, 0.04, 0.25), CFrame = CFrame.new(0, FY + 0.02, z), Color = MARBRE_VEINE, Material = Enum.Material.Marble })
		end
	end
	for _, x in { -15.5, 15.5 } do
		deco(m, { Name = "Joint", Size = Vector3.new(0.25, 0.04, 60), CFrame = CFrame.new(x, FY + 0.02, 0), Color = MARBRE_VEINE, Material = Enum.Material.Marble })
	end
	-- Champ de duel : dalle d'ardoise sombre bordée d'or, sous les runes
	deco(m, { Name = "Bordure", Size = Vector3.new(27.6, 0.05, 61.6), CFrame = CFrame.new(0, FY + 0.03, 0), Color = OR, Material = Enum.Material.Metal })
	deco(m, { Name = "Champ", Size = Vector3.new(26.4, 0.06, 60.4), CFrame = CFrame.new(0, FY + 0.045, 0), Color = ARDOISE, Material = Enum.Material.Slate })
	-- Marches aux deux bouts (contremarches de 0,45 stud)
	local bout = HL + 1
	for _, s in { -1, 1 } do
		for k = 1, 3 do
			local top = FY - 0.1 - k * 0.45
			part(m, { Name = "Marche", Size = Vector3.new(14, top + 2, 1.6), CFrame = CFrame.new(0, (top - 2) / 2, s * (bout + (k - 0.5) * 1.6)), Color = PIERRE, Material = Enum.Material.Granite })
			deco(m, { Name = "Nez", Size = Vector3.new(14, 0.08, 0.2), CFrame = CFrame.new(0, top - 0.02, s * (bout + (k - 1) * 1.6 + 0.1)), Color = OR, Material = Enum.Material.Metal })
		end
	end
	return sol
end

----------------------------------------------------------------------------------------------
-- 2. Runes du champ de duel (dossier Runes : uniquement Neon violet)
----------------------------------------------------------------------------------------------

local function construireRunes(m: Model)
	local runes = Instance.new("Folder")
	runes.Name = "Runes"
	runes.Parent = m
	local Y = FY + 0.075 + 0.04
	local function rune(props)
		props.Name = props.Name or "Rune"
		props.Color = ARCANE
		props.Material = Enum.Material.Neon
		props.Transparency = 0.25
		return deco(runes, props)
	end
	local function ligne(a: Vector3, b: Vector3, l: number)
		return trait(runes, a, b, l, 0.08, {}, function(_, props)
			return rune(props)
		end)
	end
	local function cercle(c: Vector3, r: number, l: number, n: number)
		anneau(runes, CFrame.new(c), r, l, 0.08, n, {}, function(_, props)
			return rune(props)
		end)
	end
	-- Double cadre du champ
	local X1, Z1, X2, Z2 = 12.6, 29.6, 11.4, 28.4
	for _, c in { { X1, Z1, 0.35 }, { X2, Z2, 0.15 } } do
		local x, z, l = c[1], c[2], c[3]
		ligne(Vector3.new(-x, Y, -z), Vector3.new(x, Y, -z), l)
		ligne(Vector3.new(x, Y, -z), Vector3.new(x, Y, z), l)
		ligne(Vector3.new(x, Y, z), Vector3.new(-x, Y, z), l)
		ligne(Vector3.new(-x, Y, z), Vector3.new(-x, Y, -z), l)
	end
	-- Ligne médiane interrompue par le cercle central
	ligne(Vector3.new(-X2, Y, 0), Vector3.new(-6.4, Y, 0), 0.2)
	ligne(Vector3.new(6.4, Y, 0), Vector3.new(X2, Y, 0), 0.2)
	-- Cercle central, hexagramme et sceau
	cercle(Vector3.new(0, Y, 0), 6.4, 0.35, 32)
	cercle(Vector3.new(0, Y, 0), 5.2, 0.15, 28)
	for t = 0, 1 do
		for k = 0, 2 do
			local a1, a2 = math.rad(t * 60 + k * 120), math.rad(t * 60 + (k + 1) * 120)
			ligne(Vector3.new(math.sin(a1) * 5.2, Y, math.cos(a1) * 5.2), Vector3.new(math.sin(a2) * 5.2, Y, math.cos(a2) * 5.2), 0.18)
		end
	end
	local sceau = rune({ Name = "Sceau", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1.8, 1.8), CFrame = vertical(CFrame.new(0, Y + 0.01, 0)) })
	lumiere(sceau, ARCANE, 22, 1.2).Name = "Halo"
	-- Marques des duellistes (±20) et des Anima (±10)
	for _, s in { -1, 1 } do
		cercle(Vector3.new(0, Y, s * 20), 2.4, 0.25, 20)
		ligne(Vector3.new(-1.2, Y, s * 16.4), Vector3.new(0, Y, s * 15.2), 0.2)
		ligne(Vector3.new(1.2, Y, s * 16.4), Vector3.new(0, Y, s * 15.2), 0.2)
		local c = Vector3.new(0, Y, s * 10)
		for k = 0, 3 do
			local a1, a2 = math.rad(k * 90), math.rad((k + 1) * 90)
			ligne(c + Vector3.new(math.sin(a1) * 1.8, 0, math.cos(a1) * 1.8), c + Vector3.new(math.sin(a2) * 1.8, 0, math.cos(a2) * 1.8), 0.18)
		end
	end
	-- Glyphes le long des grands côtés, entre les deux cadres
	local function glyphe(c: Vector3, graine: number)
		local q = 1000 + graine * 97
		local function r()
			q = (q * 16807) % 2147483647
			return q / 2147483647
		end
		local P = { { 0, -0.9 }, { 0, 0.9 }, { -0.4, -0.5 }, { 0.4, -0.5 }, { -0.4, 0.3 }, { 0.4, 0.3 } }
		ligne(c + Vector3.new(0, 0, -0.9), c + Vector3.new(0, 0, 0.9), 0.12)
		local a, b = P[1 + math.floor(r() * 6)], P[1 + math.floor(r() * 6)]
		if a ~= b then
			ligne(c + Vector3.new(a[1], 0, a[2]), c + Vector3.new(b[1], 0, b[2]), 0.12)
		end
	end
	for i = 0, 8 do
		local z = -24 + i * 6
		if math.abs(z) > 3 then
			glyphe(Vector3.new(12, Y, z), i)
			glyphe(Vector3.new(-12, Y, z), i + 20)
		end
	end
	-- Écoinçons : losange dans chaque angle
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local c = Vector3.new(sx * 12, Y, sz * 29)
			for k = 0, 3 do
				local a1, a2 = math.rad(k * 90 + 45), math.rad((k + 1) * 90 + 45)
				ligne(c + Vector3.new(math.sin(a1) * 0.5, 0, math.cos(a1) * 0.5), c + Vector3.new(math.sin(a2) * 0.5, 0, math.cos(a2) * 0.5), 0.12)
			end
		end
	end
end

----------------------------------------------------------------------------------------------
-- 3. Parapets, braseros et bannières des grands côtés
----------------------------------------------------------------------------------------------

local function construireParapets(m: Model)
	local d = Instance.new("Folder")
	d.Name = "Parapets"
	d.Parent = m
	local H = 2.4
	local L = DIM.Length - 14 -- s'arrête avant les piliers d'angle
	for _, s in { -1, 1 } do
		local x = s * (HW - 0.4)
		part(d, { Name = "Mur", Size = Vector3.new(1.2, H, L), CFrame = CFrame.new(x, FY + H / 2, 0), Color = PIERRE, Material = Enum.Material.Granite })
		deco(d, { Name = "Plinthe", Size = Vector3.new(1.6, 0.4, L), CFrame = CFrame.new(x, FY + 0.2, 0), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
		deco(d, { Name = "Couvertine", Size = Vector3.new(1.7, 0.35, L + 0.4), CFrame = CFrame.new(x, FY + H + 0.17, 0), Color = MARBRE, Material = Enum.Material.Marble })
		deco(d, { Name = "Filet", Size = Vector3.new(1.74, 0.08, L + 0.4), CFrame = CFrame.new(x, FY + H - 0.02, 0), Color = OR, Material = Enum.Material.Metal })
		-- Panneaux sculptés côté extérieur
		for k = -3, 3 do
			if k ~= 0 then
				deco(d, { Name = "Panneau", Size = Vector3.new(0.12, 1.3, 7), CFrame = CFrame.new(x + s * 0.62, FY + 1.2, k * 9.2), Color = PIERRE_SOMBRE, Material = Enum.Material.Slate })
				deco(d, { Name = "Rosace", Size = Vector3.new(0.16, 0.5, 0.5), CFrame = CFrame.new(x + s * 0.66, FY + 1.2, k * 9.2) * CFrame.Angles(math.rad(45), 0, 0), Color = OR, Material = Enum.Material.Metal })
			end
		end
		-- Braseros posés sur le parapet, au quart de chaque côté
		for _, z in { -19, 19 } do
			local base = CFrame.new(x, FY + H + 0.35, z)
			deco(d, { Name = "Vasque", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 1.9, 1.9), CFrame = vertical(base * CFrame.new(0, 0.35, 0)), Color = Color3.fromRGB(46, 42, 50), Material = Enum.Material.Metal })
			deco(d, { Name = "Rebord", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 2.05, 2.05), CFrame = vertical(base * CFrame.new(0, 0.72, 0)), Color = OR, Material = Enum.Material.Metal })
			local braises = deco(d, { Name = "Braises", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1.6, 1.6), CFrame = vertical(base * CFrame.new(0, 0.66, 0)), Color = ARCANE, Material = Enum.Material.CrackedLava })
			feu(braises, ARCANE, Color3.fromRGB(230, 205, 255), 2.5)
			lumiere(braises, Color3.fromRGB(175, 135, 255), 14, 1.2)
		end
	end
end

local function banniere(parent: Instance, cf: CFrame, tissu: Color3, embleme: Color3)
	deco(parent, { Name = "Tringle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 0.2, 0.2), CFrame = cf, Color = OR, Material = Enum.Material.Metal })
	deco(parent, { Name = "Tissu", Size = Vector3.new(2.8, 6, 0.12), CFrame = cf * CFrame.new(0, -3, 0), Color = tissu, Material = Enum.Material.Fabric })
	deco(parent, { Name = "Pointe", Class = "WedgePart", Size = Vector3.new(0.12, 0.9, 1.4), CFrame = cf * CFrame.new(-0.7, -6.45, 0) * CFrame.Angles(0, math.rad(90), math.rad(180)), Color = tissu, Material = Enum.Material.Fabric })
	deco(parent, { Name = "Pointe", Class = "WedgePart", Size = Vector3.new(0.12, 0.9, 1.4), CFrame = cf * CFrame.new(0.7, -6.45, 0) * CFrame.Angles(0, math.rad(-90), math.rad(180)), Color = tissu, Material = Enum.Material.Fabric })
	deco(parent, { Name = "Embleme", Size = Vector3.new(0.9, 0.9, 0.16), CFrame = cf * CFrame.new(0, -2.6, 0) * CFrame.Angles(0, 0, math.rad(45)), Color = embleme, Material = Enum.Material.Neon })
	deco(parent, { Name = "Galon", Size = Vector3.new(2.8, 0.2, 0.16), CFrame = cf * CFrame.new(0, -0.35, 0), Color = OR, Material = Enum.Material.Metal })
end

----------------------------------------------------------------------------------------------
-- 4. Piliers élémentaires (cristal serti, fixe)
----------------------------------------------------------------------------------------------

local function construirePiliers(m: Model)
	local dossier = Instance.new("Folder")
	dossier.Name = "Piliers"
	dossier.Parent = m
	for _, def in PLACES_PILIERS do
		local nom, pos = def[1], def[2]
		local el = ELEMENTS[nom]
		local pm = Instance.new("Model")
		pm.Name = nom
		pm:SetAttribute("Element", nom)
		-- Repère du pilier : base sur le dallage, tourné vers le centre de l'arène
		local cf = CFrame.lookAt(Vector3.new(pos.X, FY, pos.Z), Vector3.new(0, FY, pos.Z)) -- face au champ, aligné sur l'arène
		part(pm, { Name = "Base", Size = Vector3.new(3.6, 1.2, 3.6), CFrame = cf * CFrame.new(0, 0.6, 0), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
		deco(pm, { Name = "Bande", Size = Vector3.new(3.1, 0.25, 3.1), CFrame = cf * CFrame.new(0, 1.32, 0), Color = OR, Material = Enum.Material.Metal })
		part(pm, { Name = "Fut", Size = Vector3.new(2.4, 8.4, 2.4), CFrame = cf * CFrame.new(0, 5.6, 0), Color = el.pierre, Material = el.mat })
		for _, y in { 3.2, 8.4 } do
			deco(pm, { Name = "Bague", Size = Vector3.new(2.6, 0.22, 2.6), CFrame = cf * CFrame.new(0, y, 0), Color = OR, Material = Enum.Material.Metal })
		end
		-- Incrustation lumineuse de l'élément sur la face avant
		deco(pm, { Name = "Veine", Size = Vector3.new(0.35, 4.4, 0.1), CFrame = cf * CFrame.new(0, 5.8, -1.22), Color = el.couleur, Material = Enum.Material.Neon, Transparency = 0.1 })
		deco(pm, { Name = "Sigle", Size = Vector3.new(0.9, 0.9, 0.1), CFrame = cf * CFrame.new(0, 5.8, -1.24) * CFrame.Angles(0, 0, math.rad(45)), Color = el.couleur, Material = Enum.Material.Neon })
		part(pm, { Name = "Chapiteau", Size = Vector3.new(3.2, 0.8, 3.2), CFrame = cf * CFrame.new(0, 10.2, 0), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
		deco(pm, { Name = "Coupe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 2.2, 2.2), CFrame = vertical(cf * CFrame.new(0, 10.85, 0)), Color = OR, Material = Enum.Material.Metal })
		-- Griffes dorées qui tiennent le cristal (rien ne flotte)
		for k = 0, 3 do
			local a = math.rad(k * 90 + 45)
			local c = cf * CFrame.new(math.cos(a) * 0.75, 11.6, math.sin(a) * 0.75) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-14))
			deco(pm, { Name = "Griffe", Size = Vector3.new(0.18, 1.6, 0.18), CFrame = c, Color = OR_CLAIR, Material = Enum.Material.Metal })
		end
		local cristal = deco(pm, {
			Name = "Cristal",
			Size = Vector3.new(1.3, 2.6, 1.3),
			CFrame = cf * CFrame.new(0, 12.15, 0) * CFrame.Angles(0, math.rad(45), 0),
			Color = el.couleur,
			Material = Enum.Material.Glass,
			Transparency = 0.15,
		})
		lumiere(cristal, el.couleur, 16, 1.5)
		eclat(cristal, el.couleur)
		-- Signature de l'élément au pied ou au sommet
		if nom == "Feu" then
			deco(pm, { Name = "Lave", Size = Vector3.new(3.9, 0.1, 3.9), CFrame = cf * CFrame.new(0, 0.05, 0), Color = Color3.fromRGB(255, 96, 32), Material = Enum.Material.CrackedLava })
		elseif nom == "Eau" then
			deco(pm, { Name = "Cascade", Size = Vector3.new(0.9, 7.4, 0.1), CFrame = cf * CFrame.new(0, 5.6, -1.28), Color = Color3.fromRGB(130, 200, 255), Material = Enum.Material.Glass, Transparency = 0.5 })
		elseif nom == "Nature" then
			deco(pm, { Name = "Mousse", Size = Vector3.new(3.3, 0.35, 3.3), CFrame = cf * CFrame.new(0, 10.65, 0), Color = Color3.fromRGB(78, 128, 58), Material = Enum.Material.LeafyGrass })
		elseif nom == "Foudre" then
			for _, y in { 4.6, 5.6, 6.6, 7.6 } do
				deco(pm, { Name = "Bobine", Size = Vector3.new(2.55, 0.15, 2.55), CFrame = cf * CFrame.new(0, y, 0), Color = Color3.fromRGB(196, 116, 62), Material = Enum.Material.Metal })
			end
		elseif nom == "Ombre" then
			deco(pm, { Name = "Joint", Size = Vector3.new(2.5, 0.1, 2.5), CFrame = cf * CFrame.new(0, 5.6, 0) * CFrame.Angles(0, math.rad(45), 0), Color = el.couleur, Material = Enum.Material.Neon })
		elseif nom == "Lumiere" then
			deco(pm, { Name = "Aureole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 3.6, 3.6), CFrame = cf * CFrame.new(0, 12.15, 0.9) * CFrame.Angles(0, math.rad(90), 0), Color = OR_CLAIR, Material = Enum.Material.Foil, Transparency = 0.2 })
		end
		pm.WorldPivot = origine * cf
		pm.Parent = dossier
		-- Bannière de l'élément sur le parapet (piliers du milieu) ou sur la face extérieure du pilier
		local dehors = Vector3.new(math.sign(pos.X), 0, 0)
		local haut = Vector3.new(pos.X, FY + 9.6, pos.Z) + dehors * 1.35
		banniere(m, CFrame.lookAt(haut, haut + dehors), el.tissu, el.couleur)
	end
end

----------------------------------------------------------------------------------------------
-- 5. Portes aux deux bouts (ouvertes : les duellistes y entrent à pied)
----------------------------------------------------------------------------------------------

local function construirePortes(m: Model)
	local d = Instance.new("Folder")
	d.Name = "Portes"
	d.Parent = m
	for _, s in { -1, 1 } do
		local z = s * (HL - 0.8)
		for _, x in { -6.2, 6.2 } do
			part(d, { Name = "Montant", Size = Vector3.new(1.8, 10.4, 1.8), CFrame = CFrame.new(x, FY + 5.2, z), Color = MARBRE, Material = Enum.Material.Marble })
			deco(d, { Name = "Base", Size = Vector3.new(2.3, 0.8, 2.3), CFrame = CFrame.new(x, FY + 0.4, z), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
			deco(d, { Name = "Bague", Size = Vector3.new(2, 0.25, 2), CFrame = CFrame.new(x, FY + 8.6, z), Color = OR, Material = Enum.Material.Metal })
			-- Lanterne suspendue côté arène
			local lanterne = deco(d, { Name = "Lanterne", Size = Vector3.new(0.7, 1, 0.7), CFrame = CFrame.new(x, FY + 7, z - s * 1.25), Color = Color3.fromRGB(205, 185, 255), Material = Enum.Material.Neon })
			lumiere(lanterne, Color3.fromRGB(190, 160, 255), 14, 1)
			deco(d, { Name = "Potence", Size = Vector3.new(0.15, 0.15, 1), CFrame = CFrame.new(x, FY + 7.7, z - s * 0.9), Color = OR, Material = Enum.Material.Metal })
		end
		deco(d, { Name = "Linteau", Size = Vector3.new(15, 1.6, 2.2), CFrame = CFrame.new(0, FY + 11.2, z), Color = MARBRE, Material = Enum.Material.Marble })
		deco(d, { Name = "Corniche", Size = Vector3.new(15.8, 0.5, 2.6), CFrame = CFrame.new(0, FY + 12.25, z), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
		deco(d, { Name = "Frise", Size = Vector3.new(15, 0.22, 2.3), CFrame = CFrame.new(0, FY + 10.5, z), Color = OR, Material = Enum.Material.Metal })
		local cle = deco(d, { Name = "Clef", Size = Vector3.new(1.3, 1.3, 0.3), CFrame = CFrame.new(0, FY + 11.2, z + s * 1.15) * CFrame.Angles(0, 0, math.rad(45)), Color = ARCANE, Material = Enum.Material.Neon })
		cle.CastShadow = false
		deco(d, { Name = "Clef", Size = Vector3.new(1.3, 1.3, 0.3), CFrame = CFrame.new(0, FY + 11.2, z - s * 1.15) * CFrame.Angles(0, 0, math.rad(45)), Color = ARCANE, Material = Enum.Material.Neon })
	end
end

----------------------------------------------------------------------------------------------
-- Une arène
----------------------------------------------------------------------------------------------

local function v3(v: Vector2, y: number): Vector3
	return Vector3.new(v.X, y, v.Y)
end

function ArenaBuilder.buildArena(slot, parent: Instance, groundY: number): Model
	local c = v3(slot.Center, groundY)
	-- -Z local = vers l'entrée de la zone ; Z local = axe des duellistes
	origine = CFrame.lookAt(c, c + v3(slot.Gate, 0))
	local m = Instance.new("Model")
	m.Name = slot.Id
	m:SetAttribute("ArenaId", slot.Id)
	m:SetAttribute("Zone", slot.Zone)
	construireEstrade(m)
	construireRunes(m)
	construireParapets(m)
	construirePiliers(m)
	construirePortes(m)
	m.WorldPivot = CFrame.new(c)
	m:SetAttribute("FloorY", groundY + FY)
	m.Parent = parent
	return m
end

----------------------------------------------------------------------------------------------
-- Habillage d'une zone : estrade de Varek, enseigne, étendards au fond
----------------------------------------------------------------------------------------------

function ArenaBuilder.buildZone(zone, parent: Instance, groundY: number): Model
	local c = v3(zone.Center, groundY)
	origine = CFrame.lookAt(c, c + v3(zone.Gate, 0))
	local m = Instance.new("Model")
	m.Name = "Zone" .. zone.Id
	local front = -(HL + 10) -- devant les marches des arènes
	-- Estrade ronde de Varek
	cylindre(m, CFrame.new(0, -1, front), 9, 1.6, { Name = "Estrade", Color = PIERRE, Material = Enum.Material.Granite })
	decorative(cylindre(m, CFrame.new(0, 0.5, front), 9.4, 0.15, { Name = "Liseré", Color = OR, Material = Enum.Material.Metal }))
	-- Grand panneau « Arènes des Champions » sur deux colonnes, au-dessus de l'allée
	for _, x in { -9, 9 } do
		part(m, { Name = "Colonne", Size = Vector3.new(1.6, 12, 1.6), CFrame = CFrame.new(x, 6, front + 4), Color = MARBRE, Material = Enum.Material.Marble })
		deco(m, { Name = "Bague", Size = Vector3.new(1.8, 0.25, 1.8), CFrame = CFrame.new(x, 10, front + 4), Color = OR, Material = Enum.Material.Metal })
		local gemme = deco(m, { Name = "Gemme", Size = Vector3.new(1.2, 1.2, 1.2), CFrame = CFrame.new(x, 12.9, front + 4) * CFrame.Angles(math.rad(45), 0, math.rad(35.26)), Color = ARCANE, Material = Enum.Material.Neon })
		lumiere(gemme, ARCANE, 16, 1.2)
	end
	local panneau = deco(m, { Name = "Enseigne", Size = Vector3.new(17, 2.4, 0.4), CFrame = CFrame.new(0, 10.8, front + 4), Color = Color3.fromRGB(62, 40, 112), Material = Enum.Material.Fabric })
	inscription(panneau, "ARÈNES DES CHAMPIONS", OR_CLAIR)
	deco(m, { Name = "Cadre", Size = Vector3.new(17.4, 0.25, 0.5), CFrame = CFrame.new(0, 12.1, front + 4), Color = OR, Material = Enum.Material.Metal })
	deco(m, { Name = "Cadre", Size = Vector3.new(17.4, 0.25, 0.5), CFrame = CFrame.new(0, 9.5, front + 4), Color = OR, Material = Enum.Material.Metal })
	-- Numéros des arènes devant chaque entrée
	for i = 1, 3 do
		local x = (i - 2) * DIM.Spacing -- même ordre que VillageData.arenaSlots (X local = travers)
		local borne = part(m, { Name = "Borne", Size = Vector3.new(2.4, 3.2, 0.8), CFrame = CFrame.new(x + 9.5, 1.6, -(HL + 5)), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
		inscription(borne, zone.Id .. " " .. i, OR_CLAIR)
	end
	-- Étendards au fond de la zone, derrière les arènes
	-- Entre les arènes et aux deux bords de la zone.
	local positions = { -(DIM.Spacing + DIM.Width / 2 + 8), -DIM.Spacing / 2, DIM.Spacing / 2, DIM.Spacing + DIM.Width / 2 + 8 }
	for i = -2, 1 do
		local x = positions[i + 3]
		local base = CFrame.new(x, 0, HL + 9)
		part(m, { Name = "Socle", Size = Vector3.new(2.2, 1.2, 2.2), CFrame = base * CFrame.new(0, 0.6, 0), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
		part(m, { Name = "Mat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(16, 0.45, 0.45), CFrame = vertical(base * CFrame.new(0, 8.6, 0)), Color = OR, Material = Enum.Material.Metal })
		local noms = { "Feu", "Eau", "Nature", "Foudre", "Ombre", "Lumiere" }
		local el = ELEMENTS[noms[(i + 2) % 6 + 1 + (zone.Id == "Ouest" and 2 or 0)]]
		banniere(m, CFrame.lookAt(base.Position + Vector3.new(0, 15.6, -0.3), base.Position + Vector3.new(0, 15.6, -2)), el.tissu, el.couleur)
	end
	m.WorldPivot = CFrame.new(c)
	m.Parent = parent
	return m
end

-- Construit tout : workspace.World.Arenes (zones + six arènes)
function ArenaBuilder.build(world: Instance, groundY: number): Folder
	local ancien = world:FindFirstChild("Arenes")
	if ancien then
		ancien:Destroy()
	end
	nbParts = 0
	local dossier = Instance.new("Folder")
	dossier.Name = "Arenes"
	for _, zone in VillageData.arenaZones() do
		ArenaBuilder.buildZone(zone, dossier, groundY)
	end
	for _, slot in VillageData.arenaSlots() do
		ArenaBuilder.buildArena(slot, dossier, groundY)
	end
	dossier:SetAttribute("PartCount", nbParts)
	dossier.Parent = world
	return dossier
end

return ArenaBuilder
