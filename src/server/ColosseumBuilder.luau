--!nonstrict
--[[
	ColosseumBuilder : « Le Cercle des Arcanes » (Arcana Bestia, cité de Brumeval)

	Construit l'arène de duel complète, entièrement par script (aucune modif manuelle
	dans Studio, aucun asset externe). Appelé par buildColosseum() dans World.server.luau.

	Contrat avec le code existant (ne pas casser) :
	  • Model "Colosseum" dans workspace.World, centré sur Layout.Colosseum
	  • Colosseum.Runes           : UNIQUEMENT des BasePart Neon violet (150,110,255), Transparency 0.25
	                                (Arena3D:lightCircle). Le sceau central porte un PointLight.
	  • Colosseum.Piliers.<Elem>  : Model + attribut Element, enfant "Cristal" (PointLight + ParticleEmitter
	                                "Eclat", attribut Floating = true) (Arena3D:lightPillars)
	  • Colosseum.PierresRuniques : pierres en lévitation (CircleFX)
	  • Sol central plat, CanQuery = true, dégagé sur 26 studs minimum autour du centre
	  • Rien ne dépasse ColosseumRadius + 8

	Repère interne : tout est construit dans un repère local dont l'origine est le centre de
	l'arène au niveau du sol extérieur, et dont l'axe -Z pointe vers l'entrée (ColosseumGate).
	Les angles « theta » sont en degrés, mesurés depuis l'entrée (0 = entrée, 90 / 270 = axe
	des duellistes, 180 = fond de l'arène).
]]

local ColosseumBuilder = {}

----------------------------------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------------------------------

local ARCANE = Color3.fromRGB(150, 110, 255) -- couleur imposée des runes (lightCircle)
local RUNE_TRANSPARENCE = 0.25

local OR = Color3.fromRGB(214, 172, 74)
local OR_CLAIR = Color3.fromRGB(247, 216, 128)
local CUIVRE = Color3.fromRGB(196, 116, 62)
local MARBRE = Color3.fromRGB(228, 223, 213)
local MARBRE_VEINE = Color3.fromRGB(176, 166, 154)
local PIERRE = Color3.fromRGB(150, 142, 132)
local PIERRE_SOMBRE = Color3.fromRGB(82, 78, 92)
local ARDOISE = Color3.fromRGB(34, 30, 48)
local BOIS = Color3.fromRGB(96, 70, 48)

-- Couleur et tissu (bannières) de chaque élément
local ELEMENTS = {
	Feu = { couleur = Color3.fromRGB(255, 110, 40), tissu = Color3.fromRGB(120, 30, 18) },
	Eau = { couleur = Color3.fromRGB(70, 170, 255), tissu = Color3.fromRGB(22, 60, 120) },
	Nature = { couleur = Color3.fromRGB(110, 220, 80), tissu = Color3.fromRGB(34, 86, 34) },
	Foudre = { couleur = Color3.fromRGB(255, 220, 60), tissu = Color3.fromRGB(120, 96, 20) },
	Ombre = { couleur = Color3.fromRGB(135, 60, 210), tissu = Color3.fromRGB(40, 20, 62) },
	Lumiere = { couleur = Color3.fromRGB(255, 236, 160), tissu = Color3.fromRGB(230, 222, 200) },
}

-- Ordre autour du cercle (pilier i à theta = 30 + 60*i). Les éléments opposés se font face :
-- Lumiere/Ombre, Feu/Eau, Nature/Foudre. Feu et Eau sont derrière les duellistes (theta 90 / 270).
local ORDRE_PILIERS = { "Lumiere", "Feu", "Nature", "Ombre", "Eau", "Foudre" }

----------------------------------------------------------------------------------------------
-- État de construction (une seule construction à la fois)
----------------------------------------------------------------------------------------------

local origine = CFrame.new() -- repère local -> monde
local nbParts = 0
local aleaGraine = 1

-- Générateur pseudo-aléatoire déterministe : même arène à chaque démarrage
local function alea(min: number, max: number): number
	aleaGraine = (aleaGraine * 16807) % 2147483647
	return min + (max - min) * (aleaGraine / 2147483647)
end

----------------------------------------------------------------------------------------------
-- Utilitaires géométriques (repère local)
----------------------------------------------------------------------------------------------

