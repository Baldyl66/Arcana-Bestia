-- Décors 3D importés : remplace les lampadaires et le voilier construits en
-- pièces par les modèles « LampadaireModel » et « GalionModel » (rangés
-- dans ServerStorage ou ReplicatedStorage). Les animations sont jouées par
-- le client (module PropsFX), d'après l'attribut ArcanaProp.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ArcanaProps = {}

local LAMP_HEIGHT = 12.5
local GALLEON_LENGTH = 64
local ARENA_DIAMETER = 230
local SOLID = { pierre = true, fonte = true, coque = true, pont = true, poupe = true, cloison = true, sable = true, pierre_sombre = true,
	marbre = true, bois = true, bleu_nuit = true,
	-- Torche
	socle_de = true, socle_marche = true, socle_corniche = true, colonne_segment = true, colonne_spirale = true }

-- Couleurs des fichiers Claude Design, appliquées selon le nom des pièces :
-- { couleur, matière, transparence }.
local N = Enum.Material
local PALETTE = {
	-- Lampadaire
	pierre = { Color3.fromRGB(120, 116, 108), N.Slate },
	fonte = { Color3.fromRGB(29, 36, 51), N.Metal },
	["or"] = { Color3.fromRGB(205, 165, 78), N.Metal },
	verre = { Color3.fromRGB(255, 225, 170), N.Glass, 0.4 },
	flamme_neon = { Color3.fromRGB(255, 175, 70), N.Neon },
	flamme = { Color3.fromRGB(255, 175, 70), N.Neon },
	runes = { Color3.fromRGB(88, 214, 255), N.Neon },
	runes_neon = { Color3.fromRGB(88, 214, 255), N.Neon },
	-- Galion
	coque = { Color3.fromRGB(92, 56, 32), N.WoodPlanks },
	pont = { Color3.fromRGB(160, 120, 78), N.WoodPlanks },
	poupe = { Color3.fromRGB(110, 66, 38), N.WoodPlanks },
	cloison = { Color3.fromRGB(130, 85, 50), N.WoodPlanks },
	bois_sombre = { Color3.fromRGB(61, 38, 21), N.Wood },
	corde = { Color3.fromRGB(46, 32, 20), N.Fabric },
	voile = { Color3.fromRGB(240, 230, 205), N.Fabric },
	lumiere_neon = { Color3.fromRGB(255, 200, 110), N.Neon },
	cristal_neon = { Color3.fromRGB(110, 225, 255), N.Neon },
	plumes = { Color3.fromRGB(216, 211, 244), N.SmoothPlastic },
	-- Arène des Champions
	pierre_sombre = { Color3.fromRGB(140, 123, 98), N.Limestone },
	marbre = { Color3.fromRGB(242, 237, 227), N.Marble },
	sable = { Color3.fromRGB(227, 197, 140), N.Sand },
	bois = { Color3.fromRGB(107, 69, 40), N.WoodPlanks },
	tissu_rouge = { Color3.fromRGB(165, 35, 43), N.Fabric },
	tissu_creme = { Color3.fromRGB(239, 226, 196), N.Fabric },
	bleu_nuit = { Color3.fromRGB(27, 42, 92), N.Fabric },
	metal = { Color3.fromRGB(59, 62, 70), N.Metal },
	vegetation = { Color3.fromRGB(86, 112, 47), N.Grass },
	feu_neon = { Color3.fromRGB(255, 160, 60), N.Neon },
	vitrail_neon = { Color3.fromRGB(110, 140, 255), N.Neon },
}

-- Nom de matière sans suffixe de découpe (« pierre_2 » -> « pierre »).
local function baseName(name: string): string
	return (string.gsub(name, "_%d+$", ""))
end

local function template(name: string): Model?
	local m = ServerStorage:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

