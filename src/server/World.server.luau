-- Génère le monde d'Arcana Bestia au démarrage du serveur : l'arène de
-- l'autel au centre, la cité fortifiée de Brumeval tout autour (sol pavé,
-- remparts, portes, Arène des Champions), montagnes en toile de fond et
-- éclairage. Les maisons, places et PNJ sont construits par Village.server.luau.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VillageData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("VillageData"))
local ArcanaProps = require(game:GetService("ServerScriptService"):WaitForChild("ArcanaProps"))

local Terrain = workspace.Terrain

-- Nettoie les éléments de l'ancienne version restés dans le place.
for _, name in ipairs({ "Arena", "Baseplate", "ArenaAtmosphere" }) do
	local legacy = workspace:FindFirstChild(name)
	if legacy then
		legacy:Destroy()
	end
end
local legacyGui = game:GetService("StarterGui"):FindFirstChild("BoosterUI")
if legacyGui then
	legacyGui:Destroy()
end

-- Les personnages n'apparaissent qu'une fois le sol généré.
Players.CharacterAutoLoads = false
workspace:SetAttribute("WorldReady", false)
workspace:SetAttribute("WorldProgress", 0)

local RES = 4
local MIN_Y, MAX_Y = -24, 216
local CHUNK = 32
-- Le terrain va au-delà de la prairie : collines puis montagnes à l'horizon.
local GEN_HALF = 512
local COLS = GEN_HALF * 2 // RES

local L = VillageData.Layout
local GROUND = L.Ground
local WALL, WALL_T, WALL_H = L.Wall, L.WallThickness, L.WallHeight
-- Eau des douves : les voxels sous ce niveau sont remplis d'eau.
local WATER = -3

local M = Enum.Material

local function smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function fbm(x: number, z: number, octaves: number, seed: number): number
	local total, amplitude, frequency, norm = 0, 1, 1, 0
	for _ = 1, octaves do
		total += math.noise(x * frequency, z * frequency, seed) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2
	end
	return total / norm
end

-- Crêtes montagneuses : bruit « ridged » multi-octaves (arêtes vives, sommets
-- pointus, vallons plus doux entre les crêtes).
local function ridged(x: number, z: number): number
	local total, amplitude, frequency, weight, norm = 0, 1, 1 / 200, 1, 0
	for i = 1, 5 do
		local n = math.clamp(1 - math.abs(math.noise(x * frequency, z * frequency, 9.71 + i * 1.37)) * 2.2, 0, 1)
		n = n * n * weight
		weight = math.clamp(n * 1.8, 0, 1)
		total += n * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.03
	end
	return total / norm
end

---------------------------------------------------------------------------
-- Plan du château
---------------------------------------------------------------------------
local function inRect(x: number, z: number, r: { Vector2 }, margin: number): boolean
	return x >= r[1].X - margin and x <= r[2].X + margin and z >= r[1].Y - margin and z <= r[2].Y + margin
end

local function onPath(x: number, z: number): boolean
	for _, r in ipairs(L.Paths) do
		if inRect(x, z, r, 0) then
			return true
		end
	end
	return false
end

-- Allées pavées entre les quartiers.
local function onStonePath(x: number, z: number, margin: number?): boolean
	local p = Vector2.new(x, z)
	local extra = margin or 0
	for _, seg in ipairs(L.StonePaths or {}) do
		local a, b = seg[1], seg[2]
		local ab = b - a
		local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
		local half = seg[3] / 2 + extra
		if (p - (a + ab * t)).Magnitude <= half then
			return true
		end
	end
	return false
end

-- Cours en terre battue des quartiers.
local function inYard(x: number, z: number): boolean
	for _, r in ipairs({ L.BarracksYard, L.TrainingYard, L.StableYard, L.WarehouseYard }) do
		if inRect(x, z, r, 0) then
			return true
		end
	end
	return false
end

-- La surface rendue des voxels se trouve une demi-case (2 studs) au-dessus
-- de la hauteur écrite : on compense pour que le sol soit pile à GROUND.
local SURFACE_OFFSET = RES / 2

local function heightAt(x: number, z: number): number
	local reach = math.max(math.abs(x), math.abs(z))
	local h = GROUND
	if reach > L.MoatInner - 4 and reach < L.MoatOuter + 4 then
		-- Douves : berges en pente douce, fond plat.
		local into = math.min(reach - (L.MoatInner - 4), (L.MoatOuter + 4) - reach)
		h = GROUND - 11 * smoothstep(0, 7, into)
	elseif reach >= L.MoatOuter + 4 then
		-- Prairie à peine ondulée, puis collines et montagnes.
		local d = reach - L.Hills
		h = GROUND + fbm(x / 120, z / 120, 2, 4.1) * 3 * smoothstep(L.MoatOuter + 10, L.MoatOuter + 50, reach)
		if d > 0 then
			h += smoothstep(0, 140, d) * (25 + ridged(x, z) * 140 + fbm(x / 90, z / 90, 3, 2.2) * 20) + smoothstep(80, 220, d) * 30
		end
		-- Les chemins restent plats.
		if onPath(x, z) or (Vector2.new(x, z) - L.Colosseum).Magnitude < L.ColosseumRadius + 10 then
			h = GROUND
		end
	end
	return math.clamp(h - SURFACE_OFFSET, MIN_Y + 8, MAX_Y - 8)
end

local function surfaceMaterial(x: number, z: number, h: number, slope: number): Enum.Material
	local reach = math.max(math.abs(x), math.abs(z))
	local d = math.sqrt(x * x + z * z)
	if reach <= WALL then
		if d <= L.Plaza then
			-- Boulevard autour de l'arène et bordure de la place en pavés plus sombres.
			if (d >= L.RingInner and d <= L.RingOuter) or d >= L.Plaza - 5 then
				return M.Cobblestone
			end
			return M.Pavement
		end
		if (Vector2.new(x, z) - L.Colosseum).Magnitude < L.ColosseumRadius + 8 then
			return M.Pavement
		end
		-- Marge de 2 studs : la terre labourée va jusqu'aux clôtures, sans herbe qui dépasse.
		if inRect(x, z, L.Fields, 2) or inRect(x, z, L.VegetableGarden, 2) then
			return M.Mud
		end
		-- Grand-Place et cour d'honneur dallées ; rues et cour des artisans pavées.
		if inRect(x, z, L.MarketSquare, 0) or inRect(x, z, L.HonorCourt, 0) then
			return M.Pavement
		end
		if inRect(x, z, L.ArtisanYard, 0) or onPath(x, z) or onStonePath(x, z) then
			return M.Cobblestone
		end
		if inYard(x, z) then
			return (math.noise(x / 14, z / 14, 8.8) > 0.3) and M.Mud or M.Ground
		end
		-- Pelouse uniforme : seule la matière Grass porte les brins d'herbe.
		return M.Grass
	elseif reach < L.MoatOuter + 4 then
		-- Pied des remparts et berges des douves.
		return (reach > L.MoatInner - 1 and reach < L.MoatOuter + 1) and M.Mud or M.Ground
	end
	if onPath(x, z) then
		return M.Ground
	end
	if (Vector2.new(x, z) - L.Colosseum).Magnitude < L.ColosseumRadius + 8 then
		return M.Pavement
	end
	if h > 130 + math.noise(x / 40, z / 40, 1.7) * 15 and slope < 1.1 then
		return M.Snow
	elseif slope > 0.9 then
		return M.Rock
	elseif slope > 0.6 then
		return M.Slate
	end
	-- Prairie : grandes nappes d'herbe grasse, quelques zones de terre.
	if fbm(x / 70, z / 70, 2, 3.3) > 0.18 then
		return M.LeafyGrass
	end
	if h > GROUND + 30 and math.noise(x / 25, z / 25, 4.4) > 0.35 then
		return M.Ground
	end
	return M.Grass
end