-- Position à un angle theta (degrés depuis l'entrée), un rayon r et une hauteur y
local function at(theta: number, r: number, y: number): Vector3
	local a = math.rad(theta)
	return Vector3.new(math.sin(a) * r, y, -math.cos(a) * r)
end

-- CFrame tournée vers l'extérieur (LookVector radial sortant, RightVector tangent)
local function facing(theta: number, r: number, y: number): CFrame
	local p = at(theta, r, y)
	return CFrame.lookAt(p, p + at(theta, 1, 0))
end

-- CFrame tournée vers le centre
local function facingIn(theta: number, r: number, y: number): CFrame
	return facing(theta, r, y) * CFrame.Angles(0, math.pi, 0)
end

-- Fait passer l'axe d'un cylindre (X par défaut) à la verticale
local function vertical(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.pi / 2)
end

-- CFrame au milieu d'un segment a -> b (axe Z le long du segment) et sa longueur
local function between(a: Vector3, b: Vector3): (CFrame, number)
	local dir = b - a
	local up = if math.abs(dir.Unit.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt((a + b) / 2, b, up), dir.Magnitude
end

----------------------------------------------------------------------------------------------
-- Fabrique de parts
----------------------------------------------------------------------------------------------

-- props : Name, Size, CFrame (LOCAL), Color, Material, Shape, Transparency, Class, Reflectance
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
	if props.Reflectance then
		p.Reflectance = props.Reflectance
	end
	p.Parent = parent
	nbParts += 1
	return p
end

-- Rend une part purement décorative (aucune collision, invisible aux raycasts)
local function decorative(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	local s = p.Size
	if math.max(s.X, s.Y, s.Z) < 6 then
		p.CastShadow = false
	end
	return p
end

local function deco(parent: Instance, props): BasePart
	return decorative(part(parent, props))
end

-- Cylindre vertical dont la BASE est en cfBase
local function cylindre(parent: Instance, cfBase: CFrame, diametre: number, hauteur: number, props): BasePart
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(hauteur, diametre, diametre)
	props.CFrame = vertical(cfBase * CFrame.new(0, hauteur / 2, 0))
	return part(parent, props)
end

-- Disque fin posé au sol, dont le DESSUS est à la hauteur y
local function disque(parent: Instance, diametre: number, epaisseur: number, y: number, props, base: CFrame?): BasePart
	local cf = (base or CFrame.new()) * CFrame.new(0, y - epaisseur, 0)
	return decorative(cylindre(parent, cf, diametre, epaisseur, props))
end

-- Tige entre deux points (bloc ou cylindre)
local function tige(parent: Instance, a: Vector3, b: Vector3, d: number, props, rond: boolean?): BasePart
	local cf, l = between(a, b)
	if rond then
		props.Shape = Enum.PartType.Cylinder
		props.Size = Vector3.new(l + d * 0.3, d, d)
		props.CFrame = cf * CFrame.Angles(0, math.pi / 2, 0)
	else
		props.Size = Vector3.new(d, d, l + d * 0.3)
		props.CFrame = cf
	end
	return part(parent, props)
end

-- Anneau en segments dans le plan XZ de « centre » (repère local)
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

----------------------------------------------------------------------------------------------
-- Effets (lumières, particules)
----------------------------------------------------------------------------------------------

local function lumiere(parent: Instance, couleur: Color3, portee: number, intensite: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = couleur
	l.Range = portee
	l.Brightness = intensite
	l.Shadows = false
	l.Parent = parent
	return l
end

local TEX_ETINCELLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_FUMEE = "rbxasset://textures/particles/smoke_main.dds"

-- props : Rate, Lifetime {min,max}, Speed {min,max}, Size {debut,fin}, Transparence {debut,fin},
--         Couleur, Couleur2, Texture, Spread, Accel, Direction, LightEmission, Drag, Rotation
local function particules(parent: Instance, nom: string, props): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = nom
	e.Texture = props.Texture or TEX_ETINCELLE
	e.Rate = props.Rate or 5
	e.Lifetime = NumberRange.new(props.Lifetime[1], props.Lifetime[2])
	e.Speed = NumberRange.new(props.Speed[1], props.Speed[2])
	e.Size = NumberSequence.new(props.Size[1], props.Size[2])
	local t = props.Transparence or { 0.2, 1 }
	e.Transparency = NumberSequence.new(t[1], t[2])
	e.Color = ColorSequence.new(props.Couleur, props.Couleur2 or props.Couleur)
	e.LightEmission = props.LightEmission or 1
	e.LightInfluence = props.LightInfluence or 0
	e.SpreadAngle = props.Spread or Vector2.new(180, 180)
	e.Acceleration = props.Accel or Vector3.zero
	e.EmissionDirection = props.Direction or Enum.NormalId.Top
	e.Drag = props.Drag or 0
	if props.Rotation then
		e.RotSpeed = NumberRange.new(-props.Rotation, props.Rotation)
		e.Rotation = NumberRange.new(0, 360)
	end
	e.Parent = parent
	return e
end

-- Part invisible servant uniquement de zone d'émission
local function zoneEmission(parent: Instance, nom: string, cf: CFrame, taille: Vector3): BasePart
	return deco(parent, { Name = nom, Size = taille, CFrame = cf, Transparency = 1, Material = Enum.Material.SmoothPlastic })
end

local function feu(parent: Instance, couleur: Color3, couleur2: Color3, taille: number, chaleur: number)
	local f = Instance.new("Fire")
	f.Color = couleur
	f.SecondaryColor = couleur2
	f.Size = taille
	f.Heat = chaleur
	f.Parent = parent
	return f
end

----------------------------------------------------------------------------------------------
-- Dimensions (calculées depuis Layout.ColosseumRadius)
----------------------------------------------------------------------------------------------

local Dim = {} :: any

local function calculerDimensions(rayon: number, circleScale: number)
	Dim.R = rayon -- 72 par défaut
	Dim.LIMITE = rayon + 8 -- rien ne dépasse
	Dim.SOL_Y = 3 -- dessus du sol de combat (au-dessus du sol extérieur)
	Dim.SOL_R = rayon - 20 -- estrade principale (52)
	Dim.MARCHE_R = rayon - 15 -- marche intermédiaire (57)
	Dim.SOCLE_R = rayon - 10 -- socle extérieur (62)
	-- Piliers à 44 : plinthe à partir de 39.5, les duellistes entrent à pied depuis 36 (Arena3D)
	Dim.PILIER_R = Dim.SOL_R - 8
	Dim.CERCLE_R = 22 * circleScale -- grand cercle magique (33, même taille qu'avant)
	Dim.ARDOISE_R = Dim.CERCLE_R + 2.5 -- disque sombre sous le cercle
	Dim.GRADIN_R = rayon - 8 -- début des gradins (64)
	Dim.PORTIQUE_R = rayon - 3 -- arches en ruine (69)
	Dim.ENTREE_DEMI_ANGLE = 22 -- ouverture des gradins côté entrée
	assert(Dim.SOL_R >= Dim.CERCLE_R + 8, "ColosseumRadius trop petit pour CIRCLE_SCALE")
	assert(Dim.CERCLE_R >= 26, "le cercle doit couvrir la zone de combat (26 studs)")
end

----------------------------------------------------------------------------------------------
-- 1. Estrade : socle, marches, dallage de marbre, bordures dorées
----------------------------------------------------------------------------------------------

local function construireEstrade(modele: Model): BasePart
	local Y = Dim.SOL_Y
	local estrade = Instance.new("Folder")
	estrade.Name = "Estrade"
	estrade.Parent = modele

	-- Trois niveaux enterrés de 4 studs pour absorber les irrégularités du terrain
	local niveaux = {
		{ nom = "Socle", r = Dim.SOCLE_R, haut = 1, couleur = PIERRE_SOMBRE, mat = Enum.Material.Slate },
		{ nom = "Marche", r = Dim.MARCHE_R, haut = 2, couleur = PIERRE, mat = Enum.Material.Granite },
		{ nom = "Sol", r = Dim.SOL_R, haut = Y, couleur = MARBRE, mat = Enum.Material.Marble },
	}
	local sol
	for _, n in niveaux do
		local h = n.haut + 4
		local p = cylindre(estrade, CFrame.new(0, -4, 0), n.r * 2, h, { Name = n.nom, Color = n.couleur, Material = n.mat })
		p.CanQuery = true
		p.CanCollide = true
		-- Bandeau doré ouvragé sur la contremarche
		local bande = cylindre(estrade, CFrame.new(0, n.haut - 0.55, 0), n.r * 2 + 0.3, 0.35, {
			Name = "BandeauDore",
			Color = OR,
			Material = Enum.Material.Metal,
		})
		decorative(bande)
		if n.nom == "Sol" then
			sol = p
		end
	end

	-- Dallage : couches très fines (aucune collision) superposées pour dessiner les motifs
	local dallage = Instance.new("Folder")
	dallage.Name = "Dallage"
	dallage.Parent = modele
	disque(dallage, (Dim.SOL_R - 3.5) * 2, 0.06, Y + 0.02, { Name = "AnneauVeine", Color = MARBRE_VEINE, Material = Enum.Material.Marble })
	disque(dallage, (Dim.SOL_R - 4.6) * 2, 0.06, Y + 0.03, { Name = "Marbre", Color = MARBRE, Material = Enum.Material.Marble })
	disque(dallage, (Dim.ARDOISE_R + 1.6) * 2, 0.06, Y + 0.04, { Name = "AnneauDore", Color = OR, Material = Enum.Material.Metal })
	disque(dallage, Dim.ARDOISE_R * 2, 0.06, Y + 0.05, { Name = "Ardoise", Color = ARDOISE, Material = Enum.Material.Slate })

	-- Rayons de marbre veiné et losanges dorés entre le cercle et les piliers
	local r1, r2 = Dim.ARDOISE_R + 2.4, Dim.SOL_R - 5.2
	for i = 0, 23 do
		local theta = i * 15
		local cf, l = between(at(theta, r1, Y + 0.05), at(theta, r2, Y + 0.05))
		if (theta - 30) % 60 ~= 0 then -- pas sous les piliers
			deco(dallage, { Name = "Rayon", Size = Vector3.new(0.45, 0.04, l), CFrame = cf, Color = MARBRE_VEINE, Material = Enum.Material.Marble })
		end
		local losange = facing(theta + 7.5, (r1 + r2) / 2, Y + 0.05) * CFrame.Angles(0, math.rad(45), 0)
		deco(dallage, { Name = "Losange", Size = Vector3.new(1.3, 0.04, 1.3), CFrame = losange, Color = OR_CLAIR, Material = Enum.Material.Metal })
	end
	-- Frise de dalles sur la marche et le socle (alternance de teintes)
	for i = 0, 35 do
		local theta = (i + 0.5) * 10
		local teinte = if i % 2 == 0 then Color3.fromRGB(128, 120, 112) else Color3.fromRGB(160, 152, 140)
		deco(dallage, {
			Name = "Dalle",
			Size = Vector3.new(2 * (Dim.MARCHE_R - 1) * math.sin(math.rad(5)) - 0.3, 0.04, 4.6),
			CFrame = facing(theta, Dim.MARCHE_R - 3, 2.02),
			Color = teinte,
			Material = Enum.Material.Granite,
		})
	end
	return sol
end

----------------------------------------------------------------------------------------------
-- 2. Cercle magique (dossier Runes : uniquement des BasePart Neon violet)
----------------------------------------------------------------------------------------------

local function rune(dossier: Instance, props): BasePart
	props.Name = props.Name or "Rune"
	props.Color = ARCANE
	props.Material = Enum.Material.Neon
	props.Transparency = RUNE_TRANSPARENCE
	return deco(dossier, props)
end

-- Glyphe runique procédural (hampe + 2 ou 3 traits), à plat au sol
local POINTS_GLYPHE = { { 0, -1 }, { 0, 1 }, { -0.65, -0.6 }, { 0.65, -0.6 }, { -0.65, 0.25 }, { 0.65, 0.25 }, { 0, 0 } }
local function glyphe(dossier: Instance, cf: CFrame, taille: number, graine: number)
	local q = 1000 + graine * 97
	local function r()
		q = (q * 16807) % 2147483647
		return q / 2147483647
	end
	local function p(pt)
		return Vector3.new(pt[1] * taille, 0, -pt[2] * taille)
	end
	local traits = { { POINTS_GLYPHE[1], POINTS_GLYPHE[2] } }
	for _ = 1, 2 + (if r() > 0.5 then 1 else 0) do
		local a = POINTS_GLYPHE[1 + math.floor(r() * 7)]
		local b = POINTS_GLYPHE[1 + math.floor(r() * 7)]
		if a ~= b then
			table.insert(traits, { a, b })
		end
	end
	for _, t in traits do
		local c, l = between(p(t[1]), p(t[2]))
		rune(dossier, { Size = Vector3.new(0.3, 0.12, l + 0.3), CFrame = cf * c })
	end
end

local function construireCercleMagique(modele: Model)
	local runes = Instance.new("Folder")
	runes.Name = "Runes"
	runes.Parent = modele

	local Y = Dim.SOL_Y + 0.05 + 0.06 -- posé sur le disque d'ardoise
	local centre = CFrame.new(0, Y, 0)
	local RC = Dim.CERCLE_R
	local function segments(r, largeur, n)
		anneau(runes, centre, r, largeur, 0.12, n, { Name = "Anneau" }, rune)
	end

	-- Couronne extérieure graduée
	segments(RC, 0.8, 52)
	segments(RC - 1.7, 0.3, 52)
	for i = 0, 47 do
		local cf = facing(i * 7.5, RC - 0.85, Y)
		rune(runes, { Name = "Graduation", Size = Vector3.new(0.22, 0.12, if i % 4 == 0 then 1.5 else 0.9), CFrame = cf })
	end

	-- Bande de glyphes entre la couronne et l'hexagramme
	local RH = RC * 0.64
	segments(RH, 0.5, 40)
	local rGlyphes = (RH + RC - 1.7) / 2
	for i = 0, 23 do
		glyphe(runes, facingIn(i * 15 + 7.5, rGlyphes, Y), 1.25, i)
	end

	-- Hexagramme : pointes sur l'axe des duellistes (theta 90 / 270)
	local function sommet(theta)
		return at(theta, RH, Y)
	end
	for t = 0, 1 do
		for k = 0, 2 do
			local a = 90 + t * 180 + k * 120
			local cf, l = between(sommet(a), sommet(a + 120))
			rune(runes, { Name = "Hexagramme", Size = Vector3.new(0.45, 0.12, l + 0.4), CFrame = cf })
		end
	end
	-- Médaillons aux six pointes
	for k = 0, 5 do
		local c = CFrame.new(sommet(90 + k * 60))
		anneau(runes, c, 1.6, 0.25, 0.12, 12, { Name = "Medaillon" }, rune)
		rune(runes, { Name = "Joyau", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 1.1, 1.1), CFrame = vertical(c) })
	end

	-- Anneau intérieur et sceau central
	segments(RC * 0.3, 0.4, 28)
	segments(4.4, 0.3, 20)
	for k = 0, 7 do
		local a = k * 45
		local cf, l = between(at(a, 3.6, Y), at(a + 135, 3.6, Y))
		rune(runes, { Name = "Etoile", Size = Vector3.new(0.25, 0.12, l), CFrame = cf })
	end
	local sceau = rune(runes, {
		Name = "Sceau",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.16, 2.6, 2.6),
		CFrame = vertical(CFrame.new(0, Y + 0.01, 0)),
	})
	-- Même réglage qu'avant : lightCircle le passe à 2 en combat puis le remet à 1.2
	lumiere(sceau, ARCANE, 26, 1.2).Name = "Halo"
	return runes
end

----------------------------------------------------------------------------------------------
-- 3. Piliers élémentaires
----------------------------------------------------------------------------------------------

-- Pièces communes : plinthe à deux degrés, cristal flottant, médaillon au sol
local function plinthe(m: Model, cf: CFrame, couleur: Color3, mat: Enum.Material, bande: Color3?, matBande: Enum.Material?)
	part(m, { Name = "Plinthe", Size = Vector3.new(9, 1.4, 9), CFrame = cf * CFrame.new(0, 0.7, 0), Color = couleur, Material = mat })
	deco(m, { Name = "Bande", Size = Vector3.new(7.8, 0.3, 7.8), CFrame = cf * CFrame.new(0, 1.55, 0), Color = bande or OR, Material = matBande or Enum.Material.Metal })
	part(m, { Name = "Plinthe", Size = Vector3.new(7.4, 1.1, 7.4), CFrame = cf * CFrame.new(0, 2.05, 0), Color = couleur, Material = mat })
end

-- Cristal flottant. Repos = Glass, Transparency 0.15, lumière 1.5 / 16 : ce sont les valeurs que
-- Arena3D:lightPillars remet après un duel. Il est droit car CircleFX le fait tourner autour de
-- son axe Y local. Le cœur et le halo sont des parts ENFANTS du cristal : CircleFX les déplace avec lui.
local function cristal(m: Model, cf: CFrame, y: number, couleur: Color3, halo: boolean): BasePart
	local base = cf * CFrame.new(0, y, 0)
	local c = deco(m, {
		Name = "Cristal",
		Size = Vector3.new(2.1, 3.8, 2.1),
		CFrame = base * CFrame.Angles(0, math.rad(45), 0),
		Color = couleur,
		Material = Enum.Material.Glass,
		Transparency = 0.15,
	})
	c:SetAttribute("Floating", true)
	lumiere(c, couleur, 16, 1.5)
	particules(c, "Eclat", {
		Rate = 4,
		Lifetime = { 1, 2 },
		Speed = { 0.5, 1.5 },
		Size = { 0.4, 0 },
		Couleur = couleur,
		Couleur2 = Color3.new(1, 1, 1),
	})
	-- Cœur lumineux : petit cube posé sur la pointe, toujours en Neon
	deco(c, {
		Name = "Coeur",
		Size = Vector3.new(1.25, 1.25, 1.25),
		CFrame = base * CFrame.Angles(math.rad(45), 0, math.rad(35.26)),
		Color = couleur,
		Material = Enum.Material.Neon,
	})
	if halo then
		anneau(c, base * CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(16), 0, 0), 2.7, 0.16, 0.16, 10, {
			Name = "Halo",
			Color = OR_CLAIR,
			Material = Enum.Material.Metal,
		})
	end
	return c
end

-- Gemme de l'élément sertie dans l'anneau doré, au pied de chaque pilier
local function gemmeAnneau(parent: Instance, theta: number, couleur: Color3)
	local cf = facing(theta, Dim.ARDOISE_R + 0.8, Dim.SOL_Y + 0.07) * CFrame.Angles(0, math.rad(45), 0)
	deco(parent, { Name = "Sertissure", Size = Vector3.new(2.1, 0.06, 2.1), CFrame = cf, Color = OR_CLAIR, Material = Enum.Material.Metal })
	deco(parent, { Name = "Gemme", Size = Vector3.new(1.4, 0.1, 1.4), CFrame = cf * CFrame.new(0, 0.03, 0), Color = couleur, Material = Enum.Material.Neon })
end

-- Point sur la surface d'un fût cylindrique (angle a autour du pilier, en degrés)
local function surface(cf: CFrame, a: number, r: number, y: number): Vector3
	local rad = math.rad(a)
	return (cf * CFrame.new(math.cos(rad) * r, y, math.sin(rad) * r)).Position
end

local Piliers = {}

-- FEU : pierre volcanique, veines de lave, brasier et cornes de basalte
function Piliers.Feu(m: Model, cf: CFrame, c: Color3)
	local basalte = Color3.fromRGB(46, 38, 38)
	disque(m, 13, 0.12, 0.14, { Name = "Lave", Color = Color3.fromRGB(255, 96, 32), Material = Enum.Material.CrackedLava }, cf)
	plinthe(m, cf, basalte, Enum.Material.Basalt, Color3.fromRGB(255, 96, 32), Enum.Material.CrackedLava)
	cylindre(m, cf * CFrame.new(0, 2.6, 0), 4.6, 14, { Name = "Fut", Color = Color3.fromRGB(56, 46, 44), Material = Enum.Material.Basalt })
	-- Veines de lave en zigzag
	for k = 0, 3 do
		local a0 = 45 + k * 90
		local prev = surface(cf, a0, 2.28, 3)
		for s = 1, 4 do
			local nxt = surface(cf, a0 + (if s % 2 == 0 then -9 else 9), 2.28, 3 + s * 3.3)
			decorative(tige(m, prev, nxt, 0.35, { Name = "Veine", Color = c, Material = Enum.Material.Neon }))
			prev = nxt
		end
	end
	-- Blocs volcaniques au pied
	for k = 0, 6 do
		local a = k * 51 + alea(-10, 10)
		local p = surface(cf, a, alea(5.3, 6.2), 0.4)
		deco(m, {
			Name = "Roche",
			Size = Vector3.new(alea(1.4, 2.6), alea(1.2, 2.4), alea(1.4, 2.6)),
			CFrame = CFrame.new(p) * CFrame.Angles(alea(-0.5, 0.5), alea(0, 6), alea(-0.5, 0.5)),
			Color = basalte,
			Material = Enum.Material.Basalt,
		})
	end
	-- Brasier sommital
	cylindre(m, cf * CFrame.new(0, 16.6, 0), 6, 1, { Name = "Chapiteau", Color = basalte, Material = Enum.Material.Basalt })
	decorative(cylindre(m, cf * CFrame.new(0, 17.6, 0), 7, 1.2, { Name = "Vasque", Color = Color3.fromRGB(40, 34, 34), Material = Enum.Material.Metal }))
	decorative(cylindre(m, cf * CFrame.new(0, 18.75, 0), 7.3, 0.25, { Name = "Rebord", Color = OR, Material = Enum.Material.Metal }))
	local braises = decorative(cylindre(m, cf * CFrame.new(0, 18.6, 0), 6.2, 0.4, { Name = "Braises", Color = Color3.fromRGB(255, 110, 40), Material = Enum.Material.CrackedLava }))
	feu(braises, Color3.fromRGB(255, 120, 40), Color3.fromRGB(255, 210, 90), 5, 9)
	particules(braises, "Braises", {
		Rate = 14,
		Lifetime = { 1.5, 3 },
		Speed = { 3, 6 },
		Size = { 0.25, 0 },
		Couleur = Color3.fromRGB(255, 170, 60),
		Couleur2 = Color3.fromRGB(255, 60, 20),
		Spread = Vector2.new(25, 25),
		Accel = Vector3.new(0, 2, 0),
	})
	-- Cornes d'obsidienne autour de la vasque
	for k = 0, 5 do
		local a = k * 60 + 30
		local base = surface(cf, a, 3.3, 18.6)
		local pointe = surface(cf, a, 4.4, 21.6)
		deco(m, { Name = "Corne", Size = Vector3.new(0.7, 0.7, 3.3), CFrame = (between(base, pointe)), Color = Color3.fromRGB(26, 20, 22), Material = Enum.Material.Basalt })
	end
	cristal(m, cf, 23.5, c, true)
end

-- EAU : marbre bleuté, bassin, cascade et cristaux de glace
function Piliers.Eau(m: Model, cf: CFrame, c: Color3)
	local marbreBleu = Color3.fromRGB(176, 202, 222)
	cylindre(m, cf, 13.4, 1.3, { Name = "Bassin", Color = Color3.fromRGB(120, 136, 152), Material = Enum.Material.Granite })
	disque(m, 12.4, 0.2, 1.35, { Name = "Eau", Color = Color3.fromRGB(60, 150, 230), Material = Enum.Material.Glass, Transparency = 0.35 }, cf)
	plinthe(m, cf * CFrame.new(0, 0.4, 0), marbreBleu, Enum.Material.Marble)
	cylindre(m, cf * CFrame.new(0, 3, 0), 4.4, 13.6, { Name = "Fut", Color = marbreBleu, Material = Enum.Material.Marble })
	for _, y in { 6, 10, 14 } do
		decorative(cylindre(m, cf * CFrame.new(0, y, 0), 4.7, 0.25, { Name = "Anneau", Color = c, Material = Enum.Material.Neon, Transparency = 0.1 }))
	end
	-- Cristaux de glace sur le rebord du bassin
	for k = 0, 7 do
		local a = k * 45 + alea(-12, 12)
		local base = surface(cf, a, alea(5.1, 6.1), 1.1)
		local h = alea(2, 4.8)
		local inclinaison = CFrame.Angles(0, -math.rad(a), 0) * CFrame.Angles(0, 0, math.rad(-alea(10, 28)))
		deco(m, {
			Name = "Glace",
			Size = Vector3.new(alea(0.8, 1.4), h, alea(0.8, 1.4)),
			CFrame = CFrame.new(base) * inclinaison * CFrame.new(0, h / 2, 0),
			Color = Color3.fromRGB(160, 220, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
		})
	end
	-- Chapiteau, bec doré et cascade (face au centre = -Z local)
	cylindre(m, cf * CFrame.new(0, 16.6, 0), 6.2, 1.2, { Name = "Chapiteau", Color = marbreBleu, Material = Enum.Material.Marble })
	decorative(cylindre(m, cf * CFrame.new(0, 17.8, 0), 6.5, 0.3, { Name = "Rebord", Color = OR, Material = Enum.Material.Metal }))
	local bec = deco(m, { Name = "Bec", Size = Vector3.new(1.6, 0.8, 1.6), CFrame = cf * CFrame.new(0, 17.1, -3.2), Color = OR, Material = Enum.Material.Metal })
	deco(m, { Name = "Cascade", Size = Vector3.new(2.6, 15.6, 0.25), CFrame = cf * CFrame.new(0, 9.35, -2.6), Color = Color3.fromRGB(110, 190, 255), Material = Enum.Material.Glass, Transparency = 0.45 })
	deco(m, { Name = "Cascade", Size = Vector3.new(1.1, 15.6, 0.1), CFrame = cf * CFrame.new(0, 9.35, -2.8), Color = Color3.fromRGB(190, 235, 255), Material = Enum.Material.Neon, Transparency = 0.7 })
	particules(bec, "Ruissellement", {
		Rate = 30,
		Lifetime = { 0.8, 1 },
		Speed = { 2, 4 },
		Size = { 0.35, 0.15 },
		Couleur = Color3.fromRGB(170, 220, 255),
		Spread = Vector2.new(8, 8),
		Accel = Vector3.new(0, -18, 0),
		Direction = Enum.NormalId.Bottom,
		LightEmission = 0.4,
	})
	local embruns = zoneEmission(m, "Embruns", cf * CFrame.new(0, 1.6, -3.4), Vector3.new(3, 0.2, 1.5))
	particules(embruns, "Embruns", {
		Texture = TEX_FUMEE,
		Rate = 6,
		Lifetime = { 1.5, 2.5 },
		Speed = { 0.5, 1.5 },
		Size = { 1, 3 },
		Transparence = { 0.6, 1 },
		Couleur = Color3.fromRGB(200, 235, 255),
		LightEmission = 0.3,
	})
	-- Éclats de cristal sur le chapiteau
	for k = 0, 3 do
		local a = k * 90 + 45
		local base = surface(cf, a, 2.3, 17.8)
		deco(m, {
			Name = "Glace",
			Size = Vector3.new(0.7, 2.6, 0.7),
			CFrame = CFrame.new(base) * CFrame.Angles(0, -math.rad(a), 0) * CFrame.Angles(0, 0, math.rad(-22)) * CFrame.new(0, 1.3, 0),
			Color = Color3.fromRGB(160, 220, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
		})
	end
	cristal(m, cf, 21.5, c, true)
end

-- NATURE : pierre moussue, racines, lianes, feuillages et champignons lumineux
function Piliers.Nature(m: Model, cf: CFrame, c: Color3)
	local vert = Color3.fromRGB(70, 140, 52)
	disque(m, 13.5, 0.15, 0.16, { Name = "Mousse", Color = Color3.fromRGB(78, 128, 58), Material = Enum.Material.Grass }, cf)
	plinthe(m, cf, Color3.fromRGB(104, 108, 92), Enum.Material.Slate)
	cylindre(m, cf * CFrame.new(0, 2.6, 0), 4.4, 14, { Name = "Fut", Color = Color3.fromRGB(112, 116, 100), Material = Enum.Material.Slate })
	-- Racines qui s'étalent sur le dallage
	for k = 0, 6 do
		local a = k * 51.4 + alea(-8, 8)
		local p1 = surface(cf, a, 2, 4.2)
		local p2 = surface(cf, a + 6, 4.3, 1.9)
		local p3 = surface(cf, a + 12, 6.6, 0.3)
		decorative(tige(m, p1, p2, 0.95, { Name = "Racine", Color = BOIS, Material = Enum.Material.Wood }, true))
		decorative(tige(m, p2, p3, 0.7, { Name = "Racine", Color = BOIS, Material = Enum.Material.Wood }, true))
	end
	-- Deux lianes en spirale
	for v = 0, 1 do
		local prev = surface(cf, v * 180, 2.35, 2.8)
		for s = 1, 10 do
			local nxt = surface(cf, v * 180 + s * 40, 2.35, 2.8 + s * 1.4)
			decorative(tige(m, prev, nxt, 0.35, { Name = "Liane", Color = vert, Material = Enum.Material.LeafyGrass }, true))
			if s % 3 == 0 then
				deco(m, { Name = "Feuillage", Shape = Enum.PartType.Ball, Size = Vector3.one * alea(1.3, 2), CFrame = CFrame.new(nxt), Color = vert, Material = Enum.Material.LeafyGrass })
			end
			prev = nxt
		end
	end
	-- Couronne de branches qui porte le cristal
	cylindre(m, cf * CFrame.new(0, 16.6, 0), 5.6, 1, { Name = "Chapiteau", Color = Color3.fromRGB(104, 108, 92), Material = Enum.Material.Slate })
	for k = 0, 4 do
		local a = k * 72
		local base = surface(cf, a, 1.6, 17.4)
		local pointe = surface(cf, a + 20, 3.8, 20.4)
		decorative(tige(m, base, pointe, 0.7, { Name = "Branche", Color = BOIS, Material = Enum.Material.Wood }, true))
		deco(m, {
			Name = "Feuillage",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * alea(2.2, 2.8),
			CFrame = CFrame.new(pointe),
			Color = if k % 2 == 0 then vert else Color3.fromRGB(96, 168, 70),
			Material = Enum.Material.LeafyGrass,
		})
	end
	-- Fleurs et champignons lumineux au pied
	for k = 0, 5 do
		local p = surface(cf, k * 60 + 20, alea(5, 6.3), 0.35)
		deco(m, { Name = "Fleur", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = CFrame.new(p), Color = if k % 2 == 0 then Color3.fromRGB(255, 150, 210) else Color3.fromRGB(255, 232, 120), Material = Enum.Material.Neon })
	end
	for k = 0, 2 do
		local base = cf * CFrame.new(surface(CFrame.new(), k * 120 + 75, 5.6, 0))
		decorative(cylindre(m, base, 0.35, 0.9, { Name = "Pied", Color = Color3.fromRGB(230, 225, 210), Material = Enum.Material.SmoothPlastic }))
		decorative(cylindre(m, base * CFrame.new(0, 0.9, 0), 1.3, 0.35, { Name = "Chapeau", Color = Color3.fromRGB(120, 255, 210), Material = Enum.Material.Neon, Transparency = 0.15 }))
	end
	local zone = zoneEmission(m, "Lucioles", cf * CFrame.new(0, 8, 0), Vector3.new(9, 12, 9))
	particules(zone, "Lucioles", {
		Rate = 4,
		Lifetime = { 3, 5 },
		Speed = { 0.2, 0.6 },
		Size = { 0.25, 0.1 },
		Couleur = Color3.fromRGB(200, 255, 140),
	})
	cristal(m, cf, 21.5, c, true)
end

-- FOUDRE : métal, bobines de cuivre, éclair incrusté et arcs électriques
function Piliers.Foudre(m: Model, cf: CFrame, c: Color3)
	local acier = Color3.fromRGB(92, 98, 112)
	plinthe(m, cf, Color3.fromRGB(78, 82, 94), Enum.Material.DiamondPlate, CUIVRE)
	cylindre(m, cf * CFrame.new(0, 2.6, 0), 4.2, 14, { Name = "Fut", Color = acier, Material = Enum.Material.Metal })
	for i = 0, 6 do
		decorative(cylindre(m, cf * CFrame.new(0, 4 + i * 1.8, 0), 5, 0.35, { Name = "Bobine", Color = CUIVRE, Material = Enum.Material.Metal }))
	end
	-- Rivets sur la plinthe
	for k = 0, 7 do
		local a = k * 45 + 22.5
		deco(m, { Name = "Rivet", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = CFrame.new(surface(cf, a, 4.6, 1.4)), Color = CUIVRE, Material = Enum.Material.Metal })
	end
	-- Éclair incrusté sur la face avant
	local zig = { { 0.6, 15.5 }, { -0.7, 12.5 }, { 0.5, 10.5 }, { -0.8, 7.5 }, { 0.4, 5.5 }, { -0.3, 3.2 } }
	for i = 1, #zig - 1 do
		local a = (cf * CFrame.new(zig[i][1], zig[i][2], -2.15)).Position
		local b = (cf * CFrame.new(zig[i + 1][1], zig[i + 1][2], -2.15)).Position
		decorative(tige(m, a, b, 0.4, { Name = "Eclair", Color = c, Material = Enum.Material.Neon }))
	end
	-- Chapiteau à quatre pointes reliées par des arcs
	cylindre(m, cf * CFrame.new(0, 16.6, 0), 5.6, 1, { Name = "Chapiteau", Color = acier, Material = Enum.Material.DiamondPlate })
	local pointes = {}
	for k = 0, 3 do
		local a = k * 90 + 45
		local base = surface(cf, a, 1.8, 17.6)
		local bout = surface(cf, a, 3.3, 22.6)
		decorative(tige(m, base, bout, 0.45, { Name = "Pointe", Color = acier, Material = Enum.Material.Metal }, true))
		local boule = deco(m, { Name = "Electrode", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, CFrame = CFrame.new(bout), Color = c, Material = Enum.Material.Neon })
		local att = Instance.new("Attachment")
		att.Name = "Arc"
		att.Parent = boule
		table.insert(pointes, att)
	end
	for k = 1, 4 do
		local arc = Instance.new("Beam")
		arc.Name = "ArcElectrique"
		arc.Attachment0 = pointes[k]
		arc.Attachment1 = pointes[k % 4 + 1]
		arc.Color = ColorSequence.new(Color3.new(1, 1, 1), c)
		arc.LightEmission = 1
		arc.Width0 = 0.25
		arc.Width1 = 0.1
		arc.CurveSize0 = if k % 2 == 0 then 1.8 else -1.4
		arc.CurveSize1 = if k % 2 == 0 then -1.2 else 1.6
		arc.Segments = 12
		arc.FaceCamera = true
		arc.Transparency = NumberSequence.new(0.1, 0.4)
		arc.Parent = pointes[k].Parent
	end
	local zone = zoneEmission(m, "Etincelles", cf * CFrame.new(0, 21, 0), Vector3.new(5, 2, 5))
	particules(zone, "Etincelles", {
		Rate = 10,
		Lifetime = { 0.2, 0.5 },
		Speed = { 6, 10 },
		Size = { 0.2, 0 },
		Couleur = Color3.new(1, 1, 0.8),
		Couleur2 = c,
		Accel = Vector3.new(0, -20, 0),
	})
	cristal(m, cf, 21.8, c, true)
end

-- OMBRE : obsidienne torsadée, éclats noirs, cornes et brume
function Piliers.Ombre(m: Model, cf: CFrame, c: Color3)
	local obsidienne = Color3.fromRGB(24, 18, 32)
	disque(m, 13, 0.12, 0.14, { Name = "Tache", Color = Color3.fromRGB(20, 14, 30), Material = Enum.Material.Slate }, cf)
	plinthe(m, cf, Color3.fromRGB(32, 28, 40), Enum.Material.Basalt, Color3.fromRGB(96, 70, 130))
	-- Fût torsadé : blocs d'obsidienne pivotés, joints violets
	for i = 0, 6 do
		part(m, {
			Name = "Fut",
			Size = Vector3.new(3.7, 2, 3.7),
			CFrame = cf * CFrame.new(0, 3.6 + i * 2, 0) * CFrame.Angles(0, math.rad(i * 13), 0),
			Color = obsidienne,
			Material = Enum.Material.Glass,
			Reflectance = 0.15,
		})
		if i > 0 then
			deco(m, {
				Name = "Joint",
				Size = Vector3.new(3.85, 0.12, 3.85),
				CFrame = cf * CFrame.new(0, 2.6 + i * 2, 0) * CFrame.Angles(0, math.rad(i * 13 - 6.5), 0),
				Color = c,
				Material = Enum.Material.Neon,
				Transparency = 0.2,
			})
		end
	end
	-- Éclats d'obsidienne plantés dans le sol
	for k = 0, 7 do
		local a = k * 45 + alea(-14, 14)
		local base = surface(cf, a, alea(5, 6.4), 0)
		local h = alea(2.5, 5)
		deco(m, {
			Name = "Eclat",
			Size = Vector3.new(alea(0.7, 1.2), h, alea(0.7, 1.2)),
			CFrame = CFrame.new(base) * CFrame.Angles(0, -math.rad(a), 0) * CFrame.Angles(0, 0, math.rad(-alea(12, 30))) * CFrame.new(0, h / 2, 0),
			Color = Color3.fromRGB(44, 26, 66),
			Material = Enum.Material.Glass,
			Reflectance = 0.2,
		})
	end
	-- Chapiteau et cornes recourbées
	part(m, { Name = "Chapiteau", Size = Vector3.new(5.6, 1.2, 5.6), CFrame = cf * CFrame.new(0, 17.2, 0) * CFrame.Angles(0, math.rad(45), 0), Color = Color3.fromRGB(32, 28, 40), Material = Enum.Material.Basalt })
	for k = 0, 3 do
		local a = k * 90
		local p1 = surface(cf, a, 2.6, 17.8)
		local p2 = surface(cf, a, 3.6, 20.4)
		local p3 = surface(cf, a, 2.6, 23.4)
		decorative(tige(m, p1, p2, 0.6, { Name = "Corne", Color = obsidienne, Material = Enum.Material.Basalt }, true))
		decorative(tige(m, p2, p3, 0.4, { Name = "Corne", Color = obsidienne, Material = Enum.Material.Basalt }, true))
	end
	local brume = zoneEmission(m, "Brume", cf * CFrame.new(0, 0.6, 0), Vector3.new(11, 0.5, 11))
	particules(brume, "Brume", {
		Texture = TEX_FUMEE,
		Rate = 6,
		Lifetime = { 4, 6 },
		Speed = { 0.4, 1 },
		Size = { 3, 7 },
		Transparence = { 0.55, 1 },
		Couleur = Color3.fromRGB(70, 34, 100),
		Couleur2 = Color3.fromRGB(12, 6, 20),
		LightEmission = 0,
		LightInfluence = 1,
		Rotation = 20,
	})
	local brumeHaute = zoneEmission(m, "BrumeHaute", cf * CFrame.new(0, 21, 0), Vector3.new(3, 1, 3))
	particules(brumeHaute, "Brume", {
		Texture = TEX_FUMEE,
		Rate = 3,
		Lifetime = { 3, 4 },
		Speed = { 0.5, 1 },
		Size = { 1.5, 4 },
		Transparence = { 0.6, 1 },
		Couleur = Color3.fromRGB(90, 40, 140),
		LightEmission = 0.2,
		Rotation = 30,
	})
	cristal(m, cf, 21.6, c, true)
end

-- LUMIÈRE : marbre blanc cannelé, or, ailes et auréole
function Piliers.Lumiere(m: Model, cf: CFrame, c: Color3)
	local blanc = Color3.fromRGB(242, 238, 230)
	disque(m, 13, 0.1, 0.12, { Name = "Aureole", Color = OR, Material = Enum.Material.Foil }, cf)
	disque(m, 11.4, 0.1, 0.14, { Name = "Dalle", Color = blanc, Material = Enum.Material.Marble }, cf)
	plinthe(m, cf, blanc, Enum.Material.Marble)
	cylindre(m, cf * CFrame.new(0, 2.6, 0), 3.8, 14, { Name = "Fut", Color = blanc, Material = Enum.Material.Marble })
	for k = 0, 7 do
		local rad = math.rad(k * 45)
		decorative(cylindre(m, cf * CFrame.new(math.cos(rad) * 1.9, 2.6, math.sin(rad) * 1.9), 0.7, 14, { Name = "Cannelure", Color = blanc, Material = Enum.Material.Marble }))
	end
	for _, y in { 3.2, 9.6, 15.8 } do
		decorative(cylindre(m, cf * CFrame.new(0, y, 0), 4.7, 0.35, { Name = "Bague", Color = OR, Material = Enum.Material.Foil }))
	end
	cylindre(m, cf * CFrame.new(0, 16.6, 0), 6.2, 1.1, { Name = "Chapiteau", Color = blanc, Material = Enum.Material.Marble })
	decorative(cylindre(m, cf * CFrame.new(0, 17.7, 0), 5.4, 0.4, { Name = "Couronne", Color = OR, Material = Enum.Material.Foil }))
	for k = 0, 3 do
		local a = k * 90 + 45
		deco(m, { Name = "Volute", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, CFrame = CFrame.new(surface(cf, a, 3, 17.2)), Color = OR, Material = Enum.Material.Foil })
	end
	-- Ailes dorées derrière le cristal (+Z local = dos au centre)
	local Y = 21.6
	for cote = -1, 1, 2 do
		for i, plume in { { 15, 5 }, { 35, 4.4 }, { 55, 3.6 }, { 75, 2.8 } } do
			local base = cf * CFrame.new(cote * 0.9, Y - 1.4 + i * 0.25, 0.9)
			deco(m, {
				Name = "Plume",
				Size = Vector3.new(0.7, plume[2], 0.2),
				CFrame = base * CFrame.Angles(0, 0, math.rad(-cote * (90 - plume[1]))) * CFrame.new(0, plume[2] / 2, 0),
				Color = OR_CLAIR,
				Material = Enum.Material.Foil,
			})
		end
	end
	-- Auréole verticale et rayons
	local plan = cf * CFrame.new(0, Y, 0.6) * CFrame.Angles(math.rad(90), 0, 0)
	anneau(m, plan, 3.6, 0.22, 0.22, 16, { Name = "Aureole", Color = c, Material = Enum.Material.Neon, Transparency = 0.15 })
	for k = 0, 7 do
		local rad = math.rad(k * 45 + 22.5)
		local a = (cf * CFrame.new(math.cos(rad) * 4.3, Y + math.sin(rad) * 4.3, 0.6)).Position
		local b = (cf * CFrame.new(math.cos(rad) * 6.2, Y + math.sin(rad) * 6.2, 0.6)).Position
		decorative(tige(m, a, b, 0.18, { Name = "Rayon", Color = c, Material = Enum.Material.Neon, Transparency = 0.4 }))
	end
	local zone = zoneEmission(m, "Lumen", cf * CFrame.new(0, 10, 0), Vector3.new(7, 16, 7))
	particules(zone, "Lumen", {
		Rate = 5,
		Lifetime = { 2, 4 },
		Speed = { 0.5, 1.2 },
		Size = { 0.3, 0 },
		Couleur = c,
		Accel = Vector3.new(0, 0.6, 0),
	})
	cristal(m, cf, Y, c, false)
end

local function construirePiliers(modele: Model)
	local dossier = Instance.new("Folder")
	dossier.Name = "Piliers"
	dossier.Parent = modele
	for i, nom in ORDRE_PILIERS do
		local theta = 30 + (i - 1) * 60
		local m = Instance.new("Model")
		m.Name = nom
		m:SetAttribute("Element", nom)
		local cf = facingIn(theta, Dim.PILIER_R, Dim.SOL_Y)
		Piliers[nom](m, cf, ELEMENTS[nom].couleur)
		m.WorldPivot = origine * cf
		m.Parent = dossier
		gemmeAnneau(modele:FindFirstChild("Dallage") or modele, theta, ELEMENTS[nom].couleur)
	end
end

----------------------------------------------------------------------------------------------
-- 4. Décor : braseros, pierres runiques, gradins, portiques en ruine, végétation, ambiance
----------------------------------------------------------------------------------------------

local function brasero(parent: Instance, base: CFrame, avecLumiere: boolean)
	cylindre(parent, base, 2.2, 0.4, { Name = "Socle", Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
	cylindre(parent, base * CFrame.new(0, 0.4, 0), 1, 2.6, { Name = "Pied", Color = Color3.fromRGB(46, 42, 50), Material = Enum.Material.Metal })
	decorative(cylindre(parent, base * CFrame.new(0, 3, 0), 2.6, 0.7, { Name = "Coupe", Color = Color3.fromRGB(46, 42, 50), Material = Enum.Material.Metal }))
	decorative(cylindre(parent, base * CFrame.new(0, 3.6, 0), 2.8, 0.18, { Name = "Rebord", Color = OR, Material = Enum.Material.Metal }))
	local braises = decorative(cylindre(parent, base * CFrame.new(0, 3.45, 0), 2.2, 0.3, { Name = "Braises", Color = ARCANE, Material = Enum.Material.CrackedLava }))
	feu(braises, ARCANE, Color3.fromRGB(230, 205, 255), 3, 6)
	if avecLumiere then
		lumiere(braises, Color3.fromRGB(175, 135, 255), 16, 1.6)
	end
end

local function construireBraseros(modele: Model)
	local dossier = Instance.new("Folder")
	dossier.Name = "Braseros"
	dossier.Parent = modele
	local rBrasero = (Dim.MARCHE_R + Dim.SOCLE_R) / 2
	for i = 1, 11 do
		brasero(dossier, CFrame.new(at(i * 30, rBrasero, 1)), i % 2 == 1)
	end
end

-- Pierres runiques en lévitation, en orbite lente (CircleFX : attributs Floating + Orbit).
-- Les glyphes sont des parts ENFANTS de la pierre : CircleFX les déplace avec elle.
local function construirePierresRuniques(modele: Model)
	local dossier = Instance.new("Folder")
	dossier.Name = "PierresRuniques"
	dossier.Parent = modele
	local rPierre = Dim.MARCHE_R - 2
	for i = 0, 9 do
		local theta = 45 + i * 30
		local y = 8.5 + (i % 3) * 1.6
		local cf = facingIn(theta, rPierre, y) * CFrame.Angles(math.rad(alea(-8, 8)), 0, math.rad(alea(-10, 10)))
		local p = deco(dossier, {
			Name = "Pierre",
			Size = Vector3.new(1.8, 3.4, 1),
			CFrame = cf,
			Color = Color3.fromRGB(72, 68, 92),
			Material = Enum.Material.Slate,
		})
		p:SetAttribute("Floating", true)
		p:SetAttribute("Orbit", true)
		-- glyphe gravé sur les deux faces : hampe + deux traits obliques
		for _, face in { -1, 1 } do
			local z = face * 0.52
			deco(p, { Name = "Glyphe", Size = Vector3.new(0.18, 2.4, 0.06), CFrame = cf * CFrame.new(0, 0, z), Color = ARCANE, Material = Enum.Material.Neon })
			deco(p, {
				Name = "Glyphe",
				Size = Vector3.new(0.16, 1, 0.06),
				CFrame = cf * CFrame.new(-0.35, 0.55, z) * CFrame.Angles(0, 0, math.rad(40 + i * 7)),
				Color = ARCANE,
				Material = Enum.Material.Neon,
			})
			deco(p, {
				Name = "Glyphe",
				Size = Vector3.new(0.16, 0.9, 0.06),
				CFrame = cf * CFrame.new(0.35, -0.5, z) * CFrame.Angles(0, 0, math.rad(-(35 + i * 9))),
				Color = ARCANE,
				Material = Enum.Material.Neon,
			})
		end
		particules(p, "Poussiere", {
			Rate = 2,
			Lifetime = { 1.5, 2.5 },
			Speed = { 0.2, 0.6 },
			Size = { 0.25, 0 },
			Couleur = ARCANE,
		})
		if i % 2 == 0 then
			lumiere(p, ARCANE, 9, 0.8)
		end
	end
end

-- Gradins bas en arc, interrompus à l'entrée et au niveau des portiques
local ANGLES_PORTIQUES = { 60, 120, 180, 240, 300 }
local DEMI_ANGLE_PORTIQUE = 7

local function libre(theta: number): boolean
	if theta < Dim.ENTREE_DEMI_ANGLE or theta > 360 - Dim.ENTREE_DEMI_ANGLE then
		return false
	end
	for _, a in ANGLES_PORTIQUES do
		if math.abs(theta - a) < DEMI_ANGLE_PORTIQUE then
			return false
		end
	end
	return true
end

local function construireGradins(modele: Model)
	local dossier = Instance.new("Folder")
	dossier.Name = "Gradins"
	dossier.Parent = modele
	local r0 = Dim.GRADIN_R
	local rangs = {
		{ r1 = r0, r2 = r0 + 3.5, haut = 1.6, couleur = Color3.fromRGB(150, 142, 130) },
		{ r1 = r0 + 3.5, r2 = r0 + 7, haut = 3.2, couleur = Color3.fromRGB(136, 128, 118) },
	}
	local pas = 7.5
	local theta = Dim.ENTREE_DEMI_ANGLE
	while theta < 360 - Dim.ENTREE_DEMI_ANGLE - 0.01 do
		-- découpe l'arc en tronçons qui s'arrêtent aux portiques
		local debut = theta
		local fin = math.min(theta + pas, 360 - Dim.ENTREE_DEMI_ANGLE)
		for _, a in ANGLES_PORTIQUES do
			if debut < a - DEMI_ANGLE_PORTIQUE and fin > a - DEMI_ANGLE_PORTIQUE then
				fin = a - DEMI_ANGLE_PORTIQUE
			end
		end
		local milieu = (debut + fin) / 2
		if libre(milieu) and fin - debut > 0.5 then
			local delta = math.rad(fin - debut)
			for _, rang in rangs do
				local rm = (rang.r1 + rang.r2) / 2
				local h = rang.haut + 1
				part(dossier, {
					Name = "Gradin",
					Size = Vector3.new(2 * rang.r2 * math.sin(delta / 2) + 0.15, h, rang.r2 - rang.r1),
					CFrame = facing(milieu, rm, rang.haut - h / 2),
					Color = rang.couleur,
					Material = Enum.Material.Granite,
				})
			end
			-- muret arrière en ruine (hauteur irrégulière)
			local hMur = alea(3.2, 4.8)
			part(dossier, {
				Name = "Muret",
				Size = Vector3.new(2 * (r0 + 8.5) * math.sin(delta / 2) + 0.15, hMur + 1, 1.5),
				CFrame = facing(milieu, r0 + 7.75, hMur / 2 - 0.5),
				Color = PIERRE_SOMBRE,
				Material = Enum.Material.Slate,
			})
			theta = fin
		else
			theta = fin + 2 * DEMI_ANGLE_PORTIQUE
			-- saute le portique
			for _, a in ANGLES_PORTIQUES do
				if math.abs(fin + DEMI_ANGLE_PORTIQUE - a) < 0.01 then
					theta = a + DEMI_ANGLE_PORTIQUE
				end
			end
		end
	end
end

-- Bannière suspendue (tringle dorée, tissu, frange, emblème)
local function banniere(parent: Instance, cf: CFrame, largeur: number, hauteur: number, tissu: Color3, embleme: Color3)
	deco(parent, { Name = "Tringle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(largeur + 0.6, 0.25, 0.25), CFrame = cf, Color = OR, Material = Enum.Material.Metal })
	deco(parent, { Name = "Tissu", Size = Vector3.new(largeur, hauteur, 0.15), CFrame = cf * CFrame.new(0, -hauteur / 2, 0), Color = tissu, Material = Enum.Material.Fabric })
	deco(parent, { Name = "Frange", Size = Vector3.new(largeur, 0.3, 0.2), CFrame = cf * CFrame.new(0, -hauteur + 0.15, 0), Color = OR, Material = Enum.Material.Metal })
	deco(parent, {
		Name = "Embleme",
		Size = Vector3.new(0.9, 0.9, 0.18),
		CFrame = cf * CFrame.new(0, -hauteur * 0.4, -0.05) * CFrame.Angles(0, 0, math.rad(45)),
		Color = embleme,
		Material = Enum.Material.Neon,
	})
end

local function portique(parent: Instance, theta: number, ruine: boolean)
	local m = Instance.new("Model")
	m.Name = "Portique"
	local cf = facingIn(theta, Dim.PORTIQUE_R, 0)
	local pierre = Color3.fromRGB(196, 188, 174)
	-- éléments voisins pour les bannières
	local gauche = ORDRE_PILIERS[(math.floor((theta - 30) / 60) % 6) + 1]
	local droite = ORDRE_PILIERS[(math.floor((theta + 30) / 60) % 6) + 1]
	for i, cote in { -1, 1 } do
		local x = cote * 5.2
		local hColonne = if ruine and cote == 1 then 8.5 else 16
		part(m, { Name = "Base", Size = Vector3.new(3, 1.2, 3), CFrame = cf * CFrame.new(x, 0.6, 0), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
		cylindre(m, cf * CFrame.new(x, 1.2, 0), 2, hColonne, { Name = "Colonne", Color = pierre, Material = Enum.Material.Granite })
		if hColonne < 16 then
			-- sommet brisé et tambours tombés au sol
			deco(m, { Name = "Fragment", Size = Vector3.new(2, 1.4, 2), CFrame = cf * CFrame.new(x, 1.2 + hColonne + 0.4, 0) * CFrame.Angles(0.3, 0.4, 0.25), Color = pierre, Material = Enum.Material.Granite })
			for t = 0, 1 do
				decorative(part(m, {
					Name = "Tambour",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(2.2, 2, 2),
					CFrame = cf * CFrame.new(x + 2.6 + t * 1.2, 1, -2.5 - t * 2.4) * CFrame.Angles(0, 0.5 + t, 0),
					Color = pierre,
					Material = Enum.Material.Granite,
				}))
			end
		else
			deco(m, { Name = "Chapiteau", Size = Vector3.new(2.8, 1, 2.8), CFrame = cf * CFrame.new(x, 17.7, 0), Color = pierre, Material = Enum.Material.Granite })
			decorative(cylindre(m, cf * CFrame.new(x, 16.6, 0), 2.3, 0.3, { Name = "Bague", Color = OR, Material = Enum.Material.Metal }))
		end
		local nom = if i == 1 then gauche else droite
		banniere(m, cf * CFrame.new(x, 13.5, -1.2), 2.6, 7, ELEMENTS[nom].tissu, ELEMENTS[nom].couleur)
	end
	if ruine then
		-- linteau effondré, appuyé contre la colonne restante
		deco(m, { Name = "Linteau", Size = Vector3.new(13, 1.8, 2.6), CFrame = cf * CFrame.new(0.5, 5.4, 1.6) * CFrame.Angles(0, 0, math.rad(-38)), Color = pierre, Material = Enum.Material.Granite })
	else
		deco(m, { Name = "Linteau", Size = Vector3.new(13.4, 1.8, 2.6), CFrame = cf * CFrame.new(0, 19.1, 0), Color = pierre, Material = Enum.Material.Granite })
		deco(m, { Name = "Corniche", Size = Vector3.new(14.4, 0.6, 3), CFrame = cf * CFrame.new(0, 20.3, 0), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
		deco(m, { Name = "FriseDoree", Size = Vector3.new(13.4, 0.25, 2.7), CFrame = cf * CFrame.new(0, 18.6, 0), Color = OR, Material = Enum.Material.Metal })
		local cle = deco(m, { Name = "Clef", Size = Vector3.new(1.2, 1.2, 0.3), CFrame = cf * CFrame.new(0, 19.1, -1.4) * CFrame.Angles(0, 0, math.rad(45)), Color = ARCANE, Material = Enum.Material.Neon })
		lumiere(cle, ARCANE, 10, 1)
	end
	m.WorldPivot = origine * cf
	m.Parent = parent
end

local function construirePortiques(modele: Model)
	local dossier = Instance.new("Folder")
	dossier.Name = "Portiques"
	dossier.Parent = modele
	for _, theta in ANGLES_PORTIQUES do
		portique(dossier, theta, theta == 120 or theta == 240)
	end
end

local function arbre(parent: Instance, theta: number, r: number, mystique: boolean)
	local base = at(theta, r, 0)
	local haut = base + Vector3.new(alea(-0.6, 0.6), 7, alea(-0.6, 0.6))
	decorative(tige(parent, base - Vector3.new(0, 0.5, 0), haut, 1.4, { Name = "Tronc", Color = BOIS, Material = Enum.Material.Wood }, true))
	local feuille = if mystique then Color3.fromRGB(168, 138, 220) else Color3.fromRGB(70, 128, 62)
	for k = 0, 2 do
		local d = if k == 0 then 5 else 3.8
		local off = if k == 0 then Vector3.new(0, 1.2, 0) else at(theta + (k == 1 and 70 or -70), 1.8, -0.3)
		deco(parent, {
			Name = "Feuillage",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * d,
			CFrame = CFrame.new(haut + off),
			Color = feuille,
			Material = Enum.Material.LeafyGrass,
		})
	end
	if mystique then
		deco(parent, { Name = "Fruit", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = CFrame.new(haut + Vector3.new(0, -1, 0) + at(theta + 90, 1.6, 0)), Color = Color3.fromRGB(220, 200, 255), Material = Enum.Material.Neon })
	end
end

local function construireVegetation(modele: Model)
	local dossier = Instance.new("Folder")
	dossier.Name = "Vegetation"
	dossier.Parent = modele
	local rArbre = Dim.R + 3.5
	for i = 0, 5 do
		arbre(dossier, 30 + i * 60, rArbre, i % 2 == 0)
	end
	-- buissons entre les arbres (hors de l'allée d'entrée)
	for i = 0, 19 do
		local theta = 14 + i * 16.6 + alea(-3, 3)
		if theta > 12 and theta < 348 then
			deco(dossier, {
				Name = "Buisson",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * alea(2.2, 3.4),
				CFrame = CFrame.new(at(theta, Dim.R + alea(1.5, 4.5), 0.4)),
				Color = Color3.fromRGB(62 + math.floor(alea(0, 25)), 110 + math.floor(alea(0, 30)), 58),
				Material = Enum.Material.LeafyGrass,
			})
		end
	end
	-- lucioles autour de l'arène
	for i = 0, 3 do
		local zone = zoneEmission(dossier, "Lucioles", CFrame.new(at(75 + i * 70, Dim.R - 1, 4)), Vector3.new(12, 6, 12))
		particules(zone, "Lucioles", {
			Rate = 3,
			Lifetime = { 4, 6 },
			Speed = { 0.2, 0.5 },
			Size = { 0.3, 0.1 },
			Couleur = Color3.fromRGB(210, 255, 150),
		})
	end
end

local function construireAmbiance(modele: Model)
	-- Poussière magique qui monte du cercle (émetteur plaqué au sol, ne gêne ni caméra ni raycast)
	local zone = zoneEmission(modele, "PoussiereMagique", CFrame.new(0, Dim.SOL_Y + 0.3, 0), Vector3.new(Dim.CERCLE_R * 1.6, 0.2, Dim.CERCLE_R * 1.6))
	particules(zone, "PoussiereMagique", {
		Rate = 14,
		Lifetime = { 3, 5 },
		Speed = { 0.4, 1.2 },
		Size = { 0.3, 0 },
		Couleur = ARCANE,
		Couleur2 = Color3.fromRGB(220, 200, 255),
		Spread = Vector2.new(20, 20),
		Accel = Vector3.new(0, 0.4, 0),
	})
end

----------------------------------------------------------------------------------------------
-- 5. Entrée monumentale (côté ColosseumGate, theta = 0)
----------------------------------------------------------------------------------------------

local function pylone(m: Model, x: number, rPylone: number)
	local cf = CFrame.lookAt(Vector3.new(x, 0, -rPylone), Vector3.new(x, 0, -rPylone - 1)) -- face à l'avenue
	part(m, { Name = "Base", Size = Vector3.new(6, 2, 6), CFrame = cf * CFrame.new(0, 1, 0), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
	part(m, { Name = "Pylone", Size = Vector3.new(4.4, 18, 4.4), CFrame = cf * CFrame.new(0, 11, 0), Color = Color3.fromRGB(96, 90, 108), Material = Enum.Material.Slate })
	for _, y in { 4, 17.5 } do
		deco(m, { Name = "Bande", Size = Vector3.new(4.7, 0.4, 4.7), CFrame = cf * CFrame.new(0, y, 0), Color = OR, Material = Enum.Material.Metal })
	end
	part(m, { Name = "Chapiteau", Size = Vector3.new(5.4, 1.5, 5.4), CFrame = cf * CFrame.new(0, 20.75, 0), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
	local gemme = deco(m, {
		Name = "Gemme",
		Size = Vector3.new(2, 2, 2),
		CFrame = cf * CFrame.new(0, 27, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.26)),
		Color = ARCANE,
		Material = Enum.Material.Neon,
	})
	lumiere(gemme, ARCANE, 20, 2)
	-- bannières côté avenue et côté arène
	banniere(m, cf * CFrame.new(0, 15.5, -2.35), 3, 9, Color3.fromRGB(62, 40, 112), ARCANE)
	banniere(m, cf * CFrame.new(0, 15.5, 2.35) * CFrame.Angles(0, math.pi, 0), 3, 9, Color3.fromRGB(62, 40, 112), ARCANE)
end

local function construireEntree(modele: Model)
	local m = Instance.new("Model")
	m.Name = "Entree"
	local Y = Dim.SOL_Y
	local largeur = 14
	-- Escalier de 6 marches (0.5 stud) du sol extérieur jusqu'au sol de combat
	for k = 1, 6 do
		local rExt = Dim.SOCLE_R + 2 - (k - 1) * 2
		local rInt = if k == 6 then Dim.SOL_R - 1 else rExt - 2
		-- +0.04 : le dessus ne doit pas être au même niveau que le socle ou le
		-- sol de combat, sinon les deux surfaces scintillent quand la caméra bouge.
		local haut = k * (Y / 6) + 0.04
		local h = haut + 1
		part(m, {
			Name = "Marche",
			Size = Vector3.new(largeur, h, rExt - rInt),
			CFrame = CFrame.new(0, haut - h / 2, -(rExt + rInt) / 2),
			Color = if k % 2 == 0 then MARBRE else Color3.fromRGB(210, 204, 192),
			Material = Enum.Material.Marble,
		})
		deco(m, { Name = "Nez", Size = Vector3.new(largeur, 0.12, 0.25), CFrame = CFrame.new(0, haut + 0.02, -rExt + 0.12), Color = OR, Material = Enum.Material.Metal })
	end
	-- Rampes latérales
	for _, cote in { -1, 1 } do
		local x = cote * (largeur / 2 + 0.7)
		part(m, { Name = "Rampe", Size = Vector3.new(1.4, 4.6, 7), CFrame = CFrame.new(x, Y + 1.3 - 2, -(Dim.SOL_R + 3.5)), Color = PIERRE, Material = Enum.Material.Granite })
		part(m, { Name = "Rampe", Size = Vector3.new(1.4, 3.6, 7), CFrame = CFrame.new(x, Y - 2.2, -(Dim.SOL_R + 10.5)), Color = PIERRE, Material = Enum.Material.Granite })
		deco(m, { Name = "Couvertine", Size = Vector3.new(1.6, 0.25, 7), CFrame = CFrame.new(x, Y + 1.4, -(Dim.SOL_R + 3.5)), Color = OR, Material = Enum.Material.Metal })
		deco(m, { Name = "Couvertine", Size = Vector3.new(1.6, 0.25, 7), CFrame = CFrame.new(x, Y - 0.3, -(Dim.SOL_R + 10.5)), Color = OR, Material = Enum.Material.Metal })
		-- brasero au sommet de chaque rampe, en haut de l'escalier
		brasero(m, CFrame.new(x, Y + 1.55, -(Dim.SOL_R + 1.5)), true)
	end
	-- Allée pavée jusqu'à la limite
	local rA = Dim.SOCLE_R + 2
	local rB = math.sqrt(Dim.LIMITE ^ 2 - 10 ^ 2) -- les coins de l'allée restent dans la limite
	part(m, { Name = "Allee", Size = Vector3.new(largeur + 2, 1, rB - rA), CFrame = CFrame.new(0, -0.4, -(rA + rB) / 2), Color = Color3.fromRGB(120, 114, 108), Material = Enum.Material.Cobblestone })
	for _, cote in { -1, 1 } do
		deco(m, { Name = "Bordure", Size = Vector3.new(0.6, 0.4, rB - rA), CFrame = CFrame.new(cote * (largeur / 2 + 1.3), 0.2, -(rA + rB) / 2), Color = PIERRE_SOMBRE, Material = Enum.Material.Granite })
	end
	-- Porte monumentale : deux pylônes, arche, linteau, fronton et sceau
	local rPorte = Dim.R
	local ecart = 10
	pylone(m, -ecart, rPorte)
	pylone(m, ecart, rPorte)
	local cfPorte = CFrame.lookAt(Vector3.new(0, 0, -rPorte), Vector3.new(0, 0, -rPorte - 1))
	local rArc = ecart - 2.2
	local nArc = 10
	for i = 0, nArc - 1 do
		local a1 = math.pi * i / nArc
		local a2 = math.pi * (i + 1) / nArc
		local p1 = (cfPorte * CFrame.new(math.cos(a1) * rArc, 12 + math.sin(a1) * rArc * 0.85, 0)).Position
		local p2 = (cfPorte * CFrame.new(math.cos(a2) * rArc, 12 + math.sin(a2) * rArc * 0.85, 0)).Position
		decorative(tige(m, p1, p2, 1.6, { Name = "Voussoir", Color = Color3.fromRGB(176, 168, 156), Material = Enum.Material.Granite }))
	end
	deco(m, { Name = "Linteau", Size = Vector3.new(2 * ecart + 5.4, 2.6, 4.2), CFrame = cfPorte * CFrame.new(0, 22.8, 0), Color = Color3.fromRGB(96, 90, 108), Material = Enum.Material.Slate })
	deco(m, { Name = "Frise", Size = Vector3.new(2 * ecart + 5.4, 0.35, 4.4), CFrame = cfPorte * CFrame.new(0, 21.7, 0), Color = OR, Material = Enum.Material.Metal })
	for _, cote in { -1, 1 } do
		deco(m, {
			Class = "WedgePart",
			Name = "Fronton",
			Size = Vector3.new(3.6, 3.4, ecart + 2.7),
			CFrame = cfPorte * CFrame.new(cote * (ecart + 2.7) / 2, 25.8, 0) * CFrame.Angles(0, math.rad(-cote * 90), 0), -- pente qui monte vers le centre
			Color = PIERRE_SOMBRE,
			Material = Enum.Material.Slate,
		})
	end
	for _, face in { -1, 1 } do
		local cfSceau = cfPorte * CFrame.new(0, 22.8, face * 2.25) * CFrame.Angles(0, math.pi / 2, 0)
		deco(m, { Name = "Sceau", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4, 4), CFrame = cfSceau, Color = OR, Material = Enum.Material.Metal })
		deco(m, { Name = "SceauLumineux", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 2.6, 2.6), CFrame = cfSceau, Color = ARCANE, Material = Enum.Material.Neon })
	end
	m.Parent = modele
end

----------------------------------------------------------------------------------------------
-- Point d'entrée
----------------------------------------------------------------------------------------------

-- Convention par défaut : angle (degrés) -> direction horizontale. Passer opts.angleToDir pour
-- utiliser exactement la même convention que Arena3D si elle diffère.
local function directionParDefaut(deg: number): Vector3
	local a = math.rad(deg)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local function lireCentre(c): (number, number, number?)
	if typeof(c) == "Vector3" then
		return c.X, c.Z, c.Y
	elseif typeof(c) == "Vector2" then
		return c.X, c.Y, nil
	elseif type(c) == "table" then
		return c.X or c.x or c[1], c.Z or c.z or c[2], c.Y or c.y
	end
	error("Layout.Colosseum : format de centre inconnu")
end

--[[
	opts = {
		parent      : Instance (workspace.World)
		center      : Layout.Colosseum (Vector3, Vector2 X/Z ou table {X=, Z=})
		radius      : Layout.ColosseumRadius (72)
		gateDeg     : Layout.ColosseumGate (180)
		circleScale : CIRCLE_SCALE (1.5)
		groundY     : hauteur du sol extérieur (sinon center.Y, sinon 0)
		angleToDir  : fonction(deg) -> Vector3 (optionnelle)
	}
]]
function ColosseumBuilder.build(opts): Model
	local cx, cz, cy = lireCentre(opts.center)
	local groundY = opts.groundY or cy or 0
	local dirEntree = (opts.angleToDir or directionParDefaut)(opts.gateDeg or 180)
	dirEntree = Vector3.new(dirEntree.X, 0, dirEntree.Z).Unit

	local centre = Vector3.new(cx, groundY, cz)
	origine = CFrame.lookAt(centre, centre + dirEntree) -- -Z local = entrée
	nbParts = 0
	aleaGraine = 7331
	calculerDimensions(opts.radius or 72, opts.circleScale or 1.5)

	local ancien = opts.parent:FindFirstChild("Colosseum")
	if ancien then
		ancien:Destroy()
	end

	local modele = Instance.new("Model")
	modele.Name = "Colosseum"

	local sol = construireEstrade(modele)
	construireCercleMagique(modele)
	construirePiliers(modele)
	construireBraseros(modele)
	construirePierresRuniques(modele)
	construireGradins(modele)
	construirePortiques(modele)
	construireVegetation(modele)
	construireEntree(modele)
	construireAmbiance(modele)

	-- Pivot au centre, au niveau du sol extérieur, comme l'ancienne version (CircleFX s'en sert
	-- comme centre d'orbite des pierres runiques)
	modele.WorldPivot = CFrame.new(centre)
	modele:SetAttribute("FloorY", sol.Position.Y + sol.Size.X / 2)
	modele:SetAttribute("PartCount", nbParts)
	modele.Parent = opts.parent
	return modele
end

return ColosseumBuilder