-- Copie prête à poser : pièces ancrées, collisions seulement sur les
-- pièces massives, taille voulue, pivot au milieu de la base.
local prepared: { [string]: Model } = {}
local function prepare(name: string, measure: (Vector3) -> number, target: number): Model?
	if prepared[name] then
		return prepared[name]
	end
	local t = template(name)
	if not t then
		return nil
	end
	local m = t:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local look = PALETTE[d.Name] or PALETTE[string.lower(d.Name)] or PALETTE[baseName(d.Name)]
			if look and not t:GetAttribute("KeepColors") then
				-- Les maillages importés gardent leur texture d'origine s'ils en ont une.
				if not (d:IsA("MeshPart") and d.TextureID ~= "") then
					d.Color = look[1]
					d.Material = look[2]
				end
				if look[3] then
					d.Transparency = look[3]
				end
			end
			d.Anchored = true
			d.CanCollide = SOLID[d.Name] == true or SOLID[baseName(d.Name)] == true
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("KeyframeSequence") then
			d:Destroy()
		end
	end
	local _, size = m:GetBoundingBox()
	local current = measure(size)
	if current > 0 then
		m:ScaleTo(m:GetScale() * target / current)
	end
	local boxCf, boxSize = m:GetBoundingBox()
	m.WorldPivot = CFrame.new(boxCf.Position - Vector3.new(0, boxSize.Y / 2, 0))
	prepared[name] = m
	return m
end

local function findPart(m: Model, names: { string }): BasePart?
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and table.find(names, d.Name) then
			return d
		end
	end
	return nil
end

-- Arène des Champions : pivot au centre de la piste, porte « ouest » du
-- fichier tournée dans la direction ColosseumGate (degrés).
function ArcanaProps.placeArena(center: Vector3, gateDeg: number, parent: Instance): boolean
	local base = prepare("ArenaModel", function(size)
		return math.max(size.X, size.Z)
	end, ARENA_DIAMETER)
	if not base then
		return false
	end
	local arena = base:Clone()
	arena.Name = "ArenaModel"
	arena:SetAttribute("ArcanaProp", "Arene")
	local _, size = arena:GetBoundingBox()
	arena:SetAttribute("UnitScale", math.max(size.X, size.Z) / 250)
	for _, d in ipairs(arena:GetDescendants()) do
		if d:IsA("BasePart") and baseName(d.Name) == "pierre" then
			d.Color = Color3.fromRGB(220, 202, 162)
			d.Material = Enum.Material.Limestone
		end
	end
	-- Pivot au sol, centré sur la piste (le fichier est centré à l'origine).
	local boxCf = arena:GetBoundingBox()
	local bottom = boxCf.Position.Y - size.Y / 2
	arena.WorldPivot = CFrame.new(boxCf.Position.X, bottom + size.Y * (1.525 / 52.475), boxCf.Position.Z)
	arena:PivotTo(CFrame.new(center) * CFrame.Angles(0, -math.rad(gateDeg - 180), 0))
	local fire = findPart(arena, { "feu_neon" })
	if fire then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 160, 70)
		light.Brightness = 2
		light.Range = 40
		light.Parent = fire
	end
	arena.Parent = parent
	return true
end

-- Banc : modèle « BancModel » (dossier fonte, assise en bois, or et runes).
-- Le dos est vers +Z dans le bloc `cf` du village : on tourne le modèle pour
-- que l'assise regarde vers l'avant, et on ajoute un siège pour s'asseoir.
local BENCH_WIDTH = 6.5
function ArcanaProps.placeBench(cf: CFrame, parent: Instance): boolean
	local base = prepare("BancModel", function(size)
		return size.X
	end, BENCH_WIDTH)
	if not base then
		return false
	end
	local t = template("BancModel")
	local yaw = math.rad((t and t:GetAttribute("YawOffset")) or 0)
	local bench = base:Clone()
	bench.Name = "Banc"
	bench:PivotTo(CFrame.new(cf.Position) * (cf - cf.Position) * CFrame.Angles(0, yaw, 0))
	local _, size = bench:GetBoundingBox()
	local seat = Instance.new("Seat")
	seat.Name = "Assise"
	seat.Size = Vector3.new(BENCH_WIDTH * 0.75, 0.3, 1.2)
	seat.Transparency = 1
	seat.Anchored = true
	seat.CanCollide = false
	seat.CFrame = cf * CFrame.new(0, size.Y * 0.36, 0)
	seat.Parent = bench
	bench.Parent = parent
	return true
end

-- Lampadaire : renvoie true s'il a été posé (sinon le jeu construit l'ancien).
function ArcanaProps.placeLamp(cf: CFrame, parent: Instance): boolean
	local base = prepare("LampadaireModel", function(size)
		return size.Y
	end, LAMP_HEIGHT)
	if not base then
		return false
	end
	local lamp = base:Clone()
	lamp.Name = "Lampadaire"
	lamp:SetAttribute("ArcanaProp", "Lampadaire")
	lamp:PivotTo(CFrame.new(cf.Position) * (cf - cf.Position))
	local flame = findPart(lamp, { "flamme_neon", "flamme", "verre" })
	if flame then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 110)
		light.Brightness = 1.6
		light.Range = 22
		light.Parent = flame
	end
	lamp.Parent = parent
	return true