---------------------------------------------------------------------------
-- Terrain
---------------------------------------------------------------------------
local function generateTerrain()
	Terrain:Clear()

	local heights = table.create(COLS + 2)
	for i = 0, COLS + 1 do
		local column = table.create(COLS + 2)
		local x = -GEN_HALF + (i - 0.5) * RES
		for k = 0, COLS + 1 do
			column[k] = heightAt(x, -GEN_HALF + (k - 0.5) * RES)
		end
		heights[i] = column
		if i % 8 == 0 then
			workspace:SetAttribute("WorldProgress", 0.2 * i / COLS)
			task.wait()
		end
	end

	local chunks = COLS // CHUNK
	local done = 0
	for cx = 0, chunks - 1 do
		for cz = 0, chunks - 1 do
			local i0, k0 = cx * CHUNK, cz * CHUNK

			local maxH = GROUND - SURFACE_OFFSET
			for xi = 1, CHUNK do
				for zi = 1, CHUNK do
					maxH = math.max(maxH, heights[i0 + xi][k0 + zi])
				end
			end
			local topY = math.min(MAX_Y, math.ceil((maxH + RES * 2) / RES) * RES)
			local ny = (topY - MIN_Y) // RES

			local materials, occupancy = table.create(CHUNK), table.create(CHUNK)
			for xi = 1, CHUNK do
				local gi = i0 + xi
				local matX, occX = table.create(ny), table.create(ny)
				for yi = 1, ny do
					matX[yi] = table.create(CHUNK)
					occX[yi] = table.create(CHUNK)
				end
				local x = -GEN_HALF + (gi - 0.5) * RES
				for zi = 1, CHUNK do
					local gk = k0 + zi
					local h = heights[gi][gk]
					local slope = math.max(
						math.abs(heights[gi + 1][gk] - heights[gi - 1][gk]),
						math.abs(heights[gi][gk + 1] - heights[gi][gk - 1])
					) / (2 * RES)
					local surface = surfaceMaterial(x, -GEN_HALF + (gk - 0.5) * RES, h, slope)

					for yi = 1, ny do
						local y0 = MIN_Y + (yi - 1) * RES
						local occ = math.clamp((h - y0) / RES, 0, 1)
						local mat = M.Air
						if occ > 0 then
							mat = (h - y0 > 10) and M.Rock or surface
						end
						if y0 + RES <= WATER and occ < 0.5 then
							mat, occ = M.Water, 1
						end
						matX[yi][zi] = mat
						occX[yi][zi] = occ
					end
				end
				materials[xi] = matX
				occupancy[xi] = occX
			end

			local corner = Vector3.new(-GEN_HALF + i0 * RES, MIN_Y, -GEN_HALF + k0 * RES)
			local region = Region3.new(corner, corner + Vector3.new(CHUNK * RES, topY - MIN_Y, CHUNK * RES))
			Terrain:WriteVoxels(region, RES, materials, occupancy)

			done += 1
			workspace:SetAttribute("WorldProgress", 0.2 + 0.5 * done / (chunks * chunks))
			task.wait()
		end
	end

	-- Eau des douves : vert-bleu profond, peu transparente (masque le fond).
	Terrain.WaterColor = Color3.fromRGB(38, 92, 98)
	Terrain.WaterTransparency = 0.35
	Terrain.WaterReflectance = 0.32
	Terrain.WaterWaveSize = 0.06
	Terrain.WaterWaveSpeed = 4
	-- Brins d'herbe animés sur les pelouses.
	pcall(function()
		Terrain.Decoration = true
		-- Herbe courte : elle ne doit pas cacher les bancs et les massifs.
		Terrain.GrassLength = 0.3
	end)
	pcall(function()
		-- Palette naturelle et cohérente : verts un peu jaunis, terres chaudes,
		-- pierres grises légèrement beiges.
		Terrain:SetMaterialColor(M.Grass, Color3.fromRGB(110, 158, 64))
		Terrain:SetMaterialColor(M.LeafyGrass, Color3.fromRGB(82, 132, 54))
		Terrain:SetMaterialColor(M.Ground, Color3.fromRGB(138, 112, 80))
		Terrain:SetMaterialColor(M.Mud, Color3.fromRGB(100, 76, 52))
		Terrain:SetMaterialColor(M.Rock, Color3.fromRGB(118, 114, 108))
		Terrain:SetMaterialColor(M.Slate, Color3.fromRGB(98, 96, 100))
		Terrain:SetMaterialColor(M.Snow, Color3.fromRGB(240, 245, 252))
		Terrain:SetMaterialColor(M.Cobblestone, Color3.fromRGB(122, 116, 108))
		Terrain:SetMaterialColor(M.Pavement, Color3.fromRGB(176, 166, 148))
	end)

	local clouds = Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.7
	clouds.Color = Color3.fromRGB(255, 248, 240)
	clouds.Parent = Terrain
end

---------------------------------------------------------------------------
-- Helpers de construction
---------------------------------------------------------------------------
local World = workspace:FindFirstChild("World")
if World then
	World:Destroy()
end
World = Instance.new("Folder")
World.Name = "World"
World.Parent = workspace

local function part(props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		if key ~= "ClassName" and key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function decorative(p: BasePart)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function vertical(cf: CFrame): CFrame
	-- Les cylindres Roblox sont orientés selon X : on les redresse.
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

local function pointLight(parent: Instance, color: Color3, brightness: number, range: number, shadows: boolean?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = shadows == true
	light.Parent = parent
end

-- Brasero en bronze avec braises et étincelles.
local function brazier(cf: CFrame, parent: Instance, scale: number?)
	-- Modèle 3D importé s'il est présent dans ServerStorage.
	if ArcanaProps.placeTorch(cf, parent, scale) then
		return
	end
	local s = scale or 1
	local bronze = Color3.fromRGB(110, 75, 40)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4 * s, 4.4 * s, 4.4 * s), CFrame = vertical(cf * CFrame.new(0, 0.7 * s, 0)),
		Material = M.Metal, Color = bronze, Parent = parent })
	decorative(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35 * s, 4.9 * s, 4.9 * s), CFrame = vertical(cf * CFrame.new(0, 1.4 * s, 0)),
		Material = M.Metal, Color = Color3.fromRGB(215, 170, 80), Parent = parent }))
	local coals = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3 * s, 3.8 * s, 3.8 * s), CFrame = vertical(cf * CFrame.new(0, 1.35 * s, 0)),
		Material = M.Neon, Color = Color3.fromRGB(255, 110, 40), Parent = parent })
	decorative(coals)
	local fire = Instance.new("Fire")
	fire.Size = 5 * s
	fire.Heat = 9
	fire.Color = Color3.fromRGB(255, 150, 60)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
	fire.Parent = coals
	local embers = Instance.new("ParticleEmitter")
	embers.Rate = 10
	embers.Lifetime = NumberRange.new(1.5, 3)
	embers.Speed = NumberRange.new(3, 7)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.Acceleration = Vector3.new(0, 2, 0)
	embers.EmissionDirection = Enum.NormalId.Right
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.25, 0)
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 80, 30))
	embers.Parent = coals
	pointLight(coals, Color3.fromRGB(255, 160, 80), 2.4, 30 * s, false)
end

---------------------------------------------------------------------------
-- Arène centrale
---------------------------------------------------------------------------
-- Largeur de l'autel 3D importé, en studs (le dallage de l'arène fait 101).
local ALTAR_WIDTH = 26

local function buildArena()
	local arena = Instance.new("Model")
	arena.Name = "Arena"
	arena.Parent = World

	part({ Name = "Foundation", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 140, 140),
		CFrame = vertical(CFrame.new(0, 0, 0)), Material = M.Slate, Color = Color3.fromRGB(84, 82, 88), Parent = arena })
	part({ Name = "GoldRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.05, 104, 104),
		CFrame = vertical(CFrame.new(0, 2.5, 0)), Material = M.Metal, Color = Color3.fromRGB(200, 155, 70), Parent = arena })
	part({ Name = "Floor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 101, 101),
		CFrame = vertical(CFrame.new(0, 2.55, 0)), Material = M.Marble, Color = Color3.fromRGB(222, 214, 200), Parent = arena })
	part({ Name = "RuneCircle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 44, 44),
		CFrame = vertical(CFrame.new(0, 3.15, 0)), Material = M.Granite, Color = Color3.fromRGB(58, 40, 86), Parent = arena })
	part({ Name = "RuneInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.22, 40, 40),
		CFrame = vertical(CFrame.new(0, 3.16, 0)), Material = M.Marble, Color = Color3.fromRGB(210, 200, 230), Parent = arena })

	-- Sol de la place en disques lisses par-dessus le terrain (les voxels de 4 studs
	-- donnent des bords en escalier) : bordure pavée, dallage, boulevard, dallage.
	local cobble, paving = Color3.fromRGB(122, 116, 108), Color3.fromRGB(176, 166, 148)
	for i, ring in ipairs({
		{ L.Plaza * 2, M.Cobblestone, cobble },
		{ (L.Plaza - 5) * 2, M.Pavement, paving },
		{ L.RingOuter * 2, M.Cobblestone, cobble },
		{ L.RingInner * 2, M.Pavement, paving },
	}) do
		part({ Name = "PlazaDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, ring[1], ring[1]),
			CFrame = vertical(CFrame.new(0, GROUND - 0.1 + i * 0.04, 0)), Material = ring[2], Color = ring[3],
			CanCollide = false, CastShadow = false, Parent = arena })
	end

	-- Bordure arrondie tout autour (remplace les quatre escaliers) : on monte sans marche.
	part({ Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 148, 148),
		CFrame = vertical(CFrame.new(0, 0, 0)), Material = M.Slate, Color = Color3.fromRGB(96, 94, 100), Parent = arena })

	-- Grand rond décoré : rosace de marbre, rayons d'or, losanges violets et runes lumineuses.
	local gold = Color3.fromRGB(215, 170, 80)
	local Y = 3.1 -- dessus du dallage
	local function disc(name: string, d: number, h: number, mat: Enum.Material, col: Color3)
		part({ Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, d, d), CFrame = vertical(CFrame.new(0, Y - 0.1 + h, 0)),
			Material = mat, Color = col, CanCollide = false, Parent = arena })
	end
	disc("BandOuter", 98, 0.02, M.Metal, gold)
	disc("BandDark", 96, 0.03, M.Slate, Color3.fromRGB(32, 36, 64))
	disc("BandInnerGold", 86, 0.04, M.Metal, gold)
	disc("Rosace", 84.5, 0.05, M.Marble, Color3.fromRGB(236, 228, 214))
	disc("InnerGold", 47, 0.06, M.Metal, gold)
	for i = 0, 15 do
		local a = i * math.pi / 8
		local rot = CFrame.Angles(0, a, 0)
		-- Rayon d'or de la rosace.
		decorative(part({ Name = "Ray", Size = Vector3.new(i % 2 == 0 and 0.8 or 0.4, 0.1, 19), CFrame = rot * CFrame.new(0, Y + 0.12, -(23.5 + 9.5)),
			Material = M.Metal, Color = gold, Parent = arena }))
		-- Losange entre deux rayons, alternant violet et bleu nuit.
		local mid = CFrame.Angles(0, a + math.pi / 16, 0)
		decorative(part({ Name = "Lozenge", Size = Vector3.new(4.2, 0.1, 4.2), CFrame = mid * CFrame.new(0, Y + 0.11, -33) * CFrame.Angles(0, math.pi / 4, 0),
			Material = M.Glass, Color = (i % 2 == 0) and Color3.fromRGB(110, 70, 190) or Color3.fromRGB(40, 70, 160), Parent = arena }))
	end
	-- Runes lumineuses dans la bande sombre.
	for i = 0, 23 do
		local rot = CFrame.Angles(0, i * math.pi / 12 + math.pi / 24, 0)
		decorative(part({ Name = "Rune", Size = Vector3.new(2.2, 0.1, 0.6), CFrame = rot * CFrame.new(0, Y + 0.09, -45.5),
			Material = M.Neon, Color = Color3.fromRGB(40, 120, 160), Parent = arena }))
		decorative(part({ Name = "Rune", Size = Vector3.new(0.5, 0.1, 2), CFrame = rot * CFrame.new(0, Y + 0.09, -45.5),
			Material = M.Neon, Color = Color3.fromRGB(40, 120, 160), Parent = arena }))
	end

	for i = 0, 7 do
		local angle = i * math.pi / 4 + math.pi / 8
		local base = CFrame.new(math.cos(angle) * 60, 2, math.sin(angle) * 60)
		-- Grand brasero 3D posé au sol à la place du pilier (sinon pilier + brasero).
		if not ArcanaProps.placeTorch(base, arena, 22.5 / 6) then
			part({ Name = "PillarBase", Size = Vector3.new(6, 2, 6), Material = M.Slate, Color = Color3.fromRGB(70, 68, 76),
				CFrame = base * CFrame.new(0, 1, 0), Parent = arena })
			part({ Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(18, 3.6, 3.6), Material = M.Marble,
				Color = Color3.fromRGB(228, 220, 205), CFrame = vertical(base * CFrame.new(0, 11, 0)), Parent = arena })
			part({ Name = "Capital", Size = Vector3.new(5.5, 1.5, 5.5), Material = M.Slate, Color = Color3.fromRGB(70, 68, 76),
				CFrame = base * CFrame.new(0, 20.75, 0), Parent = arena })
			brazier(base * CFrame.new(0, 21.5, 0), arena)
		end
	end

	part({ Name = "AltarDais", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 14, 14), Material = M.Slate,
		Color = Color3.fromRGB(64, 58, 78), CFrame = vertical(CFrame.new(0, 3.6, 0)), Parent = arena })
	local altar = part({ Name = "Altar", Size = Vector3.new(5, 3, 5), Material = M.Marble,
		Color = Color3.fromRGB(235, 228, 215), CFrame = CFrame.new(0, 5.6, 0), Parent = arena })
	part({ Name = "AltarTrim", Size = Vector3.new(5.4, 0.4, 5.4), Material = M.Neon,
		Color = Color3.fromRGB(255, 190, 80), CFrame = CFrame.new(0, 7.2, 0), Parent = arena })

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoosterPrompt"
	prompt.ActionText = "Ouvrir un booster"
	prompt.ObjectText = "Autel Arcanique"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = altar

	local crystal = part({ Name = "ArcanaCrystal", Size = Vector3.new(3.5, 7, 3.5), Material = M.Glass,
		Color = Color3.fromRGB(90, 230, 255), Transparency = 0.15, Reflectance = 0.2,
		CFrame = CFrame.new(0, 13, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Parent = arena })
	decorative(crystal)
	local core = part({ Name = "CrystalCore", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4),
		Material = M.Neon, Color = Color3.fromRGB(140, 245, 255), CFrame = CFrame.new(0, 13, 0), Parent = arena })
	decorative(core)
	pointLight(core, Color3.fromRGB(110, 230, 255), 4, 42, false)
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Rate = 18
	sparkles.Lifetime = NumberRange.new(1.5, 3)
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Color = ColorSequence.new(Color3.fromRGB(150, 240, 255), Color3.fromRGB(200, 140, 255))
	sparkles.Parent = core

	-- Autel 3D importé (« AutelModel » ou « AutelArcane » dans ServerStorage) :
	-- il remplace le socle, l'autel et le cristal. L'autel d'origine reste
	-- invisible pour porter l'invite « Ouvrir un booster ».
	local ServerStorage = game:GetService("ServerStorage")
	local template = ServerStorage:FindFirstChild("AutelModel") or ServerStorage:FindFirstChild("AutelArcane")
	if template and template:IsA("Model") then
		local model = template:Clone()
		model.Name = "AutelModel"
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
			elseif d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		-- L'import 3D perd les couleurs unies du fichier : on les réapplique.
		local palette = {
			["or"] = { Color3.fromRGB(201, 160, 74), M.Metal },
			pierre_sombre = { Color3.fromRGB(58, 63, 78), M.Slate },
			lueur = { Color3.fromRGB(127, 232, 255), M.Neon },
			anneau_a = { Color3.fromRGB(127, 232, 255), M.Neon },
			anneau_b = { Color3.fromRGB(201, 160, 74), M.Metal },
			cristal = { Color3.fromRGB(95, 216, 245), M.Neon },
		}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("MeshPart") then
				local look = palette[d.Name]
				if d.Name:match("^eclat_") then
					look = { Color3.fromRGB(166, 241, 255), M.Neon }
				end
				if d.Name == "anneau_a" or d.Name == "anneau_b" then
					d.Transparency = 1
				end
				if look then
					d.Color, d.Material = look[1], look[2]
				elseif d.TextureID ~= "" or d:FindFirstChildWhichIsA("SurfaceAppearance") then
					d.Color = Color3.new(1, 1, 1)
				elseif d.Name:match("^mesh_") then
					-- Tranches dorées des cartes des boosters.
					d.Color, d.Material = Color3.fromRGB(201, 162, 76), M.Metal
				end
			end
		end
		-- L'import a mis toutes les pièces à plat : on reforme les groupes animés
		-- (boosters qui tournent autour du cristal, éclats en orbite).
		local function group(name: string, match: (string) -> boolean)
			local g = Instance.new("Model")
			g.Name = name
			for _, d in ipairs(model:GetChildren()) do
				if d:IsA("BasePart") and match(d.Name) then
					d.Parent = g
				end
			end
			if #g:GetChildren() > 0 then
				g.Parent = model
			else
				g:Destroy()
			end
		end
		local boosterParts = { face_avant = true, face_arriere = true, bande_avant = true, bande_arriere = true }
		group("boosters", function(n)
			return boosterParts[n] == true or n:match("^mesh_") ~= nil
		end)
		group("eclats", function(n)
			return n:match("^eclat_") ~= nil
		end)
		local _, size = model:GetBoundingBox()
		local width = math.max(size.X, size.Z)
		if width > 0 then
			model:ScaleTo(model:GetScale() * ALTAR_WIDTH / width)
		end
		-- Posé sur le dallage, centré sur l'arène.
		local box, scaled = model:GetBoundingBox()
		local floorY = 3.1
		model:PivotTo(CFrame.new(0, floorY + scaled.Y / 2, 0) * box:Inverse() * model:GetPivot())
		-- Les groupes tournent autour de l'axe de l'autel.
		for _, name in ipairs({ "boosters", "eclats" }) do
			local g = model:FindFirstChild(name)
			if g and g:IsA("Model") then
				g.WorldPivot = CFrame.new(0, g:GetPivot().Y, 0)
			end
		end
		-- Runes au sol : la texture du maillage remplit de noir ses zones
		-- transparentes ; une décalque respecte la transparence.
		local runes = model:FindFirstChild("runes_sol", true)
		if runes and runes:IsA("MeshPart") and runes.TextureID ~= "" then
			local plate = Instance.new("Part")
			plate.Name = "runes_sol_decal"
			plate.Anchored = true
			plate.CanCollide = false
			plate.CanQuery = false
			plate.CanTouch = false
			plate.Transparency = 1
			plate.Size = Vector3.new(runes.Size.X, 0.05, runes.Size.Z)
			plate.CFrame = CFrame.new(runes.Position + Vector3.new(0, runes.Size.Y / 2, 0))
			local decal = Instance.new("Decal")
			decal.Face = Enum.NormalId.Top
			decal.Texture = runes.TextureID
			decal.Color3 = Color3.fromRGB(160, 240, 255)
			decal.Parent = plate
			plate.Parent = model
			runes.Transparency = 1
		end
		for _, name in ipairs({ "pierre", "pierre_sombre", "or" }) do
			local solid = model:FindFirstChild(name, true)
			if solid and solid:IsA("BasePart") then
				solid.CanCollide = true
			end
		end
		model.Parent = arena
		for _, name in ipairs({ "AltarDais", "AltarTrim", "ArcanaCrystal", "CrystalCore" }) do
			local old = arena:FindFirstChild(name)
			if old then
				old:Destroy()
			end
		end
		altar.Transparency = 1
		altar.CanCollide = false
		prompt.MaxActivationDistance = ALTAR_WIDTH / 2 + 8
		arena:SetAttribute("CustomAltar", true)
	end

	-- Points d'apparition répartis tout autour du grand cercle, tournés vers l'autel.
	for i = 0, 11 do
		local angle = i * math.pi / 6 + math.pi / 12
		local pos = Vector3.new(math.cos(angle) * 40, 3.25, math.sin(angle) * 40)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn" .. (i + 1)
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Size = Vector3.new(5, 0.4, 5)
		spawn.CFrame = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
		-- Points d'apparition invisibles : plus de plaques au centre.
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.CanTouch = false
		spawn.Duration = 0
		spawn.Parent = arena
	end