end

-- Torche fantaisie : modèle « TorcheModel », remplace les braseros de l'arène.
local TORCH_HEIGHT = 6
-- { préfixe, couleur, matière, transparence } : le premier préfixe qui correspond l'emporte.
local TORCH_LOOK = {
	{ "flamme_coeur", Color3.fromRGB(230, 170, 80), N.Neon, 0.2 },
	{ "flamme", Color3.fromRGB(200, 90, 30), N.Neon, 0.3 },
	{ "cristal", Color3.fromRGB(60, 140, 180), N.Neon },
	{ "rune", Color3.fromRGB(40, 120, 160), N.Neon },
	{ "vasque_lit", Color3.fromRGB(255, 110, 40), N.Neon },
	{ "corne", Color3.fromRGB(205, 165, 78), N.Metal },
	{ "colonne_bague", Color3.fromRGB(205, 165, 78), N.Metal },
	{ "chapiteau", Color3.fromRGB(205, 165, 78), N.Metal },
	{ "vasque", Color3.fromRGB(205, 165, 78), N.Metal },
	{ "colonne_spirale", Color3.fromRGB(205, 165, 78), N.Metal },
	{ "colonne", Color3.fromRGB(45, 52, 78), N.Slate },
	{ "socle", Color3.fromRGB(120, 116, 108), N.Slate },
}
function ArcanaProps.placeTorch(cf: CFrame, parent: Instance, scale: number?): boolean
	local base = prepare("TorcheModel", function(size)
		return size.Y
	end, TORCH_HEIGHT)
	if not base then
		return false
	end
	local torch = base:Clone()
	torch.Name = "Torche"
	local s = scale or 1
	if s ~= 1 then
		torch:ScaleTo(torch:GetScale() * s)
	end
	torch:PivotTo(CFrame.new(cf.Position) * (cf - cf.Position))
	torch:SetAttribute("ArcanaProp", "Torche")
	-- Couleurs par préfixe de nom (le fichier importé arrive sans couleurs).
	for _, d in ipairs(torch:GetDescendants()) do
		if d:IsA("BasePart") then
			for _, rule in ipairs(TORCH_LOOK) do
				if string.sub(d.Name, 1, #rule[1]) == rule[1] then
					if d:IsA("MeshPart") then
						d.TextureID = ""
					end
					d.Color = rule[2]
					d.Material = rule[3]
					d.Transparency = rule[4] or 0
					d.CastShadow = rule[3] ~= Enum.Material.Neon
					break
				end
			end
		end
	end
	local flame = findPart(torch, { "flamme_coeur", "flamme_externe", "cristal_central", "vasque_lit" })
	if flame then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 90)
		light.Brightness = 1
		light.Range = 18 * s
		light.Parent = flame
	end
	torch.Parent = parent
	return true
end

-- Galion : posé à flot, ligne de flottaison sous le pont.
function ArcanaProps.placeGalleon(cf: CFrame, waterY: number, parent: Instance): boolean
	local base = prepare("GalionModel", function(size)
		return math.max(size.X, size.Z)
	end, GALLEON_LENGTH)
	if not base then
		return false
	end
	local ship = base:Clone()
	ship.Name = "Galion"
	ship:SetAttribute("ArcanaProp", "Galion")
	local _, size = ship:GetBoundingBox()
	-- Dans le fichier, la coque plonge d'environ 7 % de la hauteur totale.
	local draft = size.Y * 0.07
	ship:PivotTo(CFrame.new(cf.Position.X, waterY - draft, cf.Position.Z) * (cf - cf.Position))
	for _, name in ipairs({ "lumiere_neon", "cristal_neon" }) do
		local p = findPart(ship, { name })
		if p then
			local light = Instance.new("PointLight")
			light.Color = name == "cristal_neon" and Color3.fromRGB(140, 220, 255) or Color3.fromRGB(255, 190, 110)
			light.Brightness = 1.5
			light.Range = 30
			light.Parent = p
		end
	end
	ship.Parent = parent
	return true
end

return ArcanaProps