end


---------------------------------------------------------------------------
-- Remparts : murs crénelés avec chemin de ronde, tours, portes fermées et
-- escaliers d'accès côté ville.
---------------------------------------------------------------------------
local STONE = Color3.fromRGB(152, 144, 132)
local STONE_DARK = Color3.fromRGB(116, 108, 98)
local ROOF_RED = Color3.fromRGB(176, 72, 46)
local IRON = Color3.fromRGB(40, 40, 46)
local WOOD = Color3.fromRGB(92, 62, 38)

-- Variation de teinte de la pierre : chaque pan de mur, merlon ou tour a sa
-- nuance, ce qui casse l'aspect « bloc uni ».
local stoneRandom = Random.new(31)
local function stoneTint(): Color3
	return STONE:Lerp(STONE_DARK, stoneRandom:NextNumber(0, 0.55)):Lerp(Color3.fromRGB(150, 138, 112), stoneRandom:NextNumber(0, 0.25))
end

local function signText(board: BasePart, text: string, face: Enum.NormalId, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Fantasy
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
end

-- Tour ronde : fût, couronne crénelée, toit conique et oriflamme.
local function tower(pos: Vector3, radius: number, height: number, parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Tower"
	m.Parent = parent
	local tint = stoneTint()
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, radius * 2, radius * 2), CFrame = vertical(CFrame.new(pos + Vector3.new(0, height / 2, 0))),
		Material = M.Cobblestone, Color = tint, Parent = m })
	-- Socle taluté plus large et bande de mousse au pied.
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, radius * 2 + 2, radius * 2 + 2), CFrame = vertical(CFrame.new(pos + Vector3.new(0, 2, 0))),
		Material = M.Limestone, Color = STONE_DARK, Parent = m })
	decorative(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, radius * 2 + 2.4, radius * 2 + 2.4), CFrame = vertical(CFrame.new(pos + Vector3.new(0, 0.5, 0))),
		Material = M.LeafyGrass, Color = Color3.fromRGB(72, 96, 50), Parent = m }))
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, radius * 2 + 1.6, radius * 2 + 1.6), CFrame = vertical(CFrame.new(pos + Vector3.new(0, height - 1, 0))),
		Material = M.Limestone, Color = STONE_DARK, Parent = m })
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		part({ Size = Vector3.new(2, 2.6, 1.4), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * (radius + 0.3), height + 1.3, math.sin(a) * (radius + 0.3)))
			* CFrame.Angles(0, -a + math.pi / 2, 0), Material = M.Cobblestone, Color = tint, Parent = m })
	end
	-- Meurtrières.
	for level = 1, 2 do
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2 + level * 0.6
			decorative(part({ Size = Vector3.new(0.8, 3, 0.3), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * radius, height * level / 3, math.sin(a) * radius))
				* CFrame.Angles(0, -a + math.pi / 2, 0), Material = M.Slate, Color = Color3.fromRGB(30, 28, 32), Parent = m }))
		end
	end
	for i = 0, 6 do
		local d = (radius * 2 + 2) * (1 - i / 7)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, d, d), CFrame = vertical(CFrame.new(pos + Vector3.new(0, height + 3.2 + i * 1.3, 0))),
			Material = M.ClayRoofTiles, Color = ROOF_RED:Lerp(Color3.fromRGB(110, 46, 34), (i % 2) * 0.25), Parent = m })
	end
	local top = pos + Vector3.new(0, height + 3.2 + 7 * 1.3, 0)
	part({ Size = Vector3.new(0.3, 6, 0.3), CFrame = CFrame.new(top + Vector3.new(0, 2.5, 0)), Material = M.Metal, Color = IRON, Parent = m })
	decorative(part({ Size = Vector3.new(3.4, 1.6, 0.1), CFrame = CFrame.new(top + Vector3.new(1.85, 4.6, 0)), Material = M.Fabric,
		Color = Color3.fromRGB(120, 40, 150), Parent = m }))
end

-- Lanterne murale (portes).
local function wallTorch(cf: CFrame, parent: Instance)
	decorative(part({ Size = Vector3.new(0.3, 0.3, 1), CFrame = cf * CFrame.new(0, 0, -0.5), Material = M.Metal, Color = IRON, Parent = parent }))
	local flame = part({ Size = Vector3.new(0.8, 1.1, 0.8), CFrame = cf * CFrame.new(0, -0.4, -1), Material = M.Neon, Color = Color3.fromRGB(255, 190, 100), Parent = parent })
	decorative(flame)
	pointLight(flame, Color3.fromRGB(255, 180, 100), 1.6, 20)
end

local function buildRamparts()
	local walls = folder("Ramparts", World)
	local E = WALL + WALL_T
	local mid = WALL + WALL_T / 2
	-- Enceinte fermée : les remparts sont le bord de la carte (aucune ouverture).
	local gateNames: { [string]: string } = {}
	local GATE = 8

	for _, dir in ipairs({ Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) }) do
		-- Repère du côté : X le long du mur, -Z vers la ville, origine au milieu du mur.
		local origin = Vector3.new(dir.X * mid, GROUND, dir.Y * mid)
		local frame = CFrame.lookAt(origin, origin - Vector3.new(dir.X, 0, dir.Y))
		local key = string.format("%d,%d", dir.X, dir.Y)
		local gateName = gateNames[key]

		local function wallBlock(x0: number, x1: number, y0: number)
			-- Mur découpé en pans d'environ 34 studs, chacun avec sa nuance.
			local count = math.max(1, math.ceil((x1 - x0) / 34))
			local seg = (x1 - x0) / count
			for s = 0, count - 1 do
				local a = x0 + s * seg
				part({ Name = "Wall", Size = Vector3.new(seg, WALL_H - y0, WALL_T), CFrame = frame * CFrame.new(a + seg / 2, (y0 + WALL_H) / 2, 0),
					Material = M.Cobblestone, Color = stoneTint(), Parent = walls })
			end
			if y0 == GROUND then
				decorative(part({ Size = Vector3.new(x1 - x0, 3, 0.8), CFrame = frame * CFrame.new((x0 + x1) / 2, 1.5, -WALL_T / 2 - 0.3),
					Material = M.Limestone, Color = STONE_DARK, Parent = walls }))
				-- Mousse au pied du mur côté douves et corniche sous les créneaux.
				decorative(part({ Size = Vector3.new(x1 - x0, 1.4, 0.6), CFrame = frame * CFrame.new((x0 + x1) / 2, 0.7, WALL_T / 2 + 0.25),
					Material = M.LeafyGrass, Color = Color3.fromRGB(72, 96, 50), Parent = walls }))
				decorative(part({ Size = Vector3.new(x1 - x0, 1.1, 0.8), CFrame = frame * CFrame.new((x0 + x1) / 2, WALL_H - 0.6, WALL_T / 2 + 0.35),
					Material = M.Limestone, Color = STONE_DARK, Parent = walls }))
			end
			-- Chemin de ronde dallé.
			part({ Name = "Walkway", Size = Vector3.new(x1 - x0, 0.4, WALL_T), CFrame = frame * CFrame.new((x0 + x1) / 2, WALL_H + 0.2, 0),
				Material = M.Slate, Color = Color3.fromRGB(128, 122, 116), Parent = walls })
		end
		if gateName then
			wallBlock(-E, -GATE, GROUND)
			wallBlock(GATE, E, GROUND)
			wallBlock(-GATE, GATE, 16)
		else
			wallBlock(-E, E, GROUND)
		end

		-- Contreforts côté ville (hors grande porte) : rythment le mur.
		for x = -E + 18, E - 18, 24 do
			local nearGate = key == "0,1" and math.abs(x) < 16
			if not nearGate then
				part({ Name = "Buttress", Size = Vector3.new(3, WALL_H - 1.5, 1.6), CFrame = frame * CFrame.new(x, (WALL_H - 1.5) / 2, -WALL_T / 2 - 0.8),
					Material = M.Limestone, Color = STONE_DARK, Parent = walls })
				-- Chaperon en pente (haut contre le mur, bas côté ville).
				part({ ClassName = "WedgePart", Size = Vector3.new(3, 1.9, 1.6), CFrame = frame * CFrame.new(x, WALL_H - 0.55, -WALL_T / 2 - 0.8),
					Material = M.Limestone, Color = STONE_DARK, Parent = walls })
			end
		end

		-- Tours en saillie vers l'extérieur, merlons entre elles.
		local towers = { -220, -110, 110, 220 }
		if gateName then
			table.insert(towers, -15)
			table.insert(towers, 15)
		end
		for x = -E + 2, E - 2, 4 do
			local free = true
			for _, t in ipairs(towers) do
				if math.abs(x - t) < 8 then
					free = false
				end
			end
			if free then
				part({ Name = "Merlon", Size = Vector3.new(2.2, 3, 1.4), CFrame = frame * CFrame.new(x, WALL_H + 1.9, WALL_T / 2 - 0.7),
					Material = M.Cobblestone, Color = stoneTint(), Parent = walls })
			end
		end
		for _, t in ipairs(towers) do
			local isGateTower = math.abs(t) < 20
			tower((frame * CFrame.new(t, 0, WALL_T / 2 + 3)).Position, isGateTower and 6.5 or 7, WALL_H + (isGateTower and 14 or 10), walls)
		end

		if gateName then
			-- Herse levée : seules ses dents dépassent sous la voûte.
			for x = -GATE + 1, GATE - 1, 2 do
				decorative(part({ Size = Vector3.new(0.35, 2.5, 0.35), CFrame = frame * CFrame.new(x, 14.8, 0), Material = M.Metal, Color = IRON, Parent = walls }))
			end
			-- Pont-levis de planches jusqu'à l'autre rive, chaînes vers les tours.
			local bridgeStart, bridgeEnd = WALL_T / 2, (L.MoatOuter + 5) - mid
			local length = bridgeEnd - bridgeStart
			local deck = frame * CFrame.new(0, 0.25, (bridgeStart + bridgeEnd) / 2)
			part({ Name = "Drawbridge", Size = Vector3.new(GATE * 2 - 1, 0.6, length), CFrame = deck, Material = M.WoodPlanks, Color = WOOD, Parent = walls })
			for z = -length / 2 + 1, length / 2 - 1, 3 do
				decorative(part({ Size = Vector3.new(GATE * 2 - 0.8, 0.15, 0.25), CFrame = deck * CFrame.new(0, 0.35, z), Material = M.Wood,
					Color = Color3.fromRGB(70, 46, 28), Parent = walls }))
			end
			for _, side in ipairs({ -1, 1 }) do
				part({ Size = Vector3.new(0.6, 2.4, length), CFrame = deck * CFrame.new(side * (GATE - 0.6), 1.2, 0), Material = M.Wood, Color = WOOD, Parent = walls })
				local a0 = (deck * CFrame.new(side * (GATE - 0.6), 2.4, length / 2)).Position
				local a1 = (frame * CFrame.new(side * (GATE + 1), 15, WALL_T / 2)).Position
				decorative(part({ Size = Vector3.new(0.3, 0.3, (a1 - a0).Magnitude), CFrame = CFrame.lookAt((a0 + a1) / 2, a1), Material = M.Metal,
					Color = IRON, Parent = walls }))
			end
			-- Encadrement, linteau gravé, torches et bannières côté ville.
			for _, side in ipairs({ -1, 1 }) do
				part({ Size = Vector3.new(2, 18, 1.2), CFrame = frame * CFrame.new(side * (GATE + 1), 9, -WALL_T / 2 - 0.6), Material = M.Limestone,
					Color = Color3.fromRGB(196, 186, 168), Parent = walls })
				wallTorch(frame * CFrame.new(side * (GATE + 3.5), 10, -WALL_T / 2), walls)
				decorative(part({ Size = Vector3.new(3, 9, 0.15), CFrame = frame * CFrame.new(side * (GATE + 6), WALL_H - 6, -WALL_T / 2 - 0.1),
					Material = M.Fabric, Color = Color3.fromRGB(110, 50, 170), Parent = walls }))
			end
			local lintel = part({ Size = Vector3.new(GATE * 2 + 6, 3, 1.4), CFrame = frame * CFrame.new(0, 17.5, -WALL_T / 2 - 0.7), Material = M.Limestone,
				Color = Color3.fromRGB(196, 186, 168), Parent = walls })
			signText(lintel, gateName, Enum.NormalId.Front, Color3.fromRGB(60, 45, 30))
		end

		-- Grande porte du Sud, fermée : vantaux cloutés et linteau côté château.
		if key == "0,1" then
			for _, side in ipairs({ -1, 1 }) do
				local leaf = frame * CFrame.new(side * 4, 8, -WALL_T / 2 - 0.4)
				part({ Name = "GateDoor", Size = Vector3.new(8, 16, 0.8), CFrame = leaf, Material = M.WoodPlanks, Color = WOOD, Parent = walls })
				for _, y in ipairs({ -5, 0, 5 }) do
					decorative(part({ Size = Vector3.new(7.6, 0.5, 0.2), CFrame = leaf * CFrame.new(0, y, -0.5), Material = M.Metal, Color = IRON, Parent = walls }))
				end
				part({ Size = Vector3.new(2, 18, 1.2), CFrame = frame * CFrame.new(side * 9, 9, -WALL_T / 2 - 0.6), Material = M.Limestone,
					Color = Color3.fromRGB(196, 186, 168), Parent = walls })
				wallTorch(frame * CFrame.new(side * 11.5, 10, -WALL_T / 2), walls)
			end
			local lintel = part({ Size = Vector3.new(22, 3, 1.4), CFrame = frame * CFrame.new(0, 17.5, -WALL_T / 2 - 0.7), Material = M.Limestone,
				Color = Color3.fromRGB(196, 186, 168), Parent = walls })
			signText(lintel, "Porte du Sud", Enum.NormalId.Front, Color3.fromRGB(60, 45, 30))
		end
	end
	-- Tours d'angle, décalées vers l'extérieur pour laisser le chemin de ronde libre.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			tower(Vector3.new(sx * (E + 3), GROUND, sz * (E + 3)), 9, WALL_H + 14, walls)
		end
	end
end

---------------------------------------------------------------------------
-- Donjon : grosse tour carrée crénelée dans l'angle nord-est, tourelles
-- d'angle à toit rouge, porte et escalier tournés vers la place.
---------------------------------------------------------------------------
local function buildKeep()
	local keep = Instance.new("Model")
	keep.Name = "Keep"
	keep.Parent = World
	local c = L.Keep
	local SIZE, HEIGHT = 40, 46
	-- Façade (porte) tournée vers le centre de la place.
	local base = CFrame.lookAt(Vector3.new(c.X, GROUND, c.Y), Vector3.new(0, GROUND, 0))
	part({ Name = "KeepBase", Size = Vector3.new(SIZE + 4, 3, SIZE + 4), CFrame = base * CFrame.new(0, 1.5, 0), Material = M.Limestone,
		Color = STONE_DARK, Parent = keep })
	part({ Name = "KeepBody", Size = Vector3.new(SIZE, HEIGHT, SIZE), CFrame = base * CFrame.new(0, HEIGHT / 2, 0), Material = M.Cobblestone,
		Color = STONE, Parent = keep })
	-- Bandeaux, corniche et créneaux.
	for _, y in ipairs({ HEIGHT * 0.45, HEIGHT - 1 }) do
		decorative(part({ Size = Vector3.new(SIZE + 1.2, 1.2, SIZE + 1.2), CFrame = base * CFrame.new(0, y, 0), Material = M.Limestone,
			Color = STONE_DARK, Parent = keep }))
	end
	for side = 0, 3 do
		local rot = base * CFrame.Angles(0, side * math.pi / 2, 0)
		for x = -SIZE / 2 + 2, SIZE / 2 - 2, 4 do
			part({ Name = "Merlon", Size = Vector3.new(2.2, 3, 1.4), CFrame = rot * CFrame.new(x, HEIGHT + 1.5, -SIZE / 2 + 0.7), Material = M.Cobblestone,
				Color = STONE, Parent = keep })
		end
		-- Fenêtres à meneaux sur deux étages.
		for _, y in ipairs({ HEIGHT * 0.3, HEIGHT * 0.65 }) do
			for _, x in ipairs({ -10, 10 }) do
				local w = decorative(part({ Size = Vector3.new(3, 5, 0.3), CFrame = rot * CFrame.new(x, y, -SIZE / 2 - 0.1), Material = M.Glass,
					Color = Color3.fromRGB(255, 200, 120), Transparency = 0.1, Parent = keep }))
				_ = w
				decorative(part({ Size = Vector3.new(0.4, 5, 0.4), CFrame = rot * CFrame.new(x, y, -SIZE / 2 - 0.25), Material = M.Wood, Color = WOOD, Parent = keep }))
			end
		end
	end
	-- Tourelles d'angle à toit rouge.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			tower((base * CFrame.new(sx * SIZE / 2, HEIGHT - 14, sz * SIZE / 2)).Position, 4.5, 22, keep)
		end
	end
	-- Porte en arc, escalier et bannières.
	local front = base * CFrame.new(0, 0, -SIZE / 2)
	part({ Size = Vector3.new(10, 14, 1.4), CFrame = front * CFrame.new(0, 7 + 3, -0.5), Material = M.Limestone, Color = Color3.fromRGB(196, 186, 168), Parent = keep })
	part({ Name = "KeepDoor", Size = Vector3.new(7, 11, 0.6), CFrame = front * CFrame.new(0, 5.5 + 3, -1.3), Material = M.WoodPlanks, Color = WOOD, Parent = keep })
	for step = 0, 2 do
		part({ Size = Vector3.new(14, 1, 3), CFrame = front * CFrame.new(0, 2.5 - step, -2.5 - step * 3), Material = M.Limestone,
			Color = STONE_DARK, Parent = keep })
	end
	for _, x in ipairs({ -11, 11 }) do
		decorative(part({ Size = Vector3.new(4, 14, 0.15), CFrame = front * CFrame.new(x, HEIGHT * 0.6, -0.15), Material = M.Fabric,
			Color = Color3.fromRGB(150, 32, 42), Parent = keep }))
		wallTorch(front * CFrame.new(x * 0.6, 12, 0) * CFrame.Angles(0, math.pi, 0), keep)
	end
	-- Mât et grand étendard au sommet.
	part({ Size = Vector3.new(0.5, 14, 0.5), CFrame = base * CFrame.new(0, HEIGHT + 7, 0), Material = M.Metal, Color = IRON, Parent = keep })
	decorative(part({ Size = Vector3.new(6, 3.5, 0.15), CFrame = base * CFrame.new(3.2, HEIGHT + 12, 0), Material = M.Fabric,
		Color = Color3.fromRGB(150, 32, 42), Parent = keep }))
end

---------------------------------------------------------------------------
-- L'Arène des Champions : colisée à arcades sur deux niveaux, piste de sable,
-- gradins, loge d'honneur et grande porte face à l'avenue de l'Est.
---------------------------------------------------------------------------
-- « Le Cercle des Arcanes » : terrain de duel à ciel ouvert, sans murs.
-- Estrade ronde en pierre sculptée, cercle magique gravé (runes, hexagramme),
-- six piliers élémentaires à cristal flottant, pierres runiques en lévitation
-- (animées côté client, CircleFX), bancs et bannières en retrait.
-- Le modèle garde le nom « Colosseum » (repères et scripts existants).
-- Agrandissement global du Cercle des Arcanes.
local CIRCLE_SCALE = 1.5

local function buildColosseum()
	local col = Instance.new("Model")
	col.Name = "Colosseum"
	col.Parent = World
	local c = L.Colosseum
	local base = Vector3.new(c.X, GROUND, c.Y)
	local gate = L.ColosseumGate
	local stoneDark = Color3.fromRGB(92, 88, 104)
	local stone = Color3.fromRGB(168, 160, 172)
	local marble = Color3.fromRGB(184, 180, 196)
	local gold = Color3.fromRGB(220, 175, 80)
	local arcane = Color3.fromRGB(150, 110, 255)
	local ELEMENTS = {
		{ "Feu", Color3.fromRGB(255, 120, 60) },
		{ "Eau", Color3.fromRGB(70, 165, 255) },
		{ "Nature", Color3.fromRGB(95, 205, 110) },
		{ "Foudre", Color3.fromRGB(255, 220, 70) },
		{ "Ombre", Color3.fromRGB(150, 95, 225) },
		{ "Lumiere", Color3.fromRGB(255, 240, 185) },
	}

	local function at(angleDeg: number, radius: number, y: number): Vector3
		local r = math.rad(angleDeg)
		return base + Vector3.new(math.cos(r) * radius, y, math.sin(r) * radius)
	end
	-- Repère tourné vers le centre.
	local function facing(angleDeg: number, radius: number, y: number): CFrame
		local pos = at(angleDeg, radius, y)
		return CFrame.lookAt(pos, Vector3.new(base.X, pos.Y, base.Z))
	end
	local function disc(name: string, radius: number, y0: number, y1: number, material: Enum.Material, color: Color3, deco: boolean?)
		local p = part({ Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(y1 - y0, radius * 2, radius * 2),
			CFrame = vertical(CFrame.new(base + Vector3.new(0, (y0 + y1) / 2, 0))), Material = material, Color = color, Parent = col })
		if deco then
			decorative(p)
		end
		return p
	end

	-- Estrade : deux marches, dalle de marbre.
	local TOP = GROUND + 1.8
	disc("Socle", 31, GROUND - 2, GROUND + 0.7, M.Slate, stoneDark)
	disc("Marche", 28.5, GROUND + 0.7, GROUND + 1.3, M.Limestone, stone)
	disc("Estrade", 26.5, GROUND + 1.3, TOP, M.Marble, marble)
	-- Frise sculptée : blocs dorés sur le pourtour de l'estrade.
	for i = 0, 47 do
		local a = i * 7.5
		decorative(part({ Name = "Frise", Size = Vector3.new(0.5, 0.35, 1.2), CFrame = facing(a, 26.55, TOP - 0.25), Material = M.Metal,
			Color = gold, Parent = col }))
	end

	-- Cercle magique gravé : anneaux, runes et hexagramme lumineux.
	local runes = Instance.new("Folder")
	runes.Name = "Runes"
	runes.Parent = col
	local function glow(p: BasePart)
		decorative(p)
		p.Material = M.Neon
		p.Color = arcane
		p.Transparency = 0.25
		p.Parent = runes
		return p
	end
	local G = TOP + 0.03
	-- Anneaux : un vrai trait fait de segments posés sur le pourtour (et non un
	-- disque néon caché par un disque de marbre, qui scintillait de près).
	for _, r in ipairs({ 22.5, 20.8, 9.5, 8.6 }) do
		local segments = math.max(24, math.floor(r * 4))
		local length = 2 * math.pi * r / segments + 0.08
		for k = 0, segments - 1 do
			local a = (k + 0.5) * 360 / segments
			glow(part({ Name = "Anneau", Size = Vector3.new(length, 0.06, 0.28), CFrame = facing(a, r, G) })) -- X du repère = tangente au cercle
		end
	end
	-- Runes entre les deux grands anneaux.
	for i = 0, 35 do
		local a = i * 10
		local cf = facing(a, 21.65, G + 0.02) * CFrame.Angles(0, math.rad(i % 2 == 0 and 0 or 45), 0)
		glow(part({ Name = "Rune", Size = Vector3.new(i % 3 == 0 and 0.9 or 0.5, 0.05, i % 3 == 0 and 0.25 or 0.5), CFrame = cf }))
	end
	-- Hexagramme inscrit (deux triangles).
	for t = 0, 1 do
		for k = 0, 2 do
			local a1 = gate + 90 + t * 60 + k * 120
			local a2 = a1 + 120
			local p1, p2 = at(a1, 20.6, G + 0.03), at(a2, 20.6, G + 0.03)
			local mid = (p1 + p2) / 2
			glow(part({ Name = "Trait", Size = Vector3.new(0.3, 0.05, (p2 - p1).Magnitude), CFrame = CFrame.lookAt(mid, p2) }))
		end
	end
	-- Sceau central.
	glow(part({ Name = "Sceau", Size = Vector3.new(3, 0.06, 3), CFrame = CFrame.new(base + Vector3.new(0, G + 0.04, 0)) * CFrame.Angles(0, math.rad(45), 0) }))
	local sealLight = Instance.new("PointLight")
	sealLight.Name = "Halo"
	sealLight.Color = arcane
	sealLight.Brightness = 1.2
	sealLight.Range = 26
	sealLight.Parent = runes:FindFirstChild("Sceau")

	-- Six piliers élémentaires, hors de l'estrade, avec cristal flottant.
	local pillars = Instance.new("Folder")
	pillars.Name = "Piliers"
	pillars.Parent = col
	for i, el in ipairs(ELEMENTS) do
		local a = gate + 30 + (i - 1) * 60
		local pos = at(a, 34, GROUND)
		local pillar = Instance.new("Model")
		pillar.Name = el[1]
		pillar.Parent = pillars
		part({ Name = "Base", Size = Vector3.new(4.4, 1.2, 4.4), CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0)), Material = M.Slate, Color = stoneDark, Parent = pillar })
		part({ Name = "Fut", Shape = Enum.PartType.Cylinder, Size = Vector3.new(9, 2.6, 2.6), CFrame = vertical(CFrame.new(pos + Vector3.new(0, 5.7, 0))),
			Material = M.Limestone, Color = stone, Parent = pillar })
		-- Cannelures colorées.
		for k = 0, 3 do
			decorative(part({ Name = "Veine", Size = Vector3.new(0.25, 8.2, 0.25),
				CFrame = CFrame.new(pos + Vector3.new(0, 5.7, 0)) * CFrame.Angles(0, math.rad(k * 90 + 45), 0) * CFrame.new(0, 0, 1.25),
				Material = M.Neon, Color = el[2], Transparency = 0.35, Parent = pillar }))
		end
		part({ Name = "Chapiteau", Size = Vector3.new(3.6, 0.9, 3.6), CFrame = CFrame.new(pos + Vector3.new(0, 10.6, 0)), Material = M.Marble,
			Color = marble, Parent = pillar })
		decorative(part({ Name = "Anneau", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 3.9, 3.9), CFrame = vertical(CFrame.new(pos + Vector3.new(0, 11.1, 0))),
			Material = M.Metal, Color = gold, Parent = pillar }))
		local crystal = part({ Name = "Cristal", Size = Vector3.new(1.4, 2.6, 1.4), CFrame = CFrame.new(pos + Vector3.new(0, 13.4, 0)) * CFrame.Angles(0, math.rad(45), 0),
			Material = M.Glass, Color = el[2], Transparency = 0.15, Parent = pillar })
		decorative(crystal)
		crystal:SetAttribute("Floating", true)
		local light = Instance.new("PointLight")
		light.Color = el[2]
		light.Brightness = 1.5
		light.Range = 16
		light.Parent = crystal
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Eclat"
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(el[2])
		sparks.LightEmission = 1
		sparks.Rate = 4
		sparks.Lifetime = NumberRange.new(1, 2)
		sparks.Speed = NumberRange.new(0.5, 1.5)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Size = NumberSequence.new(0.35, 0)
		sparks.Parent = crystal
		pillar:SetAttribute("Element", el[1])
	end

	-- Pierres runiques en lévitation (animées par le client).
	local stones = Instance.new("Folder")
	stones.Name = "PierresRuniques"
	stones.Parent = col
	for i = 0, 7 do
		local a = i * 45 + 22.5
		local h = 9 + (i % 3) * 2.5
		local s = part({ Name = "Pierre", Size = Vector3.new(1.6, 2.4, 0.9), CFrame = CFrame.new(at(a, 30, GROUND + h)) * CFrame.Angles(0.3, math.rad(a), 0.2),
			Material = M.Slate, Color = stoneDark, Parent = stones })
		decorative(s)
		s:SetAttribute("Floating", true)
		s:SetAttribute("Orbit", true)
		decorative(part({ Name = "Glyphe", Size = Vector3.new(0.7, 1.2, 0.05), CFrame = s.CFrame * CFrame.new(0, 0, -0.46), Material = M.Neon, Color = arcane,
			Transparency = 0.2, Parent = s }))
	end

	-- Allée d'entrée depuis la porte (vers l'ouest) et braseros qui l'encadrent.
	local gr = math.rad(gate)
	local gdir = Vector3.new(math.cos(gr), 0, math.sin(gr))
	for k = 0, 7 do
		local pos = base + gdir * (31 + k * 3.2) + Vector3.new(0, 0.05, 0)
		part({ Name = "Dalle", Size = Vector3.new(3, 0.3, 6), CFrame = CFrame.lookAt(pos, pos + gdir) * CFrame.Angles(0, math.rad(90), 0),
			Material = M.Slate, Color = stone:Lerp(stoneDark, (k % 2) * 0.3), Parent = col })
	end
	for _, s in ipairs({ -1, 1 }) do
		brazier(CFrame.new(at(gate + s * 9, 33, GROUND)), col, 0.9)
	end

	-- Bancs et bannières en retrait, bas pour ne pas gêner la vue.
	for _, a in ipairs({ gate + 60, gate + 120, gate - 60, gate - 120, gate + 180 }) do
		local cf = facing(a, 44, GROUND + 0.6)
		if not ArcanaProps.placeBench(cf, col) then
			part({ Name = "Banc", Size = Vector3.new(8, 0.6, 2), CFrame = cf, Material = M.Wood, Color = Color3.fromRGB(120, 80, 50), Parent = col })
			for _, sx in ipairs({ -3, 3 }) do
				part({ Name = "Pied", Size = Vector3.new(0.6, 1.2, 1.6), CFrame = cf * CFrame.new(sx, -0.6, 0), Material = M.Slate, Color = stoneDark, Parent = col })
			end
		end
		for _, sx in ipairs({ -6, 6 }) do
			local poleCf = cf * CFrame.new(sx, 0, 1.5)
			part({ Name = "Mat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 0.35, 0.35), CFrame = vertical(poleCf * CFrame.new(0, 3, 0)), Material = M.Wood,
				Color = Color3.fromRGB(90, 60, 40), Parent = col })
			decorative(part({ Name = "Banniere", Size = Vector3.new(1.6, 3, 0.1), CFrame = poleCf * CFrame.new(0, 4.4, -0.2), Material = M.Fabric,
				Color = sx < 0 and Color3.fromRGB(120, 30, 40) or arcane:Lerp(Color3.new(0, 0, 0), 0.35), Parent = col }))
			decorative(part({ Name = "Embleme", Size = Vector3.new(0.6, 0.6, 0.12), CFrame = poleCf * CFrame.new(0, 4.6, -0.22) * CFrame.Angles(0, 0, math.rad(45)),
				Material = M.Metal, Color = gold, Parent = col }))
		end
	end
	-- Construit à taille « intime », puis agrandi d'un bloc autour du centre.
	col.WorldPivot = CFrame.new(base)
	col:ScaleTo(CIRCLE_SCALE)
end
---------------------------------------------------------------------------
-- Prairie hors les murs : bosquets de sapins et de feuillus, hors chemins,
-- douves et abords du colisée.
---------------------------------------------------------------------------
local function buildMeadow()
	local trees = folder("Trees", World)
	local random = Random.new(77)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Terrain }
	local PINES = { Color3.fromRGB(38, 86, 52), Color3.fromRGB(46, 98, 56), Color3.fromRGB(32, 76, 50), Color3.fromRGB(52, 104, 58) }
	local LEAVES = { Color3.fromRGB(78, 128, 52), Color3.fromRGB(96, 142, 58), Color3.fromRGB(66, 112, 48), Color3.fromRGB(122, 146, 60) }
	local BARK = Color3.fromRGB(88, 62, 42)
	-- Sapin : 4 étages de cônes, plus clairs vers la pointe (lumière du ciel).
	local function pine(pos: Vector3, s: number)
		local m = Instance.new("Model")
		m.Name = "Pine"
		local tint = PINES[random:NextInteger(1, #PINES)]
		local yaw = CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(5 * s, 1.1 * s, 1.1 * s), CFrame = vertical(CFrame.new(pos + Vector3.new(0, 2.5 * s, 0))),
			Material = M.Wood, Color = BARK, Parent = m })
		for i = 0, 3 do
			local w = (8.5 - i * 1.9) * s
			local h = 4.6 * s
			local cone = part({ Size = Vector3.new(w, h, w), CFrame = CFrame.new(pos + Vector3.new(0, (4.6 + i * 2.7) * s, 0)) * yaw, Material = M.Grass,
				Color = tint:Lerp(Color3.fromRGB(110, 150, 84), i * 0.08), Parent = m })
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = "rbxassetid://1033714"
			mesh.Scale = Vector3.new(w / 2.4, h / 2.4, w / 2.4)
			mesh.Parent = cone
			decorative(cone)
		end
		m.Parent = trees
	end
	-- Feuillu : tronc, houppier en grappe de boules, ombré dessous, éclairci dessus.
	local function leafy(pos: Vector3, s: number)
		local m = Instance.new("Model")
		m.Name = "Tree"
		local tint = LEAVES[random:NextInteger(1, #LEAVES)]
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(6 * s, 1.2 * s, 1.2 * s), CFrame = vertical(CFrame.new(pos + Vector3.new(0, 3 * s, 0))),
			Material = M.Wood, Color = BARK, Parent = m })
		decorative(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7 * s, CFrame = CFrame.new(pos + Vector3.new(0, 8 * s, 0)), Material = M.Grass,
			Color = tint, Parent = m }))
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2 + random:NextNumber(0, 0.6)
			decorative(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * random:NextNumber(4, 5.2) * s,
				CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 3 * s, random:NextNumber(6.4, 7.6) * s, math.sin(a) * 3 * s)), Material = M.Grass,
				Color = tint:Lerp(Color3.fromRGB(40, 70, 36), 0.3), Parent = m }))
		end
		decorative(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 4.6 * s, CFrame = CFrame.new(pos + Vector3.new(0, 11 * s, 0)), Material = M.Grass,
			Color = tint:Lerp(Color3.fromRGB(170, 190, 90), 0.25), Parent = m }))
		m.Parent = trees
	end
	-- Buisson bas et rocher moussu pour habiller la prairie.
	local function bush(pos: Vector3, s: number)
		local m = Instance.new("Model")
		m.Name = "Bush"
		local tint = LEAVES[random:NextInteger(1, #LEAVES)]:Lerp(Color3.fromRGB(40, 70, 36), 0.15)
		for _ = 1, 3 do
			decorative(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * random:NextNumber(2.4, 3.6) * s,
				CFrame = CFrame.new(pos + Vector3.new(random:NextNumber(-1.4, 1.4) * s, 0.8 * s, random:NextNumber(-1.4, 1.4) * s)), Material = M.Grass,
				Color = tint, Parent = m }))
		end
		m.Parent = trees
	end
	local function rock(pos: Vector3, s: number)
		local m = Instance.new("Model")
		m.Name = "Rock"
		for k = 1, random:NextInteger(1, 3) do
			local size = Vector3.new(random:NextNumber(2.5, 5), random:NextNumber(1.6, 3.4), random:NextNumber(2.5, 4.5)) * s / k
			part({ Size = size, CFrame = CFrame.new(pos)
				* CFrame.new(random:NextNumber(-2, 2) * s, size.Y * 0.2, random:NextNumber(-2, 2) * s)
				* CFrame.Angles(random:NextNumber(-0.3, 0.3), random:NextNumber(0, math.pi * 2), random:NextNumber(-0.3, 0.3)),
				Material = M.Rock, Color = Color3.fromRGB(122, 118, 110):Lerp(Color3.fromRGB(96, 104, 86), random:NextNumber(0, 0.5)), Parent = m })
		end
		m.Parent = trees
	end
	local function clear(x: number, z: number): boolean
		local reach = math.max(math.abs(x), math.abs(z))
		if reach < L.MoatOuter + 8 or reach > L.Hills + 120 then
			return false
		end
		for _, r in ipairs(L.Paths) do
			if inRect(x, z, r, 7) then
				return false
			end
		end
		return (Vector2.new(x, z) - L.Colosseum).Magnitude > L.ColosseumRadius + 16
	end
	for x = -L.Hills - 120, L.Hills + 120, 13 do
		for z = -L.Hills - 120, L.Hills + 120, 13 do
			local px, pz = x + random:NextNumber(-5, 5), z + random:NextNumber(-5, 5)
			-- Bosquets : densité selon un bruit, pour des clairières et des bois.
			local density = math.noise(px / 70, pz / 70, 6.3)
			if clear(px, pz) and density > -0.05 and random:NextNumber() < 0.55 then
				local hit = workspace:Raycast(Vector3.new(px, 200, pz), Vector3.new(0, -300, 0), params)
				if hit and hit.Material ~= M.Water and hit.Normal.Y > 0.8 then
					local roll = random:NextNumber()
					if roll < 0.6 then
						pine(hit.Position, random:NextNumber(1, 1.7))
					elseif roll < 0.85 then
						leafy(hit.Position, random:NextNumber(1, 1.4))
					elseif roll < 0.95 then
						bush(hit.Position, random:NextNumber(0.9, 1.4))
					else
						rock(hit.Position, random:NextNumber(0.8, 1.6))
					end
				end
			end
		end
		task.wait()
	end
end

---------------------------------------------------------------------------
-- Limites du monde : murs invisibles sur la face extérieure des remparts.
---------------------------------------------------------------------------
local function buildBounds()
	local bounds = folder("Bounds", World)
	local height = 800
	local edge = L.Half + 0.5
	for _, data in ipairs({
		{ Vector3.new(0, 0, edge), Vector3.new(edge * 2 + 2, height, 1) },
		{ Vector3.new(0, 0, -edge), Vector3.new(edge * 2 + 2, height, 1) },
		{ Vector3.new(edge, 0, 0), Vector3.new(1, height, edge * 2 + 2) },
		{ Vector3.new(-edge, 0, 0), Vector3.new(1, height, edge * 2 + 2) },
	}) do
		local wall = part({ Name = "Boundary", Size = data[2], CFrame = CFrame.new(data[1]), Transparency = 1, Parent = bounds })
		wall.CanQuery = false
	end
	pcall(function()
		workspace.FallenPartsDestroyHeight = MIN_Y - 100
	end)
end

---------------------------------------------------------------------------
-- Éclairage et ambiance
---------------------------------------------------------------------------
local function setupLighting()
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Sky") or child:IsA("Atmosphere") then
			child:Destroy()
		end
	end

	-- NB : Lighting.Technology n'est pas modifiable par script. Pour le rendu
	-- prévu, régler Lighting > Technology sur « Future » dans Studio.
	Lighting.GeographicLatitude = 41
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ShadowSoftness = 0.15
	Lighting.GlobalShadows = true
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 10
	sky.StarCount = 4000
	sky.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.34
	atmosphere.Offset = 0.25
	atmosphere.Glare = 0.4
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.45
	bloom.Size = 28
	bloom.Threshold = 1.9
	bloom.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Intensity = 0.08
	sunRays.Spread = 0.7
	sunRays.Parent = Lighting

	local grading = Instance.new("ColorCorrectionEffect")
	grading.Brightness = 0.01
	grading.Contrast = 0.12
	grading.Saturation = 0.1
	grading.Parent = Lighting

	-- Léger flou lointain : montagnes et horizon prennent un aspect « peint ».
	local dof = Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = 0.12
	dof.FocusDistance = 40
	dof.InFocusRadius = 140
	dof.NearIntensity = 0
	dof.Parent = Lighting

	-- Ambiance par heure : chaque clé fixe luminosité, teinte du soleil,
	-- ambiances et brume. On interpole entre les clés au fil du cycle.
	local rgb = Color3.fromRGB
	local NIGHT = { Bright = 0.9, Amb = rgb(30, 34, 54), Out = rgb(74, 86, 130), Shift = rgb(130, 150, 210), Atm = rgb(70, 82, 120),
		Decay = rgb(30, 36, 62), Haze = 1.2, Expo = 0.2, Tint = rgb(222, 230, 255) }
	local DAY = { Bright = 2.9, Amb = rgb(44, 44, 54), Out = rgb(136, 138, 150), Shift = rgb(255, 240, 220), Atm = rgb(200, 216, 238),
		Decay = rgb(116, 130, 158), Haze = 1.3, Expo = 0, Tint = rgb(255, 250, 244) }
	local KEYS = {
		{ T = 0, K = NIGHT },
		{ T = 5, K = NIGHT },
		{ T = 6.5, K = { Bright = 1.8, Amb = rgb(46, 38, 48), Out = rgb(150, 120, 130), Shift = rgb(255, 165, 115), Atm = rgb(235, 186, 166),
			Decay = rgb(150, 105, 116), Haze = 2, Expo = 0.05, Tint = rgb(255, 238, 225) } },
		{ T = 9, K = DAY },
		{ T = 15, K = DAY },
		{ T = 17.3, K = { Bright = 2.5, Amb = rgb(50, 42, 40), Out = rgb(152, 132, 118), Shift = rgb(255, 196, 135), Atm = rgb(245, 208, 172),
			Decay = rgb(176, 120, 92), Haze = 1.8, Expo = 0.05, Tint = rgb(255, 240, 222) } },
		{ T = 19, K = { Bright = 1.4, Amb = rgb(42, 32, 46), Out = rgb(122, 96, 118), Shift = rgb(255, 130, 90), Atm = rgb(205, 140, 136),
			Decay = rgb(106, 62, 86), Haze = 2.2, Expo = 0.1, Tint = rgb(255, 228, 225) } },
		{ T = 20.5, K = NIGHT },
		{ T = 24, K = NIGHT },
	}
	local function lerp(a: number, b: number, t: number): number
		return a + (b - a) * t
	end
	local function apply(clock: number)
		local a, b = KEYS[1], KEYS[2]
		for i = 1, #KEYS - 1 do
			if clock >= KEYS[i].T and clock < KEYS[i + 1].T then
				a, b = KEYS[i], KEYS[i + 1]
				break
			end
		end
		local t = smoothstep(0, 1, (clock - a.T) / math.max(b.T - a.T, 0.001))
		local ka, kb = a.K, b.K
		Lighting.Brightness = lerp(ka.Bright, kb.Bright, t)
		Lighting.Ambient = ka.Amb:Lerp(kb.Amb, t)
		Lighting.OutdoorAmbient = ka.Out:Lerp(kb.Out, t)
		Lighting.ColorShift_Top = ka.Shift:Lerp(kb.Shift, t)
		Lighting.ExposureCompensation = lerp(ka.Expo, kb.Expo, t)
		atmosphere.Color = ka.Atm:Lerp(kb.Atm, t)
		atmosphere.Decay = ka.Decay:Lerp(kb.Decay, t)
		atmosphere.Haze = lerp(ka.Haze, kb.Haze, t)
		grading.TintColor = ka.Tint:Lerp(kb.Tint, t)
	end

	-- Toujours en plein jour : plus de cycle jour/nuit.
	Lighting.ClockTime = 14
	apply(Lighting.ClockTime)
end

---------------------------------------------------------------------------
setupLighting()
generateTerrain()
buildArena()
workspace:SetAttribute("WorldProgress", 0.75)
buildRamparts()
buildKeep()
buildColosseum()
buildMeadow()
buildBounds()

workspace:SetAttribute("WorldProgress", 1)
workspace:SetAttribute("WorldReady", true)

Players.CharacterAutoLoads = true
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character == nil then
		task.spawn(player.LoadCharacter, player)
	end
end
