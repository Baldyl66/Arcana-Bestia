-- Château de Brumeval : grande place autour de l'arène, forge, marché et tir
-- à l'arc, entrepôt, champs, bergerie et potager entre les remparts. PNJ R15 habillés et animés, villageois qui se promènent,
-- chasse au trésor et actions des PNJ (boutique, fusion, quêtes).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local CardsData = require(Configs:WaitForChild("CardsData"))
local VillageData = require(Configs:WaitForChild("VillageData"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CardService = require(script.Parent:WaitForChild("CardService"))
local DuelCombat = require(script.Parent:WaitForChild("DuelCombat"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NpcAction: RemoteFunction = Remotes:WaitForChild("NpcAction")
local Notify: RemoteEvent = Remotes:WaitForChild("Notify")
local DuelEvent: RemoteEvent = Remotes:WaitForChild("DuelEvent")

local ArcanaProps = require(game:GetService("ServerScriptService"):WaitForChild("ArcanaProps"))
local M = Enum.Material
local L = VillageData.Layout
local random = Random.new(2024)
-- Aléa séparé pour la végétation et le décor, pour ne pas décaler le reste.
local decoRandom = Random.new(4242)

while not workspace:GetAttribute("WorldReady") do
	workspace:GetAttributeChangedSignal("WorldReady"):Wait()
end

local Terrain = workspace.Terrain
local World = workspace:WaitForChild("World")
-- Toutes les positions sont en coordonnées monde (l'arène est à l'origine).
local center = Vector3.new(0, L.Ground, 0)
local GROUND = center.Y

local villageFolder = Instance.new("Folder")
villageFolder.Name = "Village"
villageFolder.Parent = World

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
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

local function deco(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	-- Les petits décors ne projettent pas d'ombre (gros gain de fluidité).
	p.CastShadow = false
	return p
end

local function vertical(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

local function light(parent: Instance, color: Color3, brightness: number, range: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Parent = parent
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function textSign(board: BasePart, text: string, color: Color3, font: Enum.Font?, faces: { Enum.NormalId }?)
	for _, face in ipairs(faces or { Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 1
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = text
		-- Taille calculée pour tenir sur une seule ligne, sans retour à la ligne.
		local width = (face == Enum.NormalId.Left or face == Enum.NormalId.Right) and board.Size.Z or board.Size.X
		local pixelsW, pixelsH = width * 40 * 0.88, board.Size.Y * 40 * 0.8
		label.TextScaled = false
		label.TextWrapped = false
		label.TextSize = math.floor(math.min(pixelsH * 0.85, pixelsW / (utf8.len(text) or #text) * 1.6))
		label.Font = font or Enum.Font.Fantasy
		label.TextColor3 = color
		label.Parent = gui
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.06, 0)
		padding.PaddingRight = UDim.new(0.06, 0)
		padding.PaddingTop = UDim.new(0.1, 0)
		padding.PaddingBottom = UDim.new(0.1, 0)
		padding.Parent = label
	end
end

-- Position au sol en coordonnées du village (x = est, z = sud), face à `facing`.
local function at(lx: number, lz: number, facing: Vector2?): CFrame
	local pos = Vector3.new(center.X + lx, GROUND, center.Z + lz)
	local dir = facing or Vector2.new(0, -1)
	return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Y))
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Terrain }

-- Palette resserrée : crèmes et ocres chauds, toits terre cuite ou ardoise.
-- Moins de couleurs = un village qui paraît cohérent au lieu de bariolé.
local PLASTER = {
	Color3.fromRGB(238, 228, 206), Color3.fromRGB(244, 238, 224), Color3.fromRGB(228, 208, 170),
	Color3.fromRGB(232, 214, 190), Color3.fromRGB(222, 200, 160), Color3.fromRGB(236, 220, 196),
}
local ROOFS = {
	Color3.fromRGB(168, 82, 56), Color3.fromRGB(146, 66, 48), Color3.fromRGB(124, 76, 60),
	Color3.fromRGB(86, 92, 108), Color3.fromRGB(100, 104, 118),
}
local SHUTTERS = {
	Color3.fromRGB(60, 110, 80), Color3.fromRGB(60, 90, 140), Color3.fromRGB(150, 60, 55), Color3.fromRGB(110, 80, 50),
}
local FLOWERS = {
	Color3.fromRGB(255, 110, 140), Color3.fromRGB(255, 220, 90), Color3.fromRGB(180, 130, 255),
	Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 140, 60),
}
local TIMBER = Color3.fromRGB(78, 54, 36)

---------------------------------------------------------------------------
-- Petits éléments
---------------------------------------------------------------------------
local function flowerBox(cf: CFrame, width: number, parent: Instance)
	part({ Size = Vector3.new(width, 0.6, 0.8), CFrame = cf, Material = M.WoodPlanks, Color = Color3.fromRGB(110, 75, 45), Parent = parent })
	for i = 1, math.floor(width / 0.7) do
		local x = -width / 2 + i * 0.7 - 0.35
		deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.55, 0.55, 0.55), CFrame = cf * CFrame.new(x, 0.45, 0),
			Material = M.SmoothPlastic, Color = FLOWERS[random:NextInteger(1, #FLOWERS)], Parent = parent }))
	end
end

local function window(cf: CFrame, parent: Instance, shutterColor: Color3, withBox: boolean)
	part({ Size = Vector3.new(2.8, 3.2, 0.3), CFrame = cf, Material = M.Wood, Color = TIMBER, Parent = parent })
	local glass = deco(part({ Size = Vector3.new(2.2, 2.6, 0.1), CFrame = cf * CFrame.new(0, 0, -0.12), Material = M.Glass,
		Color = Color3.fromRGB(255, 205, 135), Reflectance = 0.15, Transparency = 0.1, Parent = parent }))
	deco(part({ Size = Vector3.new(0.15, 2.6, 0.12), CFrame = cf * CFrame.new(0, 0, -0.18), Material = M.Wood, Color = TIMBER, Parent = parent }))
	deco(part({ Size = Vector3.new(2.2, 0.15, 0.12), CFrame = cf * CFrame.new(0, 0, -0.18), Material = M.Wood, Color = TIMBER, Parent = parent }))
	for _, side in ipairs({ -1, 1 }) do
		deco(part({ Size = Vector3.new(1.2, 3.2, 0.15), CFrame = cf * CFrame.new(side * 2.05, 0, -0.12), Material = M.WoodPlanks,
			Color = shutterColor, Parent = parent }))
	end
	if withBox then
		flowerBox(cf * CFrame.new(0, -1.9, -0.45), 2.8, parent)
	end
	_ = glass
end

local function wallLantern(cf: CFrame, parent: Instance)
	deco(part({ Size = Vector3.new(0.25, 0.25, 0.9), CFrame = cf * CFrame.new(0, 0, -0.45), Material = M.Metal,
		Color = Color3.fromRGB(40, 40, 45), Parent = parent }))
	local lamp = deco(part({ Size = Vector3.new(0.8, 1, 0.8), CFrame = cf * CFrame.new(0, -0.5, -0.9), Material = M.Neon,
		Color = Color3.fromRGB(255, 200, 120), Parent = parent }))
	deco(part({ Size = Vector3.new(1, 0.2, 1), CFrame = cf * CFrame.new(0, 0.05, -0.9), Material = M.Metal,
		Color = Color3.fromRGB(40, 40, 45), Parent = parent }))
	_ = lamp
end

local function lampPost(cf: CFrame, parent: Instance)
	-- Modèle 3D importé s'il est disponible.
	if ArcanaProps.placeLamp(cf, parent) then
		return
	end
	local iron = Color3.fromRGB(34, 34, 40)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 2.2, 2.2), CFrame = vertical(cf * CFrame.new(0, 0.6, 0)),
		Material = M.Slate, Color = Color3.fromRGB(70, 70, 76), Parent = parent })
	part({ Size = Vector3.new(1.4, 1.4, 1.4), CFrame = cf * CFrame.new(0, 1.9, 0), Material = M.Metal, Color = iron, Parent = parent })
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(7.6, 0.45, 0.45), CFrame = vertical(cf * CFrame.new(0, 6.3, 0)),
		Material = M.Metal, Color = iron, Parent = parent })
	for _, y in ipairs({ 3, 8.8 }) do
		deco(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.8, 0.8), CFrame = vertical(cf * CFrame.new(0, y, 0)),
			Material = M.Metal, Color = iron, Parent = parent }))
	end
	part({ Size = Vector3.new(1.7, 0.25, 1.7), CFrame = cf * CFrame.new(0, 10.15, 0), Material = M.Metal, Color = iron, Parent = parent })
	for _, x in ipairs({ -0.7, 0.7 }) do
		for _, z in ipairs({ -0.7, 0.7 }) do
			deco(part({ Size = Vector3.new(0.14, 1.8, 0.14), CFrame = cf * CFrame.new(x, 11.1, z), Material = M.Metal, Color = iron, Parent = parent }))
		end
	end
	deco(part({ Size = Vector3.new(1.3, 1.7, 1.3), CFrame = cf * CFrame.new(0, 11.1, 0), Material = M.Glass,
		Color = Color3.fromRGB(255, 225, 170), Transparency = 0.35, Parent = parent }))
	local flame = deco(part({ Size = Vector3.new(0.4, 0.8, 0.4), CFrame = cf * CFrame.new(0, 11, 0), Material = M.Neon,
		Color = Color3.fromRGB(255, 190, 100), Parent = parent }))
	light(flame, Color3.fromRGB(255, 190, 110), 1.6, 22)
	for k = 0, 1 do
		deco(part({ ClassName = "WedgePart", Size = Vector3.new(2, 0.8, 1), CFrame = cf * CFrame.new(0, 12.4, 0)
			* CFrame.Angles(0, k * math.pi, 0) * CFrame.new(0, 0, -0.5), Material = M.Metal, Color = iron, Parent = parent }))
	end
	deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.4, CFrame = cf * CFrame.new(0, 13, 0), Material = M.Metal,
		Color = Color3.fromRGB(200, 160, 70), Parent = parent }))
end

local function crate(cf: CFrame, parent: Instance, size: number?)
	local s = size or 2.4
	part({ Size = Vector3.new(s, s, s), CFrame = cf * CFrame.new(0, s / 2, 0), Material = M.WoodPlanks,
		Color = Color3.fromRGB(150, 110, 70), Parent = parent })
end

local function barrel(cf: CFrame, parent: Instance)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 2.4, 2.4), CFrame = vertical(cf * CFrame.new(0, 1.5, 0)),
		Material = M.Wood, Color = Color3.fromRGB(110, 75, 45), Parent = parent })
	for _, y in ipairs({ 0.6, 2.4 }) do
		deco(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 2.5, 2.5), CFrame = vertical(cf * CFrame.new(0, y, 0)),
			Material = M.Metal, Color = Color3.fromRGB(70, 70, 75), Parent = parent }))
	end
end

local function bench(cf: CFrame, parent: Instance)
	-- Modèle 3D importé s'il est disponible.
	if ArcanaProps.placeBench(cf, parent) then
		return
	end
	part({ Size = Vector3.new(5, 0.4, 1.4), CFrame = cf * CFrame.new(0, 1.6, 0), Material = M.WoodPlanks, Color = Color3.fromRGB(130, 90, 55), Parent = parent })
	part({ Size = Vector3.new(5, 1.4, 0.3), CFrame = cf * CFrame.new(0, 2.6, 0.6) * CFrame.Angles(math.rad(-10), 0, 0), Material = M.WoodPlanks,
		Color = Color3.fromRGB(130, 90, 55), Parent = parent })
	for _, x in ipairs({ -2.1, 2.1 }) do
		part({ Size = Vector3.new(0.4, 1.4, 1.2), CFrame = cf * CFrame.new(x, 0.7, 0), Material = M.Metal, Color = Color3.fromRGB(40, 40, 45), Parent = parent })
	end
end

local function banner(cf: CFrame, color: Color3, parent: Instance)
	part({ Size = Vector3.new(0.5, 12, 0.5), CFrame = cf * CFrame.new(0, 6, 0), Material = M.Wood, Color = TIMBER, Parent = parent })
	part({ Size = Vector3.new(3.2, 0.3, 0.3), CFrame = cf * CFrame.new(0, 11.6, -0.3), Material = M.Wood, Color = TIMBER, Parent = parent })
	local cloth = deco(part({ Size = Vector3.new(2.8, 5.5, 0.1), CFrame = cf * CFrame.new(0, 8.6, -0.35), Material = M.Fabric, Color = color, Parent = parent }))
	textSign(cloth, "◆", Color3.fromRGB(255, 210, 120), Enum.Font.GothamBlack)
end

---------------------------------------------------------------------------
-- Maison à colombages (origine au sol, façade vers -Z)
---------------------------------------------------------------------------
type HouseOptions = { W: number?, D: number?, Floors: number?, Plaster: Color3?, Roof: Color3?, Chimney: boolean? }

local function house(origin: CFrame, parent: Instance, opts: HouseOptions?): (Model, number)
	local o = opts or {}
	local m = model("House", parent)
	local w, d = o.W or random:NextInteger(13, 16), o.D or random:NextInteger(11, 13)
	local floors = o.Floors or random:NextInteger(1, 2)
	local plaster = o.Plaster or PLASTER[random:NextInteger(1, #PLASTER)]
	local roofColor = o.Roof or ROOFS[random:NextInteger(1, #ROOFS)]
	local shutter = SHUTTERS[random:NextInteger(1, #SHUTTERS)]

	part({ Name = "Foundation", Size = Vector3.new(w + 1, 2, d + 1), CFrame = origin * CFrame.new(0, 0, 0), Material = M.Cobblestone,
		Color = Color3.fromRGB(120, 115, 108), Parent = m })
	local floorH = 8
	local base = 1
	part({ Name = "GroundFloor", Size = Vector3.new(w, floorH, d), CFrame = origin * CFrame.new(0, base + floorH / 2, 0),
		Material = M.Plaster, Color = plaster, Parent = m })
	local top = base + floorH

	-- Colombages du rez-de-chaussée.
	local function frame(y0: number, height: number, width: number, depth: number, braces: boolean)
		for _, sz in ipairs({ -1, 1 }) do
			for i = 0, 4 do
				local x = -width / 2 + i * width / 4
				deco(part({ Size = Vector3.new(0.5, height, 0.3), CFrame = origin * CFrame.new(x, y0 + height / 2, sz * (depth / 2 + 0.1)),
					Material = M.Wood, Color = TIMBER, Parent = m }))
			end
			deco(part({ Size = Vector3.new(width + 0.4, 0.5, 0.35), CFrame = origin * CFrame.new(0, y0 + height - 0.25, sz * (depth / 2 + 0.12)),
				Material = M.Wood, Color = TIMBER, Parent = m }))
			if braces then
				for _, i in ipairs({ 0, 3 }) do
					local x = -width / 2 + (i + 0.5) * width / 4
					local diag = math.sqrt((width / 4) ^ 2 + height ^ 2)
					local angle = math.atan2(width / 4, height) * (i == 0 and 1 or -1)
					deco(part({ Size = Vector3.new(0.4, diag, 0.25), CFrame = origin * CFrame.new(x, y0 + height / 2, sz * (depth / 2 + 0.1))
						* CFrame.Angles(0, 0, angle), Material = M.Wood, Color = TIMBER, Parent = m }))
				end
			end
		end
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				deco(part({ Size = Vector3.new(0.7, height, 0.7), CFrame = origin * CFrame.new(sx * width / 2, y0 + height / 2, sz * depth / 2),
					Material = M.Wood, Color = TIMBER, Parent = m }))
			end
		end
	end
	frame(base, floorH, w, d, false)

	-- Porte avec auvent et lanterne.
	local front = -d / 2
	part({ Size = Vector3.new(4, 6.8, 0.3), CFrame = origin * CFrame.new(0, base + 3.4, front - 0.1), Material = M.Wood, Color = TIMBER, Parent = m })
	part({ Name = "Door", Size = Vector3.new(3.2, 6.2, 0.25), CFrame = origin * CFrame.new(0, base + 3.1, front - 0.25), Material = M.WoodPlanks,
		Color = shutter:Lerp(Color3.new(0, 0, 0), 0.25), Parent = m })
	deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), CFrame = origin * CFrame.new(1.1, base + 3, front - 0.45),
		Material = M.Metal, Color = Color3.fromRGB(220, 180, 70), Parent = m }))
	part({ ClassName = "WedgePart", Size = Vector3.new(5, 0.9, 1.8), CFrame = origin * CFrame.new(0, base + 7.4, front - 0.9),
		Material = M.ClayRoofTiles, Color = roofColor, Parent = m })
	wallLantern(origin * CFrame.new(2.8, base + 6, front), m)

	window(origin * CFrame.new(-w / 4 - 0.8, base + 4.3, front - 0.15), m, shutter, true)
	window(origin * CFrame.new(w / 4 + 0.8, base + 4.3, front - 0.15), m, shutter, true)
	window(origin * CFrame.new(0, base + 4.3, d / 2 + 0.15) * CFrame.Angles(0, math.pi, 0), m, shutter, false)
	for _, side in ipairs({ -1, 1 }) do
		window(origin * CFrame.new(side * (w / 2 + 0.15), base + 4.3, 0) * CFrame.Angles(0, -side * math.pi / 2, 0), m, shutter, false)
	end

	for _ = 2, floors do
		local upperW, upperD = w + 1, d + 1
		part({ Name = "UpperFloor", Size = Vector3.new(upperW, 7, upperD), CFrame = origin * CFrame.new(0, top + 3.5, 0),
			Material = M.Plaster, Color = plaster:Lerp(Color3.new(1, 1, 1), 0.15), Parent = m })
		frame(top, 7, upperW, upperD, true)
		for _, x in ipairs({ -upperW / 3, 0, upperW / 3 }) do
			window(origin * CFrame.new(x, top + 3.6, -upperD / 2 - 0.15), m, shutter, x ~= 0)
		end
		top += 7
		w, d = upperW, upperD
	end

	local roofH = math.max(5, d * 0.45)
	local half = d / 2 + 1
	part({ ClassName = "WedgePart", Name = "Roof", Size = Vector3.new(w + 2, roofH, half), CFrame = origin * CFrame.new(0, top + roofH / 2, -half / 2),
		Material = M.ClayRoofTiles, Color = roofColor, Parent = m })
	part({ ClassName = "WedgePart", Name = "Roof", Size = Vector3.new(w + 2, roofH, half), CFrame = origin * CFrame.new(0, top + roofH / 2, half / 2)
		* CFrame.Angles(0, math.pi, 0), Material = M.ClayRoofTiles, Color = roofColor, Parent = m })
	deco(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(w + 2.4, 0.6, 0.6), CFrame = origin * CFrame.new(0, top + roofH, 0),
		Material = M.Wood, Color = TIMBER, Parent = m }))
	-- Pignons en bois.
	for _, side in ipairs({ -1, 1 }) do
		deco(part({ Size = Vector3.new(0.3, 0.4, d + 1), CFrame = origin * CFrame.new(side * (w / 2 + 0.2), top + 0.2, 0), Material = M.Wood, Color = TIMBER, Parent = m }))
	end

	if o.Chimney ~= false and random:NextNumber() < 0.75 then
		local chimney = part({ Name = "Chimney", Size = Vector3.new(2, roofH + 2, 2), CFrame = origin * CFrame.new(w / 3, top + roofH / 2 + 1.5, d / 5),
			Material = M.Brick, Color = Color3.fromRGB(125, 72, 58), Parent = m })
		-- Fumée sur une cheminée sur cinq seulement : c'est un effet coûteux.
		if random:NextNumber() < 0.2 then
			local smoke = Instance.new("Smoke")
			smoke.Color = Color3.fromRGB(210, 210, 210)
			smoke.Opacity = 0.07
			smoke.RiseVelocity = 3
			smoke.Size = 2
			smoke.Parent = chimney
		end
	end

	return m, top
end

local function hangingSign(cf: CFrame, text: string, parent: Instance)
	cf *= CFrame.new(0, 2, 0)
	part({ Size = Vector3.new(0.3, 0.3, 2.6), CFrame = cf * CFrame.new(0, 0, -1.3), Material = M.Metal, Color = Color3.fromRGB(40, 40, 45), Parent = parent })
	local board = part({ Size = Vector3.new(0.25, 2.2, 3.4), CFrame = cf * CFrame.new(0, -1.4, -2.1), Material = M.WoodPlanks,
		Color = Color3.fromRGB(150, 110, 70), Parent = parent })
	textSign(board, text, Color3.fromRGB(60, 35, 15), Enum.Font.Fantasy, { Enum.NormalId.Left, Enum.NormalId.Right })
end

---------------------------------------------------------------------------
-- Bâtiments principaux
---------------------------------------------------------------------------
local function shop(cf: CFrame, parent: Instance)
	local m, _ = house(cf, parent, { W = 18, D = 14, Floors = 2, Plaster = Color3.fromRGB(240, 228, 205), Roof = Color3.fromRGB(150, 45, 55) })
	m.Name = "Shop"
	-- Grand auvent rayé.
	for i = 0, 7 do
		deco(part({ Size = Vector3.new(2.25, 0.2, 5), CFrame = cf * CFrame.new(-7.9 + i * 2.25, 9.3, -9.3) * CFrame.Angles(math.rad(-18), 0, 0),
			Material = M.Fabric, Color = (i % 2 == 0) and Color3.fromRGB(190, 45, 60) or Color3.fromRGB(245, 235, 215), Parent = m }))
	end
	for _, x in ipairs({ -8.6, 8.6 }) do
		part({ Size = Vector3.new(0.5, 8.5, 0.5), CFrame = cf * CFrame.new(x, 5, -11.6), Material = M.Wood, Color = TIMBER, Parent = m })
	end
	part({ Name = "Counter", Size = Vector3.new(10, 3.2, 2.2), CFrame = cf * CFrame.new(0, 2.6, -10.5), Material = M.WoodPlanks,
		Color = Color3.fromRGB(150, 105, 65), Parent = m })
	for i = -4, 4, 2 do
		local tint = CardsData.Rarities[random:NextInteger(1, #CardsData.Rarities)].Color
		for layer = 0, random:NextInteger(1, 3) do
			deco(part({ Size = Vector3.new(1.3, 0.25, 1.8), CFrame = cf * CFrame.new(i, 4.35 + layer * 0.27, -10.5)
				* CFrame.Angles(0, math.rad(random:NextNumber(-15, 15)), 0), Material = M.SmoothPlastic, Color = tint, Parent = m }))
		end
	end
	crate(cf * CFrame.new(-11, 1, -9), m)
	crate(cf * CFrame.new(-11, 3.4, -9) * CFrame.Angles(0, 0.4, 0), m, 1.8)
	barrel(cf * CFrame.new(11, 1, -9.5), m)
	hangingSign(cf * CFrame.new(10, 8.5, -7) * CFrame.Angles(0, math.pi / 2, 0), "Boutique d'Elya", m)
end

local function forge(cf: CFrame, parent: Instance)
	local m = model("Forge", parent)
	part({ Size = Vector3.new(19, 2, 15), CFrame = cf, Material = M.Cobblestone, Color = Color3.fromRGB(110, 105, 100), Parent = m })
	part({ Size = Vector3.new(18, 10, 1.5), CFrame = cf * CFrame.new(0, 6, 6.5), Material = M.Cobblestone, Color = Color3.fromRGB(125, 118, 110), Parent = m })
	for _, x in ipairs({ -8.5, 8.5 }) do
		part({ Size = Vector3.new(1.5, 4, 13), CFrame = cf * CFrame.new(x, 3, 0), Material = M.Cobblestone, Color = Color3.fromRGB(125, 118, 110), Parent = m })
	end
	for _, x in ipairs({ -8.5, 8.5 }) do
		part({ Size = Vector3.new(1, 8, 1), CFrame = cf * CFrame.new(x, 5, -6.5), Material = M.Wood, Color = TIMBER, Parent = m })
	end
	part({ ClassName = "WedgePart", Size = Vector3.new(20, 4, 16), CFrame = cf * CFrame.new(0, 13, -0.5), Material = M.RoofShingles,
		Color = Color3.fromRGB(70, 60, 55), Parent = m })
	local furnace = part({ Name = "Furnace", Size = Vector3.new(6, 6, 4), CFrame = cf * CFrame.new(-4, 4, 4), Material = M.Brick,
		Color = Color3.fromRGB(120, 70, 55), Parent = m })
	_ = furnace
	local mouth = deco(part({ Size = Vector3.new(3, 2, 0.3), CFrame = cf * CFrame.new(-4, 3, 1.9), Material = M.Neon,
		Color = Color3.fromRGB(255, 120, 40), Parent = m }))
	light(mouth, Color3.fromRGB(255, 130, 60), 3, 22)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 5
	fire.Parent = mouth
	local chimney = part({ Size = Vector3.new(2.5, 10, 2.5), CFrame = cf * CFrame.new(-4, 15, 5), Material = M.Brick,
		Color = Color3.fromRGB(105, 62, 50), Parent = m })
	local smoke = Instance.new("Smoke")
	smoke.Opacity = 0.12
	smoke.RiseVelocity = 4
	smoke.Color = Color3.fromRGB(90, 90, 90)
	smoke.Parent = chimney
	-- Enclume et creuset d'alchimie.
	part({ Size = Vector3.new(1.4, 2.2, 1.4), CFrame = cf * CFrame.new(3, 2.1, -2), Material = M.Metal, Color = Color3.fromRGB(45, 45, 50), Parent = m })
	part({ Size = Vector3.new(3.2, 0.9, 1.5), CFrame = cf * CFrame.new(3, 3.6, -2), Material = M.Metal, Color = Color3.fromRGB(60, 60, 66), Parent = m })
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 3.4, 3.4), CFrame = vertical(cf * CFrame.new(5.5, 2.1, 3)),
		Material = M.Metal, Color = Color3.fromRGB(45, 45, 50), Parent = m })
	local brew = deco(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 3, 3), CFrame = vertical(cf * CFrame.new(5.5, 3.2, 3)),
		Material = M.Neon, Color = Color3.fromRGB(120, 255, 160), Parent = m }))
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Rate = 10
	bubbles.Lifetime = NumberRange.new(0.8, 1.5)
	bubbles.Speed = NumberRange.new(2, 4)
	bubbles.SpreadAngle = Vector2.new(15, 15)
	bubbles.EmissionDirection = Enum.NormalId.Right
	bubbles.LightEmission = 1
	bubbles.Size = NumberSequence.new(0.3, 0)
	bubbles.Color = ColorSequence.new(Color3.fromRGB(150, 255, 180))
	bubbles.Parent = brew
	light(brew, Color3.fromRGB(120, 255, 160), 1.5, 12)
	-- Râtelier d'armes.
	part({ Size = Vector3.new(5, 0.4, 0.6), CFrame = cf * CFrame.new(3, 6, 5.5), Material = M.Wood, Color = TIMBER, Parent = m })
	for i = -2, 2 do
		deco(part({ Size = Vector3.new(0.25, 4, 0.1), CFrame = cf * CFrame.new(3 + i, 4.5, 5.4) * CFrame.Angles(0, 0, math.rad(i * 4)),
			Material = M.Metal, Color = Color3.fromRGB(190, 190, 200), Reflectance = 0.3, Parent = m }))
	end
	barrel(cf * CFrame.new(-8, 1, -8.5), m)
	hangingSign(cf * CFrame.new(9, 8, -6.5) * CFrame.Angles(0, math.pi / 2, 0), "Forge & Alchimie", m)
end

local houses = Instance.new("Folder")
houses.Name = "Houses"
houses.Parent = villageFolder
local props = Instance.new("Folder")
props.Name = "Props"
props.Parent = villageFolder
-- Arbres (relevés comme verdure par la carte du monde) : même dossier que
-- les sapins de la prairie construits par World.
local trees = World:FindFirstChild("Trees") or Instance.new("Folder")
trees.Name = "Trees"
trees.Parent = World

---------------------------------------------------------------------------
-- Petits éléments
---------------------------------------------------------------------------
local LEAVES = {
	Color3.fromRGB(82, 130, 54), Color3.fromRGB(98, 144, 58), Color3.fromRGB(70, 116, 50), Color3.fromRGB(124, 148, 62),
}
local LEAF_SHADE = Color3.fromRGB(38, 66, 34)
local LEAF_LIGHT = Color3.fromRGB(176, 196, 96)
local BARK = Color3.fromRGB(90, 64, 44)

-- Arbre de jardin, deux silhouettes :
-- * feuillu : tronc légèrement penché, deux branches, houppier en grappe
--   (boules du bas ombrées, boules du haut éclaircies = volume lisible) ;
-- * cyprès : colonne haute et sombre, pour varier les hauteurs.
local function tree(cf: CFrame, scale: number, parent: Instance, cypress: boolean?)
	local m = model("Tree", parent)
	local tint = LEAVES[decoRandom:NextInteger(1, #LEAVES)]
	local roll = decoRandom:NextNumber()
	if cypress == true or (cypress == nil and roll < 0.18) then
		local dark = tint:Lerp(LEAF_SHADE, 0.35)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(4 * scale, 1 * scale, 1 * scale), CFrame = vertical(cf * CFrame.new(0, 2 * scale, 0)),
			Material = M.Wood, Color = BARK, Parent = m })
		for i = 0, 5 do
			local size = (4.4 - i * 0.55) * scale
			deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, CFrame = cf * CFrame.new(0, (4.5 + i * 2.2) * scale, 0),
				Material = M.LeafyGrass, Color = dark:Lerp(LEAF_LIGHT, i * 0.04), Parent = m }))
		end
		return
	end
	local lean = cf
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(7 * scale, 1.4 * scale, 1.4 * scale), CFrame = vertical(lean * CFrame.new(0, 3.5 * scale, 0)),
		Material = M.Wood, Color = BARK, Parent = m })
	-- Évasement du pied.
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2 * scale, 2.2 * scale, 2.2 * scale), CFrame = vertical(cf * CFrame.new(0, 0.5 * scale, 0)),
		Material = M.Wood, Color = BARK, Parent = m })
	for _, side in ipairs({ -1, 1 }) do
		deco(part({ Size = Vector3.new(0.6 * scale, 4 * scale, 0.6 * scale), CFrame = lean * CFrame.new(side * 1.2 * scale, 7 * scale, 0)
			* CFrame.Angles(0, 0, math.rad(-side * 35)), Material = M.Wood, Color = BARK, Parent = m }))
	end
	local top = lean * CFrame.new(0, 9 * scale, 0)
	-- Couronne basse (ombrée), cœur, puis sommet (éclairé).
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + decoRandom:NextNumber(0, 0.5)
		local r = decoRandom:NextNumber(2.6, 3.4) * scale
		deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * decoRandom:NextNumber(4.2, 5.2) * scale,
			CFrame = top * CFrame.new(math.cos(a) * r, decoRandom:NextNumber(-1.6, -0.6) * scale, math.sin(a) * r),
			Material = M.LeafyGrass, Color = tint:Lerp(LEAF_SHADE, 0.28), Parent = m }))
	end
	deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7 * scale, CFrame = top, Material = M.LeafyGrass, Color = tint, Parent = m }))
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + 0.4
		deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 4.2 * scale, CFrame = top * CFrame.new(math.cos(a) * 1.6 * scale, 2.4 * scale, math.sin(a) * 1.6 * scale),
			Material = M.LeafyGrass, Color = tint:Lerp(LEAF_LIGHT, 0.22), Parent = m }))
	end
end

-- Buisson : trois ou quatre boules serrées, posées au ras du sol.
local function shrub(cf: CFrame, scale: number, parent: Instance)
	local m = model("Bush", parent)
	local tint = LEAVES[decoRandom:NextInteger(1, #LEAVES)]:Lerp(LEAF_SHADE, 0.12)
	for k = 1, decoRandom:NextInteger(3, 4) do
		local size = decoRandom:NextNumber(2.2, 3.4) * scale
		deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size,
			CFrame = cf * CFrame.new(decoRandom:NextNumber(-1.3, 1.3) * scale, size * 0.32, decoRandom:NextNumber(-1.3, 1.3) * scale),
			Material = M.LeafyGrass, Color = tint:Lerp(LEAF_LIGHT, k == 1 and 0.15 or 0), Parent = m }))
	end
end

-- Rocher : un à trois blocs inclinés, à moitié enfoncés.
local function boulder(cf: CFrame, scale: number, parent: Instance)
	local m = model("Rock", parent)
	for k = 1, decoRandom:NextInteger(1, 3) do
		local size = Vector3.new(decoRandom:NextNumber(1.8, 3.4), decoRandom:NextNumber(1.2, 2.4), decoRandom:NextNumber(1.6, 3)) * scale / (0.6 + k * 0.4)
		deco(part({ Size = size, CFrame = cf * CFrame.new(decoRandom:NextNumber(-1.5, 1.5) * scale, size.Y * 0.25, decoRandom:NextNumber(-1.5, 1.5) * scale)
			* CFrame.Angles(decoRandom:NextNumber(-0.35, 0.35), decoRandom:NextNumber(0, math.pi * 2), decoRandom:NextNumber(-0.35, 0.35)),
			Material = M.Rock, Color = Color3.fromRGB(128, 122, 114):Lerp(Color3.fromRGB(98, 108, 86), decoRandom:NextNumber(0, 0.5)), Parent = m }))
	end
end

-- Touffe de fleurs sauvages : feuillage bas et petites corolles d'une même couleur.
local function wildflowers(cf: CFrame, parent: Instance)
	local m = model("Wildflowers", parent)
	local petal = FLOWERS[decoRandom:NextInteger(1, #FLOWERS)]
	for _ = 1, decoRandom:NextInteger(5, 9) do
		local x, z = decoRandom:NextNumber(-2, 2), decoRandom:NextNumber(-2, 2)
		deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, CFrame = cf * CFrame.new(x, 0.2, z), Material = M.LeafyGrass,
			Color = Color3.fromRGB(70, 118, 50), Parent = m }))
		deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = cf * CFrame.new(x, 0.85, z), Material = M.SmoothPlastic,
			Color = petal, Parent = m }))
	end
end

-- Étal de marché : poteaux, auvent rayé et marchandises.
local function stall(cf: CFrame, cloth: Color3, parent: Instance)
	local m = model("Stall", parent)
	for _, x in ipairs({ -3.6, 3.6 }) do
		for _, z in ipairs({ -2, 2 }) do
			part({ Size = Vector3.new(0.4, z < 0 and 7 or 8, 0.4), CFrame = cf * CFrame.new(x, z < 0 and 3.5 or 4, z), Material = M.Wood, Color = TIMBER, Parent = m })
		end
	end
	for i = 0, 5 do
		deco(part({ Size = Vector3.new(1.35, 0.15, 5), CFrame = cf * CFrame.new(-3.4 + i * 1.36, 7.6, 0) * CFrame.Angles(math.rad(11), 0, 0),
			Material = M.Fabric, Color = (i % 2 == 0) and cloth or Color3.fromRGB(240, 230, 210), Parent = m }))
	end
	part({ Size = Vector3.new(7.6, 2.6, 2.2), CFrame = cf * CFrame.new(0, 1.3, -1), Material = M.WoodPlanks, Color = Color3.fromRGB(140, 100, 62), Parent = m })
	local goods = { Color3.fromRGB(220, 60, 50), Color3.fromRGB(240, 170, 40), Color3.fromRGB(110, 170, 60), Color3.fromRGB(150, 90, 170) }
	for x = -3, 3, 1.5 do
		local tint = goods[random:NextInteger(1, #goods)]
		for k = 0, 2 do
			deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7, CFrame = cf * CFrame.new(x + (k - 1) * 0.35, 2.9 + (k == 1 and 0.4 or 0), -1 + (k - 1) * 0.3),
				Material = M.SmoothPlastic, Color = tint, Parent = m }))
		end
	end
	crate(cf * CFrame.new(4.8, 0, 1), m, 1.6)
end

-- Puits de pierre avec treuil.
local function well(cf: CFrame, parent: Instance)
	local m = model("Well", parent)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 6, 6), CFrame = vertical(cf * CFrame.new(0, 1.3, 0)), Material = M.Cobblestone,
		Color = Color3.fromRGB(140, 132, 120), Parent = m })
	deco(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 4.6, 4.6), CFrame = vertical(cf * CFrame.new(0, 2.62, 0)), Material = M.Slate,
		Color = Color3.fromRGB(20, 26, 34), Parent = m }))
	for _, x in ipairs({ -2.7, 2.7 }) do
		part({ Size = Vector3.new(0.5, 6, 0.5), CFrame = cf * CFrame.new(x, 4, 0), Material = M.Wood, Color = TIMBER, Parent = m })
	end
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(5.8, 0.6, 0.6), CFrame = cf * CFrame.new(0, 5.5, 0), Material = M.Wood, Color = TIMBER, Parent = m })
	for k = 0, 1 do
		part({ ClassName = "WedgePart", Size = Vector3.new(7, 1.6, 2.4), CFrame = cf * CFrame.new(0, 7.8, 0) * CFrame.Angles(0, k * math.pi, 0) * CFrame.new(0, 0, -1.2),
			Material = M.RoofShingles, Color = Color3.fromRGB(120, 60, 45), Parent = m })
	end
	deco(part({ Size = Vector3.new(0.9, 1, 0.9), CFrame = cf * CFrame.new(0, 3.8, 0), Material = M.Wood, Color = Color3.fromRGB(110, 75, 45), Parent = m }))
end

---------------------------------------------------------------------------
-- Éléments du château : clôtures, cultures, moutons, cibles, granges...
---------------------------------------------------------------------------
local FENCE = Color3.fromRGB(120, 84, 50)

-- Clôture de bois entre deux points (coordonnées monde), avec une ouverture
-- optionnelle centrée sur `gapAt`.
local function fence(a: Vector2, b: Vector2, parent: Instance, gapAt: Vector2?)
	local len = (b - a).Magnitude
	local dir = (b - a).Unit
	local posts = math.max(1, math.floor(len / 4))
	for i = 0, posts do
		local p = a + dir * (len * i / posts)
		if not (gapAt and (p - gapAt).Magnitude < 3) then
			part({ Size = Vector3.new(0.5, 3, 0.5), CFrame = at(p.X, p.Y) * CFrame.new(0, 1.5, 0), Material = M.Wood, Color = FENCE, Parent = parent })
		end
	end
	for i = 0, posts - 1 do
		local p0, p1 = a + dir * (len * i / posts), a + dir * (len * (i + 1) / posts)
		local mid = (p0 + p1) / 2
		if not (gapAt and (mid - gapAt).Magnitude < 3) then
			for _, y in ipairs({ 1.2, 2.4 }) do
				local pos = Vector3.new(mid.X, GROUND + y, mid.Y)
				part({ Size = Vector3.new(0.25, 0.3, (p1 - p0).Magnitude), CFrame = CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Y)),
					Material = M.Wood, Color = FENCE, Parent = parent })
			end
		end
	end
end

-- Enclos rectangulaire clôturé, ouvert au milieu d'un côté.
local function pen(r: { Vector2 }, gateSide: string, parent: Instance)
	local a, b = r[1], r[2]
	local c1, c2 = Vector2.new(b.X, a.Y), Vector2.new(a.X, b.Y)
	local mid = (a + b) / 2
	fence(a, c1, parent, gateSide == "N" and Vector2.new(mid.X, a.Y) or nil)
	fence(c1, b, parent, gateSide == "E" and Vector2.new(b.X, mid.Y) or nil)
	fence(c2, b, parent, gateSide == "S" and Vector2.new(mid.X, b.Y) or nil)
	fence(a, c2, parent, gateSide == "W" and Vector2.new(a.X, mid.Y) or nil)
end

local CROPS = {
	Wheat = { Color3.fromRGB(222, 190, 92), Vector3.new(0.5, 2.2, 0.5) },
	Cabbage = { Color3.fromRGB(110, 170, 70), Vector3.new(1.2, 1, 1.2) },
	Pumpkin = { Color3.fromRGB(230, 130, 40), Vector3.new(1.4, 1.1, 1.4) },
	Carrot = { Color3.fromRGB(90, 160, 60), Vector3.new(0.5, 1.2, 0.5) },
}

-- Parcelle cultivée : sillons de terre et plants en rangées (le long de X).
local function crops(r: { Vector2 }, kind: string, parent: Instance)
	local crop = CROPS[kind]
	local lo, hi = r[1], r[2]
	for z = lo.Y + 1.5, hi.Y - 1.5, 3.5 do
		local pos = Vector3.new((lo.X + hi.X) / 2, GROUND + 0.25, z)
		part({ Size = Vector3.new(hi.X - lo.X - 2, 0.5, 1.6), CFrame = CFrame.new(pos), Material = M.Ground, Color = Color3.fromRGB(96, 66, 42),
			Parent = parent })
		for x = lo.X + 2, hi.X - 2, kind == "Wheat" and 1.2 or 2.6 do
			local shape = (kind == "Cabbage" or kind == "Pumpkin") and Enum.PartType.Ball or Enum.PartType.Block
			deco(part({ Shape = shape, Size = crop[2], CFrame = CFrame.new(x, GROUND + 0.5 + crop[2].Y / 2, z), Material = M.Grass,
				Color = crop[1], Parent = parent }))
		end
	end
end

-- Mouton : corps laineux, tête et pattes sombres.
local function sheep(cf: CFrame, parent: Instance)
	local m = model("Sheep", parent)
	part({ Shape = Enum.PartType.Ball, Size = Vector3.new(3.2, 2.4, 2.4), CFrame = cf * CFrame.new(0, 2.2, 0), Material = M.Fabric,
		Color = Color3.fromRGB(240, 238, 230), Parent = m })
	part({ Size = Vector3.new(1, 1.1, 1.1), CFrame = cf * CFrame.new(-1.9, 2.6, 0), Material = M.SmoothPlastic, Color = Color3.fromRGB(50, 44, 40), Parent = m })
	for _, x in ipairs({ -0.9, 0.9 }) do
		for _, z in ipairs({ -0.6, 0.6 }) do
			part({ Size = Vector3.new(0.35, 1.2, 0.35), CFrame = cf * CFrame.new(x, 0.6, z), Material = M.SmoothPlastic, Color = Color3.fromRGB(50, 44, 40), Parent = m })
		end
	end
end

-- Cible de tir à l'arc sur chevalet, tournée vers -Z.
local function target(cf: CFrame, parent: Instance)
	local m = model("Target", parent)
	for _, x in ipairs({ -1.2, 1.2 }) do
		part({ Size = Vector3.new(0.3, 5, 0.3), CFrame = cf * CFrame.new(x, 2.5, 0.6) * CFrame.Angles(math.rad(-10), 0, 0), Material = M.Wood, Color = FENCE, Parent = m })
	end
	local colors = { Color3.fromRGB(240, 235, 220), Color3.fromRGB(200, 40, 40), Color3.fromRGB(240, 235, 220), Color3.fromRGB(200, 40, 40), Color3.fromRGB(230, 190, 60) }
	for i, color in ipairs(colors) do
		local d = 3.6 - (i - 1) * 0.7
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3 + i * 0.02, d, d), CFrame = cf * CFrame.new(0, 3.6, -i * 0.02) * CFrame.Angles(0, math.pi / 2, 0),
			Material = M.Fabric, Color = color, Parent = m })
	end
end

-- Botte de foin.
local function hay(cf: CFrame, parent: Instance)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 2.6, 2.6), CFrame = cf * CFrame.new(0, 1.3, 0), Material = M.Fabric,
		Color = Color3.fromRGB(214, 180, 90), Parent = parent })
end

-- Pile de bûches.
local function woodpile(cf: CFrame, parent: Instance)
	for row = 0, 2 do
		for i = 0, 3 - row do
			part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 0.9, 0.9), CFrame = cf * CFrame.new(0, 0.45 + row * 0.8, (i - (3 - row) / 2) * 0.95),
				Material = M.Wood, Color = Color3.fromRGB(120, 82, 48), Parent = parent })
		end
	end
end

-- Grange / entrepôt : murs de planches, grand toit, double porte vers -Z.
local function barn(cf: CFrame, w: number, d: number, parent: Instance)
	local m = model("Warehouse", parent)
	local h = 11
	part({ Size = Vector3.new(w, 1, d), CFrame = cf * CFrame.new(0, 0.5, 0), Material = M.Cobblestone, Color = Color3.fromRGB(120, 115, 108), Parent = m })
	part({ Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, 1 + h / 2, 0), Material = M.WoodPlanks, Color = Color3.fromRGB(150, 108, 66), Parent = m })
	for _, x in ipairs({ -w / 2, 0, w / 2 }) do
		for _, z in ipairs({ -d / 2, d / 2 }) do
			deco(part({ Size = Vector3.new(0.9, h, 0.9), CFrame = cf * CFrame.new(x, 1 + h / 2, z), Material = M.Wood, Color = TIMBER, Parent = m }))
		end
	end
	local roofH = d * 0.4
	for k = 0, 1 do
		part({ ClassName = "WedgePart", Size = Vector3.new(w + 2, roofH, d / 2 + 1), CFrame = cf * CFrame.new(0, 1 + h + roofH / 2, 0) * CFrame.Angles(0, k * math.pi, 0)
			* CFrame.new(0, 0, -(d / 2 + 1) / 2), Material = M.WoodPlanks, Color = Color3.fromRGB(110, 78, 50), Parent = m })
	end
	part({ Size = Vector3.new(10, 9, 0.4), CFrame = cf * CFrame.new(0, 5.5, -d / 2 - 0.2), Material = M.WoodPlanks, Color = Color3.fromRGB(110, 70, 40), Parent = m })
	for _, s in ipairs({ -1, 1 }) do
		deco(part({ Size = Vector3.new(0.4, 9, 0.2), CFrame = cf * CFrame.new(s * 2.5, 5.5, -d / 2 - 0.45) * CFrame.Angles(0, 0, s * math.rad(29)),
			Material = M.Wood, Color = TIMBER, Parent = m }))
	end
	return m
end

-- Épouvantail.
local function scarecrow(cf: CFrame, parent: Instance)
	local m = model("Scarecrow", parent)
	part({ Size = Vector3.new(0.4, 6, 0.4), CFrame = cf * CFrame.new(0, 3, 0), Material = M.Wood, Color = FENCE, Parent = m })
	part({ Size = Vector3.new(4, 0.4, 0.4), CFrame = cf * CFrame.new(0, 4.5, 0), Material = M.Wood, Color = FENCE, Parent = m })
	part({ Size = Vector3.new(2.2, 2.4, 1), CFrame = cf * CFrame.new(0, 4.2, 0), Material = M.Fabric, Color = Color3.fromRGB(150, 60, 50), Parent = m })
	part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, CFrame = cf * CFrame.new(0, 6.2, 0), Material = M.Fabric, Color = Color3.fromRGB(220, 190, 120), Parent = m })
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.6, 2.6), CFrame = vertical(cf * CFrame.new(0, 6.8, 0)), Material = M.Fabric,
		Color = Color3.fromRGB(110, 80, 40), Parent = m })
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 1.2, 1.2), CFrame = vertical(cf * CFrame.new(0, 7.3, 0)), Material = M.Fabric,
		Color = Color3.fromRGB(110, 80, 40), Parent = m })
end

-- Charrette à deux roues.
local function cart(cf: CFrame, parent: Instance, load: Color3?)
	local m = model("Cart", parent)
	part({ Size = Vector3.new(4, 0.4, 6), CFrame = cf * CFrame.new(0, 2.2, 0), Material = M.WoodPlanks, Color = Color3.fromRGB(140, 100, 60), Parent = m })
	for _, x in ipairs({ -2, 2 }) do
		part({ Size = Vector3.new(0.3, 1.2, 6), CFrame = cf * CFrame.new(x, 2.9, 0), Material = M.WoodPlanks, Color = Color3.fromRGB(120, 84, 50), Parent = m })
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3.6, 3.6), CFrame = cf * CFrame.new(x * 1.15, 1.8, 0.5), Material = M.Wood,
			Color = Color3.fromRGB(80, 56, 34), Parent = m })
	end
	for _, x in ipairs({ -0.8, 0.8 }) do
		part({ Size = Vector3.new(0.3, 0.3, 4), CFrame = cf * CFrame.new(x, 2, -4.6), Material = M.Wood, Color = Color3.fromRGB(120, 84, 50), Parent = m })
	end
	if load then
		deco(part({ Size = Vector3.new(3.4, 1.2, 5), CFrame = cf * CFrame.new(0, 3.1, 0), Material = M.Fabric, Color = load, Parent = m }))
	end
end

-- Mannequin d'entraînement : poteau, sac de paille et bras.
local function dummy(cf: CFrame, parent: Instance)
	local m = model("Dummy", parent)
	part({ Size = Vector3.new(0.5, 5, 0.5), CFrame = cf * CFrame.new(0, 2.5, 0), Material = M.Wood, Color = FENCE, Parent = m })
	part({ Size = Vector3.new(1.8, 2.4, 1.2), CFrame = cf * CFrame.new(0, 4, 0), Material = M.Fabric, Color = Color3.fromRGB(214, 180, 90), Parent = m })
	part({ Size = Vector3.new(4, 0.4, 0.4), CFrame = cf * CFrame.new(0, 4.6, 0), Material = M.Wood, Color = FENCE, Parent = m })
	part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3, CFrame = cf * CFrame.new(0, 5.8, 0), Material = M.Fabric, Color = Color3.fromRGB(214, 180, 90), Parent = m })
end

-- Cheval : corps, cou, tête et pattes.
local function horse(cf: CFrame, color: Color3, parent: Instance)
	local m = model("Horse", parent)
	part({ Size = Vector3.new(4.6, 2.2, 1.8), CFrame = cf * CFrame.new(0, 3.6, 0), Material = M.SmoothPlastic, Color = color, Parent = m })
	part({ Size = Vector3.new(1.2, 2.4, 1), CFrame = cf * CFrame.new(-2.4, 4.8, 0) * CFrame.Angles(0, 0, math.rad(-30)), Material = M.SmoothPlastic, Color = color, Parent = m })
	part({ Size = Vector3.new(2, 0.9, 0.9), CFrame = cf * CFrame.new(-3.4, 5.6, 0), Material = M.SmoothPlastic, Color = color, Parent = m })
	deco(part({ Size = Vector3.new(1.6, 1.6, 0.3), CFrame = cf * CFrame.new(-2.2, 5.2, 0), Material = M.Fabric, Color = Color3.fromRGB(40, 30, 24), Parent = m }))
	for _, x in ipairs({ -1.8, 1.8 }) do
		for _, z in ipairs({ -0.6, 0.6 }) do
			part({ Size = Vector3.new(0.5, 2.6, 0.5), CFrame = cf * CFrame.new(x, 1.3, z), Material = M.SmoothPlastic, Color = color, Parent = m })
		end
	end
end

-- Moulin à vent : tour de pierre, toit conique et ailes.
local function windmill(c: Vector2, parent: Instance)
	local m = model("Windmill", parent)
	local cf = at(c.X, c.Y, (-c).Unit)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(22, 12, 12), CFrame = vertical(cf * CFrame.new(0, 11, 0)), Material = M.Cobblestone,
		Color = Color3.fromRGB(196, 186, 168), Parent = m })
	for i = 0, 5 do
		local d = 14 * (1 - i / 6)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, d, d), CFrame = vertical(cf * CFrame.new(0, 22.5 + i * 1.3, 0)), Material = M.ClayRoofTiles,
			Color = Color3.fromRGB(176, 72, 46), Parent = m })
	end
	part({ Size = Vector3.new(4, 7, 0.4), CFrame = cf * CFrame.new(0, 3.5, -6), Material = M.WoodPlanks, Color = Color3.fromRGB(110, 70, 40), Parent = m })
	local hub = cf * CFrame.new(0, 19, -6.8)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = hub * CFrame.Angles(0, math.pi / 2, 0), Material = M.Wood, Color = TIMBER,
		Parent = m })
	for i = 0, 3 do
		local arm = hub * CFrame.Angles(0, 0, i * math.pi / 2 + 0.3)
		part({ Size = Vector3.new(0.5, 14, 0.4), CFrame = arm * CFrame.new(0, 7.5, -0.4), Material = M.Wood, Color = TIMBER, Parent = m })
		deco(part({ Size = Vector3.new(3, 11, 0.15), CFrame = arm * CFrame.new(1.7, 8.5, -0.5), Material = M.Fabric, Color = Color3.fromRGB(236, 226, 205),
			Parent = m }))
	end
end

-- Chapelle : nef en pierre, toit à deux pans, clocher et vitrail.
local function chapel(cf: CFrame, parent: Instance)
	local m = model("Chapel", parent)
	local stone = Color3.fromRGB(205, 196, 180)
	part({ Size = Vector3.new(18, 1, 30), CFrame = cf * CFrame.new(0, 0.5, 0), Material = M.Limestone, Color = Color3.fromRGB(160, 150, 138), Parent = m })
	part({ Size = Vector3.new(16, 14, 28), CFrame = cf * CFrame.new(0, 8, 0), Material = M.Limestone, Color = stone, Parent = m })
	for k = 0, 1 do
		part({ ClassName = "WedgePart", Size = Vector3.new(30, 7, 9.5), CFrame = cf * CFrame.new(0, 18.5, 0) * CFrame.Angles(0, k * math.pi + math.pi / 2, 0)
			* CFrame.new(0, 0, -4.75), Material = M.ClayRoofTiles, Color = Color3.fromRGB(176, 72, 46), Parent = m })
	end
	local bell = cf * CFrame.new(0, 0, -12)
	part({ Size = Vector3.new(7, 30, 7), CFrame = bell * CFrame.new(0, 15, 0), Material = M.Limestone, Color = stone, Parent = m })
	part({ ClassName = "WedgePart", Size = Vector3.new(7.6, 8, 3.8), CFrame = bell * CFrame.new(0, 34, -1.9), Material = M.ClayRoofTiles,
		Color = Color3.fromRGB(176, 72, 46), Parent = m })
	part({ ClassName = "WedgePart", Size = Vector3.new(7.6, 8, 3.8), CFrame = bell * CFrame.new(0, 34, 1.9) * CFrame.Angles(0, math.pi, 0),
		Material = M.ClayRoofTiles, Color = Color3.fromRGB(176, 72, 46), Parent = m })
	local glass = deco(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 5, 5), CFrame = bell * CFrame.new(0, 22, -3.6) * CFrame.Angles(0, math.pi / 2, 0),
		Material = M.Neon, Color = Color3.fromRGB(120, 150, 255), Parent = m }))
	light(glass, Color3.fromRGB(140, 160, 255), 1.2, 18)
	part({ Size = Vector3.new(4, 7, 0.4), CFrame = bell * CFrame.new(0, 3.5, -3.6), Material = M.WoodPlanks, Color = TIMBER, Parent = m })
	for _, z in ipairs({ -4, 4, 10 }) do
		for _, side in ipairs({ -1, 1 }) do
			deco(part({ Size = Vector3.new(0.3, 5, 2), CFrame = cf * CFrame.new(side * 8.1, 9, z), Material = M.Glass, Color = Color3.fromRGB(180, 140, 255),
				Transparency = 0.1, Parent = m }))
		end
	end
end

-- Bassin rond avec margelle et jet d'eau.
local function pond(c: Vector2, radius: number, parent: Instance)
	local cf = at(c.X, c.Y)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, radius * 2 + 3, radius * 2 + 3), CFrame = vertical(cf * CFrame.new(0, 0.5, 0)),
		Material = M.Marble, Color = Color3.fromRGB(226, 220, 208), Parent = parent })
	deco(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, radius * 2, radius * 2), CFrame = vertical(cf * CFrame.new(0, 1.25, 0)),
		Material = M.Glass, Color = Color3.fromRGB(60, 150, 180), Transparency = 0.25, Reflectance = 0.3, Parent = parent }))
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 2, 2), CFrame = vertical(cf * CFrame.new(0, 2.5, 0)), Material = M.Marble,
		Color = Color3.fromRGB(230, 222, 210), Parent = parent })
	local nozzle = deco(part({ Size = Vector3.one * 0.5, CFrame = cf * CFrame.new(0, 4.6, 0), Transparency = 1, Parent = parent }))
	local spray = Instance.new("ParticleEmitter")
	spray.Rate = 50
	spray.Lifetime = NumberRange.new(0.8, 1.1)
	spray.Speed = NumberRange.new(9, 12)
	spray.SpreadAngle = Vector2.new(14, 14)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.Size = NumberSequence.new(0.25, 0.1)
	spray.Transparency = NumberSequence.new(0.2, 0.8)
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = nozzle
end

-- Jardin d'angle : pelouse dégagée traversée par le sentier, deux bancs
-- au fond (côté opposé à la place) pour ne pas gêner le passage.
local function flowerGarden(c: Vector2, parent: Instance)
	local m = model("FlowerGarden", parent)
	local toPlaza = -c.Unit
	for i = 0, 3 do
		local a = i * math.pi / 2
		local dir = Vector2.new(math.cos(a), math.sin(a))
		if dir:Dot(toPlaza) < 0 then
			bench(at(c.X + dir.X * 15, c.Y + dir.Y * 15, -dir) * CFrame.Angles(0, math.pi, 0), m)
		end
	end
end

---------------------------------------------------------------------------
-- Construction du château (plan en grille 3 × 3, voir VillageData.Layout)
---------------------------------------------------------------------------
local NORTH, SOUTH, EAST, WEST = Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(1, 0), Vector2.new(-1, 0)
local treasureSpots: { Vector3 } = {}
local function spot(x: number, z: number)
	table.insert(treasureSpots, Vector3.new(x, GROUND, z))
end
local CLOTHS = { Color3.fromRGB(190, 50, 60), Color3.fromRGB(60, 110, 170), Color3.fromRGB(70, 140, 80), Color3.fromRGB(220, 170, 50),
	Color3.fromRGB(140, 70, 160), Color3.fromRGB(230, 120, 50) }
local STONE = Color3.fromRGB(120, 112, 104)
local RED = Color3.fromRGB(150, 32, 42)

-- Muret de pierre entre deux points, ouvert autour de `gaps`.
local function lowWall(a: Vector2, b: Vector2, parent: Instance, gaps: { Vector2 }?)
	local len = (b - a).Magnitude
	local dir = (b - a).Unit
	local t = 0
	while t < len do
		local seg = math.min(6, len - t)
		local mid = a + dir * (t + seg / 2)
		local open = false
		for _, g in ipairs(gaps or {}) do
			if (mid - g).Magnitude < 9 then
				open = true
			end
		end
		if not open then
			local pos = Vector3.new(mid.X, GROUND + 1.6, mid.Y)
			part({ Size = Vector3.new(1.6, 3.2, seg + 0.05), CFrame = CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Y)), Material = M.Cobblestone,
				Color = STONE, Parent = parent })
		end
		t += seg
	end
end

-- Brasero sur socle de pierre.
local function brazierPost(cf: CFrame, parent: Instance)
	part({ Size = Vector3.new(2, 4, 2), CFrame = cf * CFrame.new(0, 2, 0), Material = M.Cobblestone, Color = STONE, Parent = parent })
	local coals = deco(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 2.4, 2.4), CFrame = vertical(cf * CFrame.new(0, 4.3, 0)), Material = M.Neon,
		Color = Color3.fromRGB(255, 120, 40), Parent = parent }))
	local f = Instance.new("Fire")
	f.Size = 3
	f.Heat = 6
	f.Parent = coals
	light(coals, Color3.fromRGB(255, 150, 70), 2, 20)
end

-- Atelier ouvert : poteaux, toit en pente, établi, enclume ou outils, enseigne.
local function shed(cf: CFrame, label: string, parent: Instance, sparks: boolean?)
	local m = model("Workshop", parent)
	for _, x in ipairs({ -7, 7 }) do
		for _, z in ipairs({ -4.5, 4.5 }) do
			part({ Size = Vector3.new(0.7, z < 0 and 8 or 9.5, 0.7), CFrame = cf * CFrame.new(x, z < 0 and 4 or 4.75, z), Material = M.Wood, Color = TIMBER, Parent = m })
		end
	end
	part({ Size = Vector3.new(16, 0.5, 11), CFrame = cf * CFrame.new(0, 9, 0) * CFrame.Angles(math.rad(-8), 0, 0), Material = M.RoofShingles,
		Color = Color3.fromRGB(110, 60, 45), Parent = m })
	part({ Size = Vector3.new(10, 3, 2.4), CFrame = cf * CFrame.new(0, 1.5, 3), Material = M.WoodPlanks, Color = Color3.fromRGB(130, 90, 55), Parent = m })
	part({ Size = Vector3.new(1.2, 2, 1.2), CFrame = cf * CFrame.new(-4, 1, -1), Material = M.Metal, Color = Color3.fromRGB(45, 45, 50), Parent = m })
	local anvil = part({ Size = Vector3.new(2.6, 0.8, 1.2), CFrame = cf * CFrame.new(-4, 2.4, -1), Material = M.Metal, Color = Color3.fromRGB(60, 60, 66), Parent = m })
	if sparks then
		local e = Instance.new("ParticleEmitter")
		e.Rate = 4
		e.Lifetime = NumberRange.new(0.3, 0.6)
		e.Speed = NumberRange.new(6, 10)
		e.SpreadAngle = Vector2.new(60, 60)
		e.Acceleration = Vector3.new(0, -25, 0)
		e.EmissionDirection = Enum.NormalId.Top
		e.LightEmission = 1
		e.Size = NumberSequence.new(0.15, 0)
		e.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90))
		e.Parent = anvil
	end
	for i = -2, 2 do
		deco(part({ Size = Vector3.new(0.2, 2.4, 0.15), CFrame = cf * CFrame.new(i * 1.4, 4.6, 4.3) * CFrame.Angles(0, 0, math.rad(i * 6)), Material = M.Metal,
			Color = Color3.fromRGB(180, 180, 190), Parent = m }))
	end
	hangingSign(cf * CFrame.new(8, 6.5, -4.5) * CFrame.Angles(0, math.pi / 2, 0), label, m)
	return m
end

-- Râtelier d'armes.
local function weaponRack(cf: CFrame, parent: Instance)
	part({ Size = Vector3.new(6, 0.4, 0.6), CFrame = cf * CFrame.new(0, 3.4, 0), Material = M.Wood, Color = TIMBER, Parent = parent })
	for _, x in ipairs({ -2.6, 2.6 }) do
		part({ Size = Vector3.new(0.4, 3.6, 0.4), CFrame = cf * CFrame.new(x, 1.8, 0), Material = M.Wood, Color = TIMBER, Parent = parent })
	end
	for k = -2, 2 do
		deco(part({ Size = Vector3.new(0.2, 3.6, 0.1), CFrame = cf * CFrame.new(k, 2.2, -0.25), Material = M.Metal, Color = Color3.fromRGB(190, 190, 200),
			Reflectance = 0.3, Parent = parent }))
	end
end

-- Cadre de séchage des peaux (tanneur).
local function hideRack(cf: CFrame, parent: Instance)
	for _, x in ipairs({ -2.5, 2.5 }) do
		part({ Size = Vector3.new(0.4, 5, 0.4), CFrame = cf * CFrame.new(x, 2.5, 0), Material = M.Wood, Color = TIMBER, Parent = parent })
	end
	part({ Size = Vector3.new(5.6, 0.3, 0.3), CFrame = cf * CFrame.new(0, 4.9, 0), Material = M.Wood, Color = TIMBER, Parent = parent })
	deco(part({ Size = Vector3.new(4.2, 3.6, 0.1), CFrame = cf * CFrame.new(0, 2.9, 0), Material = M.Fabric,
		Color = Color3.fromRGB(150 + random:NextInteger(-15, 15), 105, 70), Parent = parent }))
end

-- Fil à linge entre deux poteaux, avec du linge coloré.
local function laundry(a: Vector2, b: Vector2, parent: Instance)
	for _, p in ipairs({ a, b }) do
		part({ Size = Vector3.new(0.3, 5, 0.3), CFrame = at(p.X, p.Y) * CFrame.new(0, 2.5, 0), Material = M.Wood, Color = TIMBER, Parent = parent })
	end
	local pa, pb = Vector3.new(a.X, GROUND + 4.8, a.Y), Vector3.new(b.X, GROUND + 4.8, b.Y)
	deco(part({ Size = Vector3.new(0.08, 0.08, (pb - pa).Magnitude), CFrame = CFrame.lookAt((pa + pb) / 2, pb), Material = M.Fabric,
		Color = Color3.fromRGB(230, 225, 210), Parent = parent }))
	local n = math.floor((pb - pa).Magnitude / 1.6)
	for i = 1, n - 1 do
		if random:NextNumber() < 0.7 then
			local p = pa:Lerp(pb, i / n)
			deco(part({ Size = Vector3.new(0.05, random:NextNumber(1, 1.8), 1.1), CFrame = CFrame.lookAt(p, pb) * CFrame.new(0, -0.8, 0) * CFrame.Angles(0, math.pi / 2, 0),
				Material = M.Fabric, Color = CLOTHS[random:NextInteger(1, #CLOTHS)], Parent = parent }))
		end
	end
end

-- Statue de champion sur socle.
local function statue(cf: CFrame, parent: Instance)
	local m = model("Statue", parent)
	local marble = Color3.fromRGB(230, 225, 214)
	part({ Size = Vector3.new(5, 3, 5), CFrame = cf * CFrame.new(0, 1.5, 0), Material = M.Limestone, Color = Color3.fromRGB(170, 160, 146), Parent = m })
	part({ Size = Vector3.new(2.2, 3, 1.2), CFrame = cf * CFrame.new(0, 5.6, 0), Material = M.Marble, Color = marble, Parent = m })
	part({ Size = Vector3.new(2.6, 2.4, 1.4), CFrame = cf * CFrame.new(0, 8.3, 0), Material = M.Marble, Color = marble, Parent = m })
	part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = cf * CFrame.new(0, 10.3, 0), Material = M.Marble, Color = marble, Parent = m })
	part({ Size = Vector3.new(0.3, 6, 0.3), CFrame = cf * CFrame.new(1.8, 9, -0.6) * CFrame.Angles(0, 0, math.rad(-10)), Material = M.Marble, Color = marble, Parent = m })
	part({ Size = Vector3.new(0.3, 2.4, 2), CFrame = cf * CFrame.new(-1.6, 8, -0.4), Material = M.Marble, Color = marble, Parent = m })
end

-- Rangée de maisons alignées dont la façade donne sur la rue (facing) :
-- même gabarit, étages en alternance 2 / 3, tonneau et fleurs en alternance.
local function houseRow(x0: number, x1: number, z: number, facing: Vector2, step: number, parent: Instance)
	local i = 0
	for x = x0, x1, step do
		local cf = at(x, z, facing)
		house(cf, parent, { W = 14, D = 11, Floors = 2 + i % 2 })
		local front = cf * CFrame.new(5, 0, -8)
		if i % 2 == 0 then
			barrel(front, props)
		else
			wildflowers(front, props)
		end
		i += 1
	end
end

-- Sentier des jardins : peint directement dans le terrain (pavés, comme les
-- rues, voir World), seuls les lampadaires face à face sont ajoutés ici.
local function naturalPath(a: Vector2, b: Vector2, width: number, parent: Instance)
	local m = model("NaturalPath", parent)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local side = Vector2.new(-dir.Y, dir.X)
	for ld = 14, length - 8, 26 do
		local p = a + dir * ld
		for _, s in ipairs({ -1, 1 }) do
			local q = p + side * s * (width / 2 + 2.5)
			lampPost(at(q.X, q.Y), m)
		end
	end
end


---------------------------------------------------------------------------
-- Centre : place de l'arène, jardins d'angle, lampadaires
---------------------------------------------------------------------------
for i = 0, 15 do
	local a = i / 16 * math.pi * 2 + math.pi / 16
	local p = Vector2.new(math.cos(a), math.sin(a)) * (L.Plaza - 3)
	-- Pairs + les bancs qui bordent l'entrée des avenues : lampadaire des deux côtés.
	if i % 2 == 0 or i % 4 == 3 then
		lampPost(at(p.X, p.Y), props)
	else
		bench(at(p.X, p.Y, -p.Unit), props)
	end
end
for _, dir in ipairs({ NORTH, SOUTH, EAST, WEST }) do
	local side = Vector2.new(-dir.Y, dir.X)
	for _, s in ipairs({ -1, 1 }) do
		local p = dir * (L.Plaza + 3) + side * s * 12
		-- Tournés vers la place : on voit leur face décorée en arrivant au centre.
		banner(at(p.X, p.Y, -dir), RED, props)
	end
end
for _, c in ipairs(L.Gardens) do
	flowerGarden(c, props)
	spot(c.X + 10, c.Y + 10)
end

---------------------------------------------------------------------------
-- Nord : donjon (World) et cour d'honneur
---------------------------------------------------------------------------
do
	local court = model("HonorCourt", props)
	local r = L.HonorCourt
	for _, z in ipairs({ -160, -205 }) do
		for _, x in ipairs({ -30, 30 }) do
			statue(at(x, z, SOUTH), court)
		end
	end
	for _, x in ipairs({ -60, 60 }) do
		for z = -225, -150, 25 do
			brazierPost(at(x, z), court)
		end
		for z = -215, -160, 25 do
			banner(at(x * 1.35, z, SOUTH), RED, court)
		end
	end
	lowWall(Vector2.new(r[1].X, r[1].Y), Vector2.new(r[1].X, r[2].Y), court)
	lowWall(Vector2.new(r[2].X, r[1].Y), Vector2.new(r[2].X, r[2].Y), court)
	spot(r[1].X + 6, r[2].Y - 6)
end

---------------------------------------------------------------------------
-- Sud : Grand-Place du marché
---------------------------------------------------------------------------
local shopCf = at(-62, 292, NORTH)
shop(shopCf, villageFolder)
do
	local F = L.Fountain
	local market = model("MarketSquare", props)
	-- Grande fontaine à deux vasques, entourée de massifs fleuris.
	do
		local cf = at(F.X, F.Y)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 24, 24), CFrame = vertical(cf * CFrame.new(0, 0.6, 0)), Material = M.Marble,
			Color = Color3.fromRGB(226, 220, 208), Parent = market })
		deco(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 21, 21), CFrame = vertical(cf * CFrame.new(0, 1.45, 0)), Material = M.Glass,
			Color = Color3.fromRGB(60, 150, 180), Transparency = 0.25, Reflectance = 0.3, Parent = market }))
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 3, 3), CFrame = vertical(cf * CFrame.new(0, 3.5, 0)), Material = M.Marble,
			Color = Color3.fromRGB(230, 222, 210), Parent = market })
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 10, 10), CFrame = vertical(cf * CFrame.new(0, 6.2, 0)), Material = M.Marble,
			Color = Color3.fromRGB(230, 222, 210), Parent = market })
		deco(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 9, 9), CFrame = vertical(cf * CFrame.new(0, 6.65, 0)), Material = M.Glass,
			Color = Color3.fromRGB(60, 150, 180), Transparency = 0.25, Parent = market }))
		local crystal = deco(part({ Size = Vector3.new(1.6, 3, 1.6), CFrame = cf * CFrame.new(0, 10, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			Material = M.Neon, Color = Color3.fromRGB(255, 200, 110), Parent = market }))
		light(crystal, Color3.fromRGB(255, 200, 120), 2, 26)
		local nozzle = deco(part({ Size = Vector3.one * 0.5, CFrame = cf * CFrame.new(0, 8, 0), Transparency = 1, Parent = market }))
		local spray = Instance.new("ParticleEmitter")
		spray.Rate = 70
		spray.Lifetime = NumberRange.new(0.9, 1.2)
		spray.Speed = NumberRange.new(10, 13)
		spray.SpreadAngle = Vector2.new(20, 20)
		spray.Acceleration = Vector3.new(0, -30, 0)
		spray.Size = NumberSequence.new(0.25, 0.1)
		spray.Transparency = NumberSequence.new(0.2, 0.8)
		spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
		spray.EmissionDirection = Enum.NormalId.Top
		spray.Parent = nozzle
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			local bed = at(F.X + math.cos(a) * 15.5, F.Y + math.sin(a) * 15.5)
			part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 4, 4), CFrame = vertical(bed * CFrame.new(0, 0.5, 0)), Material = M.Cobblestone,
				Color = Color3.fromRGB(150, 140, 128), Parent = market })
			for _ = 1, 6 do
				deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, CFrame = bed * CFrame.new(random:NextNumber(-1.2, 1.2), 1.3, random:NextNumber(-1.2, 1.2)),
					Material = M.SmoothPlastic, Color = FLOWERS[random:NextInteger(1, #FLOWERS)], Parent = market }))
			end
		end
	end
	-- Étals en couronne autour de la fontaine, ouverts sur l'avenue.
	local index = 0
	for _, deg in ipairs({ 20, 50, 130, 160, 200, 235, 305, 340 }) do
		index += 1
		local a = math.rad(deg)
		local p = F + Vector2.new(math.cos(a), math.sin(a)) * 38
		stall(at(p.X, p.Y, (F - p).Unit), CLOTHS[(index - 1) % #CLOTHS + 1], market)
	end
	-- Guirlandes lumineuses et fanions entre des mâts.
	local poles = {}
	-- Mâts décalés de l'axe nord-sud : aucun ne se dresse sur l'avenue.
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local p = F + Vector2.new(math.cos(a), math.sin(a)) * 54
		local cf = at(p.X, p.Y)
		part({ Size = Vector3.new(0.6, 12, 0.6), CFrame = cf * CFrame.new(0, 6, 0), Material = M.Wood, Color = TIMBER, Parent = market })
		deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, CFrame = cf * CFrame.new(0, 12.3, 0), Material = M.Metal,
			Color = Color3.fromRGB(220, 175, 80), Parent = market }))
		table.insert(poles, (cf * CFrame.new(0, 11.5, 0)).Position)
	end
	local bulbColors = { Color3.fromRGB(255, 210, 120), Color3.fromRGB(255, 150, 90), Color3.fromRGB(150, 210, 255) }
	for i, a in ipairs(poles) do
		local b = poles[i % #poles + 1]
		for k = 1, 9 do
			local t = k / 10
			local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * 2.4, 0)
			local bulb = deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = CFrame.new(p), Material = M.Neon,
				Color = bulbColors[(k + i) % #bulbColors + 1], Parent = market }))
			if k == 5 and i % 2 == 0 then
				light(bulb, Color3.fromRGB(255, 200, 130), 0.8, 14)
			end
		end
		for k = 1, 7 do
			local t = k / 8
			local p = a:Lerp(b, t) - Vector3.new(0, 3 + math.sin(t * math.pi) * 2, 0)
			deco(part({ ClassName = "WedgePart", Size = Vector3.new(0.05, 1.4, 1), CFrame = CFrame.lookAt(p, p + (b - a).Unit) * CFrame.Angles(0, math.pi / 2, math.pi),
				Material = M.Fabric, Color = CLOTHS[(k + i) % #CLOTHS + 1], Parent = market }))
		end
	end
	-- Halle aux grains au fond de la place, face à la boutique d'Elya.
	do
		local cf = at(62, 292, NORTH)
		local hall = model("MarketHall", market)
		part({ Size = Vector3.new(36, 1, 22), CFrame = cf * CFrame.new(0, 0.5, 0), Material = M.Cobblestone, Color = Color3.fromRGB(140, 132, 120), Parent = hall })
		for x = -16, 16, 8 do
			for _, z in ipairs({ -10, 10 }) do
				part({ Size = Vector3.new(1, 11, 1), CFrame = cf * CFrame.new(x, 6.5, z), Material = M.Wood, Color = TIMBER, Parent = hall })
			end
		end
		for _, z in ipairs({ -10, 10 }) do
			part({ Size = Vector3.new(34, 1, 1), CFrame = cf * CFrame.new(0, 12, z), Material = M.Wood, Color = TIMBER, Parent = hall })
		end
		for k = 0, 1 do
			part({ ClassName = "WedgePart", Size = Vector3.new(38, 7, 13), CFrame = cf * CFrame.new(0, 16, 0) * CFrame.Angles(0, k * math.pi, 0) * CFrame.new(0, 0, -6.5),
				Material = M.ClayRoofTiles, Color = Color3.fromRGB(176, 72, 46), Parent = hall })
		end
		local goods = { Color3.fromRGB(220, 60, 50), Color3.fromRGB(240, 170, 40), Color3.fromRGB(110, 170, 60), Color3.fromRGB(150, 90, 170), Color3.fromRGB(230, 210, 150) }
		for x = -12, 12, 8 do
			part({ Size = Vector3.new(6, 2.6, 8), CFrame = cf * CFrame.new(x, 2.3, 0), Material = M.WoodPlanks, Color = Color3.fromRGB(140, 100, 62), Parent = hall })
			for _ = 1, 10 do
				deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, CFrame = cf * CFrame.new(x + random:NextNumber(-2.4, 2.4), 3.9, random:NextNumber(-3.4, 3.4)),
					Material = M.SmoothPlastic, Color = goods[random:NextInteger(1, #goods)], Parent = hall }))
			end
		end
		local board = deco(part({ Size = Vector3.new(14, 2.2, 0.3), CFrame = cf * CFrame.new(0, 13.4, -10.6), Material = M.WoodPlanks,
			Color = Color3.fromRGB(110, 70, 40), Parent = hall }))
		textSign(board, "HALLE AUX GRAINS", Color3.fromRGB(255, 220, 140), Enum.Font.Fantasy, { Enum.NormalId.Front })
		for _, x in ipairs({ -12, 12 }) do
			wallLantern(cf * CFrame.new(x, 10, -10.5), hall)
		end
	end
	-- Bacs à fleurs, caisses, tonneaux et charrettes aux bords de la place.
	for _, c in ipairs({ { -88, 300 }, { 88, 300 }, { -30, 305 }, { 30, 305 }, { -60, 150 }, { 60, 150 } }) do
		local cf = at(c[1], c[2])
		part({ Size = Vector3.new(5, 1.6, 3), CFrame = cf * CFrame.new(0, 0.8, 0), Material = M.WoodPlanks, Color = Color3.fromRGB(110, 75, 45), Parent = market })
		for _ = 1, 8 do
			deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, CFrame = cf * CFrame.new(random:NextNumber(-2, 2), 1.9, random:NextNumber(-1, 1)),
				Material = M.SmoothPlastic, Color = FLOWERS[random:NextInteger(1, #FLOWERS)], Parent = market }))
		end
	end
	for _, c in ipairs({ { -88, 152 }, { 88, 285 }, { -60, 310 } }) do
		crate(at(c[1], c[2]), market)
		barrel(at(c[1] + 3.5, c[2] + 1), market)
	end
	-- Boutiques alignées sur les deux côtés de la place, façades vers la fontaine.
	local shopsW = { "Fromagerie", "Boulangerie", "Herboriste", "Épices", "Tissus" }
	local shopsE = { "Boucherie", "Bijoutier", "Potier", "Chandelier", "Librairie" }
	for i, z in ipairs({ 168, 192, 216, 240, 264 }) do
		for _, data in ipairs({ { -105.5, EAST, shopsW[i] }, { 105.5, WEST, shopsE[i] } }) do
			local cf = at(data[1], z, data[2])
			local m = house(cf, houses, { W = 14, D = 11, Floors = 2 + i % 2 })
			m.Name = data[3]
			hangingSign(cf * CFrame.new(6.5, 8, -5.7) * CFrame.Angles(0, math.pi / 2, 0), data[3], m)
			-- Auvent rayé au-dessus de la porte.
			local cloth = CLOTHS[(i + (data[1] > 0 and 2 or 0)) % #CLOTHS + 1]
			for k = 0, 3 do
				deco(part({ Size = Vector3.new(1.6, 0.15, 3), CFrame = cf * CFrame.new(-2.4 + k * 1.6, 8.2, -7) * CFrame.Angles(math.rad(-18), 0, 0),
					Material = M.Fabric, Color = (k % 2 == 0) and cloth or Color3.fromRGB(240, 230, 210), Parent = m }))
			end
			-- Petit étalage devant la boutique.
			local front = cf * CFrame.new(-4.5, 0, -9)
			part({ Size = Vector3.new(4, 2.4, 1.6), CFrame = front * CFrame.new(0, 1.2, 0), Material = M.WoodPlanks, Color = Color3.fromRGB(140, 100, 62), Parent = m })
			for _ = 1, 6 do
				deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7, CFrame = front * CFrame.new(random:NextNumber(-1.6, 1.6), 2.7, random:NextNumber(-0.5, 0.5)),
					Material = M.SmoothPlastic, Color = CLOTHS[random:NextInteger(1, #CLOTHS)], Parent = m }))
			end
		end
	end
	cart(at(-80, 290, NORTH), market, Color3.fromRGB(220, 170, 50))
	cart(at(80, 150, SOUTH), market, Color3.fromRGB(110, 170, 70))
	for _, c in ipairs({ { -108, 144 }, { 108, 144 }, { -108, 314 }, { 108, 314 } }) do
		banner(at(c[1], c[2], NORTH), RED, market)
	end
	spot(-108, 160)
	spot(108, 300)
end

---------------------------------------------------------------------------
-- Est : abords du colisée
---------------------------------------------------------------------------
-- Parvis du Colisée sans fanions : seuls les braseros encadrent l'entrée.
for _, z in ipairs({ -40, 40 }) do
	brazierPost(at(150, z), props)
end

---------------------------------------------------------------------------
-- Ouest : quartier des artisans (forge de Borin, haut fourneau, ateliers)
---------------------------------------------------------------------------
local forgeCf = at(L.Forge.X, L.Forge.Y, SOUTH)
do
	local r = L.ArtisanYard
	local yard = model("Artisans", props)
	forge(forgeCf, villageFolder)
	-- Muret autour du quartier, ouvert sur l'avenue et le boulevard.
	local c1, c2 = Vector2.new(r[2].X, r[1].Y), Vector2.new(r[1].X, r[2].Y)
	lowWall(r[1], c1, yard)
	lowWall(c2, r[2], yard)
	lowWall(c1, r[2], yard, { Vector2.new(r[2].X, 0) })
	-- Haut fourneau : tour de brique, gueule incandescente, fumée, coulée.
	do
		local cf = at(-298, -82, EAST)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(16, 11, 11), CFrame = vertical(cf * CFrame.new(0, 8, 0)), Material = M.Brick,
			Color = Color3.fromRGB(120, 70, 55), Parent = yard })
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 5, 5), CFrame = vertical(cf * CFrame.new(0, 21, 0)), Material = M.Brick,
			Color = Color3.fromRGB(100, 60, 48), Parent = yard })
		local mouth = deco(part({ Size = Vector3.new(4, 3.5, 0.4), CFrame = cf * CFrame.new(0, 3, -5.4), Material = M.Neon, Color = Color3.fromRGB(255, 120, 40),
			Parent = yard }))
		light(mouth, Color3.fromRGB(255, 130, 60), 3, 26)
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 6
		fire.Parent = mouth
		local top = deco(part({ Size = Vector3.one, CFrame = cf * CFrame.new(0, 26.5, 0), Transparency = 1, Parent = yard }))
		local smoke = Instance.new("Smoke")
		smoke.Opacity = 0.18
		smoke.RiseVelocity = 6
		smoke.Size = 4
		smoke.Color = Color3.fromRGB(80, 80, 80)
		smoke.Parent = top
		deco(part({ Size = Vector3.new(1.2, 0.3, 10), CFrame = cf * CFrame.new(0, 1.4, -11), Material = M.Neon, Color = Color3.fromRGB(255, 150, 50), Parent = yard }))
		part({ Size = Vector3.new(4, 1.2, 3), CFrame = cf * CFrame.new(0, 0.6, -17), Material = M.Slate, Color = Color3.fromRGB(60, 58, 62), Parent = yard })
		-- Minerai et charbon au pied du fourneau.
		for _, data in ipairs({ { -312, -100, Color3.fromRGB(70, 66, 72) }, { -312, -64, Color3.fromRGB(30, 28, 30) } }) do
			-- Tas en pyramide : 3 × 3 blocs, puis un au sommet.
			for i = 0, 8 do
				deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2,
					CFrame = at(data[1] + (i % 3 - 1) * 1.9, data[2] + (i // 3 - 1) * 1.9) * CFrame.new(0, 0.8, 0),
					Material = M.Slate, Color = data[3], Parent = yard }))
			end
			deco(part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = at(data[1], data[2]) * CFrame.new(0, 2.4, 0),
				Material = M.Slate, Color = data[3], Parent = yard }))
		end
	end
	-- Ateliers : armurier, coutelier, tanneur, menuisier.
	shed(at(-290, 60, NORTH), "Armurier", yard, true)
	shed(at(-245, 60, NORTH), "Coutelier", yard, true)
	shed(at(-200, 60, NORTH), "Tanneur", yard)
	shed(at(-170, -85, SOUTH), "Menuisier", yard)
	-- Tanneur : cadres de séchage des peaux.
	for i = 0, 3 do
		hideRack(at(-205 + i * 7, 88, NORTH), yard)
	end
	-- Menuisier : piles de bois et chevalet.
	woodpile(at(-190, -95, EAST), yard)
	woodpile(at(-150, -95, EAST), yard)
	part({ Size = Vector3.new(4, 0.4, 1), CFrame = at(-170, -65) * CFrame.new(0, 2.6, 0), Material = M.Wood, Color = TIMBER, Parent = yard })
	-- Armurier : râteliers et mannequins en armure.
	for i = 0, 2 do
		weaponRack(at(-305 + i * 9, 32, NORTH), yard)
	end
	for _, x in ipairs({ -275, -262 }) do
		local cf = at(x, 30, NORTH)
		part({ Size = Vector3.new(0.4, 3, 0.4), CFrame = cf * CFrame.new(0, 1.5, 0), Material = M.Wood, Color = TIMBER, Parent = yard })
		part({ Size = Vector3.new(2.4, 2.6, 1.4), CFrame = cf * CFrame.new(0, 4.2, 0), Material = M.Metal, Color = Color3.fromRGB(170, 170, 180), Reflectance = 0.2,
			Parent = yard })
		part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.5, CFrame = cf * CFrame.new(0, 6.2, 0), Material = M.Metal, Color = Color3.fromRGB(150, 150, 160),
			Parent = yard })
	end
	-- Abreuvoir de trempe, puits, charrette de minerai, tonneaux.
	part({ Size = Vector3.new(7, 1.6, 3), CFrame = at(-205, -30) * CFrame.new(0, 0.8, 0), Material = M.Wood, Color = Color3.fromRGB(100, 70, 45), Parent = yard })
	deco(part({ Size = Vector3.new(6.4, 0.2, 2.4), CFrame = at(-205, -30) * CFrame.new(0, 1.55, 0), Material = M.Glass, Color = Color3.fromRGB(60, 120, 150),
		Transparency = 0.3, Parent = yard }))
	well(at(-180, -30), yard)
	cart(at(-270, -95, EAST), yard, Color3.fromRGB(60, 58, 62))
	for _, c in ipairs({ { -212, -62 }, { -215, -59 }, { -258, -62 }, { -150, 40 }, { -153, 44 } }) do
		barrel(at(c[1], c[2]), yard)
	end
	-- Étal d'outils sur l'avenue.
	stall(at(-150, -25, SOUTH), Color3.fromRGB(110, 90, 70), yard)
	stall(at(-150, 25, NORTH), Color3.fromRGB(150, 60, 50), yard)
	for _, x in ipairs({ -320, -140 }) do
		brazierPost(at(x + (x < 0 and 6 or 0), -14), yard)
		brazierPost(at(x + (x < 0 and 6 or 0), 14), yard)
	end
	-- Deux maisons d'artisans au fond de la cour, côté ouest (les ateliers
	-- occupent déjà les bords nord et sud).
	for _, z in ipairs({ -55, -33 }) do
		house(at(-315, z, EAST), houses, { W = 14, D = 11, Floors = 2 })
	end
	-- Alignement d'arbres en bacs de part et d'autre de l'avenue.
	for x = -300, -170, 26 do
		for _, z in ipairs({ -15, 15 }) do
			local cf = at(x, z)
			part({ Size = Vector3.new(4, 1.4, 4), CFrame = cf * CFrame.new(0, 0.7, 0), Material = M.Cobblestone, Color = STONE, Parent = yard })
			tree(cf * CFrame.new(0, 1.4, 0), 0.8, trees)
		end
	end
	-- Teinturerie : cuves de couleur et tissus qui sèchent.
	local dyes = { Color3.fromRGB(170, 40, 50), Color3.fromRGB(50, 80, 160), Color3.fromRGB(220, 170, 40), Color3.fromRGB(70, 130, 70), Color3.fromRGB(120, 60, 140) }
	for i, color in ipairs(dyes) do
		local cf = at(-300 + (i - 1) * 9, 82)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 5.4, 5.4), CFrame = vertical(cf * CFrame.new(0, 1.3, 0)), Material = M.Wood,
			Color = Color3.fromRGB(110, 75, 45), Parent = yard })
		deco(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 4.8, 4.8), CFrame = vertical(cf * CFrame.new(0, 2.5, 0)), Material = M.SmoothPlastic,
			Color = color, Parent = yard }))
	end
	laundry(Vector2.new(-302, 70), Vector2.new(-262, 70), yard)
	hangingSign(at(-270, 82, NORTH) * CFrame.new(0, 2, -4) * CFrame.Angles(0, math.pi / 2, 0), "Teinturier", yard)
	-- Entrepôt de bois du menuisier et charron, au sud-est de la cour.
	barn(at(-220, 82, NORTH), 16, 14, yard).Name = "Woodshed"
	for _, x in ipairs({ -250, -238 }) do
		woodpile(at(x, 70, EAST), yard)
	end
	for i = 0, 2 do
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 3.6, 3.6), CFrame = at(-170 + i * 3, 75) * CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, math.rad(8)),
			Material = M.Wood, Color = Color3.fromRGB(80, 56, 34), Parent = yard })
	end
	cart(at(-180, 72, WEST), yard)
	-- Bancs et tables de travail en bordure.
	for _, x in ipairs({ -287, -235 }) do
		bench(at(x, -20, NORTH) * CFrame.Angles(0, math.pi, 0), yard)
		bench(at(x, 20, SOUTH) * CFrame.Angles(0, math.pi, 0), yard)
	end
	spot(-300, -40)
	spot(-160, 95)
end

---------------------------------------------------------------------------
-- Nord-est : caserne (logis des gardes, entraînement, écurie)
---------------------------------------------------------------------------
do
	local barracks = model("Barracks", props)
	-- Logis des gardes : deux longs bâtiments et une tente de commandement.
	for _, x in ipairs({ 190, 270 }) do
		local m = house(at(x, -300, SOUTH), villageFolder, { W = 34, D = 14, Floors = 2, Plaster = Color3.fromRGB(215, 205, 190), Roof = Color3.fromRGB(110, 60, 45) })
		m.Name = "Barracks"
	end
	hangingSign(at(190, -300, SOUTH) * CFrame.new(18, 8, -8) * CFrame.Angles(0, math.pi / 2, 0), "Caserne", props)
	for i, c in ipairs({ { 165, -255 }, { 300, -255 } }) do
		local tent = model("Tent", barracks)
		local cf = at(c[1], c[2], SOUTH)
		for k = 0, 1 do
			part({ ClassName = "WedgePart", Size = Vector3.new(8, 6, 4), CFrame = cf * CFrame.new(0, 3, 0) * CFrame.Angles(0, k * math.pi, 0) * CFrame.new(0, 0, -2),
				Material = M.Fabric, Color = i == 1 and RED or Color3.fromRGB(236, 226, 205), Parent = tent })
		end
	end
	for i = 0, 3 do
		weaponRack(at(205 + i * 14, -250, SOUTH), barracks)
	end
	for _, c in ipairs({ { 150, -300 }, { 150, -290 }, { 315, -300 } }) do
		crate(at(c[1], c[2]), barracks)
		crate(at(c[1], c[2]) * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, 0.3, 0), barracks, 2)
	end
	-- Terrain d'entraînement : cibles, mannequins, bottes de foin.
	local r = L.TrainingYard
	pen(r, "S", barracks)
	for i = 0, 3 do
		target(at(r[1].X + 15 + i * 22, r[1].Y + 10, SOUTH) * CFrame.Angles(0, math.pi, 0), barracks)
	end
	for i = 0, 5 do
		dummy(at(r[1].X + 15 + (i % 3) * 30, r[1].Y + 38 + (i // 3) * 18), barracks)
	end
	for _, x in ipairs({ r[1].X + 8, r[2].X - 8 }) do
		hay(at(x, r[2].Y - 8), barracks)
	end
	-- Écurie et paddock.
	local s = L.StableYard
	local stable = barn(at(s[2].X - 14, (s[1].Y + s[2].Y) / 2, WEST), 18, 26, barracks)
	stable.Name = "Stable"
	local paddock = { Vector2.new(s[1].X + 2, s[1].Y + 4), Vector2.new(s[2].X - 28, s[2].Y - 4) }
	pen(paddock, "W", barracks)
	local colors = { Color3.fromRGB(120, 80, 50), Color3.fromRGB(60, 45, 35), Color3.fromRGB(220, 210, 195) }
	for i = 1, 3 do
		horse(at(paddock[1].X + 12, paddock[1].Y + i * 16, WEST), colors[i], barracks)
	end
	hay(at(paddock[2].X - 5, paddock[2].Y - 5), barracks)
	spot(r[2].X + 4, r[2].Y + 4)
	spot(160, -300)
end

---------------------------------------------------------------------------
-- Sud-est : entrepôts et potager
---------------------------------------------------------------------------
local barnCf = at(205, 176, WEST)
barn(barnCf, 22, 30, villageFolder)
do
	local depot = model("Depot", props)
	local barn2 = barn(at(285, 176, WEST), 18, 24, depot)
	barn2.Name = "Granary"
	for _, c in ipairs({ { 150, 150 }, { 155, 156 }, { 150, 200 }, { 240, 150 }, { 245, 156 }, { 240, 205 }, { 315, 150 } }) do
		crate(at(c[1], c[2]), depot)
		crate(at(c[1], c[2]) * CFrame.new(0, 2.4, 0), depot, 2)
	end
	for _, c in ipairs({ { 160, 165 }, { 250, 195 }, { 252, 160 } }) do
		barrel(at(c[1], c[2]), depot)
	end
	cart(at(165, 190, NORTH), depot, Color3.fromRGB(150, 110, 70))
	cart(at(255, 178, NORTH), depot)
	-- Potager clos.
	local g = L.VegetableGarden
	local garden = model("VegetableGarden", depot)
	pen(g, "N", garden)
	local third = (g[2].X - g[1].X) / 3
	crops({ g[1] + Vector2.new(4, 4), Vector2.new(g[1].X + third - 3, g[2].Y - 4) }, "Cabbage", garden)
	crops({ Vector2.new(g[1].X + third + 3, g[1].Y + 4), Vector2.new(g[1].X + 2 * third - 3, g[2].Y - 4) }, "Pumpkin", garden)
	crops({ Vector2.new(g[1].X + 2 * third + 3, g[1].Y + 4), g[2] - Vector2.new(4, 4) }, "Carrot", garden)
	scarecrow(at(g[1].X + third, (g[1].Y + g[2].Y) / 2), garden)
	spot(g[1].X - 4, g[1].Y - 4)
	spot(315, 205)
end

---------------------------------------------------------------------------
-- Sud-ouest : quartier des maisons (ruelle, rue, chapelle, bassin)
---------------------------------------------------------------------------
do
	local hood = model("Neighbourhood", props)
	-- Une seule rue (z 187-195) bordée de deux rangées de maisons qui se font
	-- face, avec une trouée au milieu pour l'allée dallée vers la chapelle.
	houseRow(-310, -254, 174, SOUTH, 28, houses)
	houseRow(-196, -154, 174, SOUTH, 28, houses)
	houseRow(-310, -254, 208, NORTH, 28, houses)
	houseRow(-196, -154, 208, NORTH, 28, houses)
	-- Chapelle et parvis, bassin et petit square.
	chapel(at(-180, 290, NORTH), villageFolder)
	pond(Vector2.new(-270, 285), 9, hood)
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		bench(at(-270 + math.cos(a) * 15, 285 + math.sin(a) * 15, Vector2.new(-math.cos(a), -math.sin(a))) * CFrame.Angles(0, math.pi, 0), hood)
	end
	for _, c in ipairs({ { -300, 262 }, { -240, 262 }, { -300, 310 }, { -240, 310 } }) do
		tree(at(c[1], c[2]), 1, trees)
	end
	-- Fils à linge dans les arrière-cours, puits et lampadaires dans la rue.
	laundry(Vector2.new(-300, 160), Vector2.new(-285, 160), hood)
	laundry(Vector2.new(-190, 160), Vector2.new(-175, 160), hood)
	laundry(Vector2.new(-300, 222), Vector2.new(-285, 222), hood)
	well(at(-150, 160), hood)
	for x = -310, -190, 40 do
		lampPost(at(x + 14, 185), hood)
		lampPost(at(x + 34, 197), hood)
	end
	cart(at(-300, 240, EAST), hood, Color3.fromRGB(214, 180, 90))
	spot(-150, 300)
	spot(-315, 191)
end

---------------------------------------------------------------------------
-- Nord-ouest : ferme (champs, moulin, bergerie)
---------------------------------------------------------------------------
do
	local f = L.Fields
	local farm = model("Farm", props)
	local w = (f[2].X - f[1].X) / 3
	crops({ f[1] + Vector2.new(4, 4), Vector2.new(f[1].X + w - 3, f[2].Y - 4) }, "Wheat", farm)
	crops({ Vector2.new(f[1].X + w + 3, f[1].Y + 4), Vector2.new(f[1].X + 2 * w - 3, f[2].Y - 4) }, "Wheat", farm)
	crops({ Vector2.new(f[1].X + 2 * w + 3, f[1].Y + 4), f[2] - Vector2.new(4, 4) }, "Cabbage", farm)
	pen(f, "S", farm)
	scarecrow(at(f[1].X + w / 2, (f[1].Y + f[2].Y) / 2), farm)
	windmill(L.Windmill, farm)
	-- Bergerie : enclos, moutons, cabane, foin.
	local r = L.SheepPen
	pen(r, "E", farm)
	-- Troupeau en rangs : 5 × 2, tous tournés vers la porte de l'enclos.
	for i = 0, 9 do
		sheep(at(r[1].X + 16 + (i % 5) * 20, r[1].Y + 20 + (i // 5) * 30, EAST), farm)
	end
	part({ Size = Vector3.new(10, 1.2, 2), CFrame = at(r[2].X - 12, r[1].Y + 8) * CFrame.new(0, 0.6, 0), Material = M.Wood, Color = FENCE, Parent = farm })
	barn(at(-170, -150, WEST), 14, 18, farm).Name = "Sheepfold"
	for _, x in ipairs({ -200, -196, -192 }) do
		hay(at(x, -200), farm)
	end
	cart(at(-150, -240, WEST), farm, Color3.fromRGB(214, 180, 90))
	spot(f[2].X + 4, f[1].Y + 6)
	spot(r[1].X + 6, r[2].Y + 4)
end

---------------------------------------------------------------------------
-- Arbres alignés le long des rues, et un peu de verdure basse.
---------------------------------------------------------------------------
do
	local zones = { L.HonorCourt, L.MarketSquare, L.ArtisanYard, L.BarracksYard, L.TrainingYard, L.StableYard, L.WarehouseYard,
		L.VegetableGarden, L.Houses, L.Fields, L.SheepPen }
	local function free(x: number, z: number, margin: number): boolean
		local p = Vector2.new(x, z)
		if p.Magnitude < L.Plaza + 6 or math.max(math.abs(x), math.abs(z)) > L.Wall - 8 then
			return false
		end
		-- Parvis du Colisée dégagé (deux arbres symétriques l'encadrent, posés plus bas).
		local gateDir = Vector2.new(math.cos(math.rad(L.ColosseumGate)), math.sin(math.rad(L.ColosseumGate)))
		if (p - (L.Colosseum + gateDir * L.ColosseumRadius)).Magnitude < 50 then
			return false
		end
		if (p - L.Colosseum).Magnitude < L.ColosseumRadius + 10 or (p - L.Windmill).Magnitude < 14 or (p - Vector2.new(0, -280)).Magnitude < 40 then
			return false
		end
		for _, g in ipairs(L.Gardens) do
			if (p - g).Magnitude < 18 then
				return false
			end
		end
		for _, seg in ipairs(L.StonePaths) do
			local ab = seg[2] - seg[1]
			local t = math.clamp((p - seg[1]):Dot(ab) / ab:Dot(ab), 0, 1)
			if (p - (seg[1] + ab * t)).Magnitude < seg[3] / 2 + margin + 2 then
				return false
			end
		end
		for _, list in ipairs({ zones, L.Paths }) do
			for _, r in ipairs(list) do
				if x > r[1].X - margin and x < r[2].X + margin and z > r[1].Y - margin and z < r[2].Y + margin then
					return false
				end
			end
		end
		return true
	end
	-- Alignements : un arbre tous les 26 studs de part et d'autre de chaque rue,
	-- même taille et même orientation ; un buisson fleuri au pied d'un arbre sur deux.
	for _, r in ipairs(L.Paths) do
		local size = r[2] - r[1]
		local horizontal = size.X >= size.Y
		local len = horizontal and size.X or size.Y
		local index = 0
		for t = 8, len - 8, 26 do
			index += 1
			for _, sideOff in ipairs({ -6, 6 }) do
				local x = horizontal and (r[1].X + t) or (sideOff < 0 and r[1].X + sideOff or r[2].X + sideOff)
				local z = horizontal and (sideOff < 0 and r[1].Y + sideOff or r[2].Y + sideOff) or (r[1].Y + t)
				if free(x, z, 3) then
					tree(at(x, z), 1, trees)
					if index % 2 == 0 then
						local out = horizontal and Vector2.new(0, math.sign(sideOff) * 4) or Vector2.new(math.sign(sideOff) * 4, 0)
						-- Buisson et fleurs seulement s'ils restent hors des champs et des cours.
						if free(x + out.X * 1.8, z + out.Y * 1.8, 2) then
							shrub(at(x + out.X, z + out.Y), 1, trees)
							wildflowers(at(x + out.X * 1.8, z + out.Y * 1.8), props)
						end
					end
				end
			end
		end
	end
	-- Deux arbres feuillus symétriques de part et d'autre du parvis du Colisée.
	do
		local gateDir = Vector2.new(math.cos(math.rad(L.ColosseumGate)), math.sin(math.rad(L.ColosseumGate)))
		local side = Vector2.new(-gateDir.Y, gateDir.X)
		local front = L.Colosseum + gateDir * (L.ColosseumRadius + 14)
		for _, s in ipairs({ -1, 1 }) do
			local q = front + side * s * 30
			tree(at(q.X, q.Y), 1, trees, false)
		end
	end
	-- Allées en dalles de pierre entre les quartiers.
	local paths = model("StonePaths", props)
	for _, seg in ipairs(L.StonePaths) do
		-- Toutes les allées sont pavées dans le terrain (même sol que les rues) :
		-- plus de dalles posées par-dessus, seulement les lampadaires.
		naturalPath(seg[1], seg[2], seg[3], paths)
	end
end

-- Lampadaires le long des avenues.
for d = 140, 320, 30 do
	-- Avenue sud : la fontaine de la Grand-Place reste dégagée.
	local nearFountain = math.abs(d - L.Fountain.Y) < 25
	if not nearFountain then
		lampPost(at(-11, d), props)
	end
	-- Avenue nord : pas de lampadaires devant le donjon.
	if d < 230 then
		lampPost(at(11, -d), props)
	end
	lampPost(at(-d, -11), props)
	-- Côté opposé de chaque avenue.
	if not nearFountain then
		lampPost(at(11, d), props)
	end
	if d < 230 then
		lampPost(at(-11, -d), props)
	end
	lampPost(at(-d, 11), props)
end
-- Avenue est : pas de lampadaires devant l'entrée du Colisée.

-- Comptoir des Merveilles : kiosque de la boutique Robux sur la grande place.
do
	local k = at(-34, 158, NORTH)
	local m = model("WonderKiosk", props)
	local violet, gold = Color3.fromRGB(95, 55, 160), Color3.fromRGB(225, 180, 80)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 9, 9), CFrame = vertical(k * CFrame.new(0, 0.4, 0)), Material = M.Marble,
		Color = Color3.fromRGB(225, 220, 235), Parent = m })
	-- Comptoir en arc de cercle.
	for i = -3, 3 do
		local a = math.rad(i * 22)
		local cf = k * CFrame.Angles(0, a, 0) * CFrame.new(0, 2, -3.2)
		part({ Size = Vector3.new(1.35, 2.4, 0.9), CFrame = cf, Material = M.WoodPlanks, Color = violet, Parent = m })
		deco(part({ Size = Vector3.new(1.4, 0.25, 1.2), CFrame = cf * CFrame.new(0, 1.3, 0), Material = M.Metal, Color = gold, Reflectance = 0.2, Parent = m }))
	end
	-- Colonnes, coupole et cristal flottant.
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, 0.5, 0.5), CFrame = vertical(k * CFrame.new(math.cos(a) * 4, 4.6, math.sin(a) * 4)),
			Material = M.Metal, Color = gold, Parent = m })
	end
	local dome = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(10, 10, 10), CFrame = k * CFrame.new(0, 8.6, 0), Material = M.Fabric, Color = violet, Parent = m })
	local cut2 = Instance.new("SpecialMesh")
	cut2.MeshType = Enum.MeshType.Sphere
	cut2.Scale = Vector3.new(1, 0.45, 1)
	cut2.Parent = dome
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 10.2, 10.2), CFrame = vertical(k * CFrame.new(0, 8.6, 0)), Material = M.Metal, Color = gold, Parent = m })
	local crystal = deco(part({ Size = Vector3.new(1.4, 2.6, 1.4), CFrame = k * CFrame.new(0, 12.4, 0) * CFrame.Angles(0, math.rad(45), 0), Material = M.Neon,
		Color = Color3.fromRGB(120, 230, 255), Parent = m }))
	light(crystal, Color3.fromRGB(140, 220, 255), 2, 22)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(1.5, 2.5)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.35, 0)
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150))
	sparkle.Parent = crystal
	-- Coffres de gemmes sur le comptoir.
	for _, x in ipairs({ -1.6, 1.6 }) do
		local c = k * CFrame.new(x, 3.6, -3)
		part({ Size = Vector3.new(1.3, 0.8, 0.9), CFrame = c, Material = M.WoodPlanks, Color = Color3.fromRGB(110, 70, 40), Parent = m })
		local gems = deco(part({ Size = Vector3.new(1.1, 0.3, 0.7), CFrame = c * CFrame.new(0, 0.5, 0), Material = M.Neon, Color = Color3.fromRGB(110, 210, 255), Parent = m }))
		gems.Transparency = 0.1
	end
	local board = deco(part({ Size = Vector3.new(6, 1.2, 0.2), CFrame = k * CFrame.new(0, 6.8, -4.15), Material = M.WoodPlanks, Color = Color3.fromRGB(60, 35, 95), Parent = m }))
	textSign(board, "COMPTOIR DES MERVEILLES", gold, Enum.Font.Merriweather)
	local anchor = deco(part({ Size = Vector3.new(1, 1, 1), CFrame = k * CFrame.new(0, 3, -3.6), Transparency = 1, Parent = m }))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Ouvrir la boutique"
	prompt.ObjectText = "Comptoir des Merveilles"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
end

-- Lanternes célestes : la nuit, de petites lanternes s'élèvent au-dessus de la cité.
do
	local sky = deco(part({ Name = "SkyLanterns", Size = Vector3.new(L.Wall * 2 - 20, 1, L.Wall * 2 - 20), CFrame = CFrame.new(0, GROUND + 6, 0),
		Transparency = 1, Parent = props }))
	local lanterns = Instance.new("ParticleEmitter")
	lanterns.Shape = Enum.ParticleEmitterShape.Box
	lanterns.Rate = 2.5
	lanterns.Lifetime = NumberRange.new(30, 40)
	lanterns.Speed = NumberRange.new(1.5, 2.5)
	lanterns.SpreadAngle = Vector2.new(10, 10)
	lanterns.EmissionDirection = Enum.NormalId.Top
	lanterns.Acceleration = Vector3.new(0.4, 0, 0.2)
	lanterns.LightEmission = 0.8
	lanterns.Brightness = 3
	lanterns.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.05, 0.9), NumberSequenceKeypoint.new(0.85, 0.7),
		NumberSequenceKeypoint.new(1, 0) })
	lanterns.Color = ColorSequence.new(Color3.fromRGB(255, 190, 100), Color3.fromRGB(255, 140, 70))
	lanterns.Enabled = false
	lanterns.Parent = sky
	local Lighting = game:GetService("Lighting")
	task.spawn(function()
		while sky.Parent do
			local t = Lighting.ClockTime
			lanterns.Enabled = t >= 19 or t < 5
			task.wait(5)
		end
	end)
end

---------------------------------------------------------------------------
-- Personnages R15 habillés
---------------------------------------------------------------------------
local IDLE_ANIM = "rbxassetid://507766666"
local WALK_ANIM = "rbxassetid://507777826"

local function attach(character: Model, bodyName: string, props: { [string]: any }, offset: CFrame): BasePart?
	local body = character:FindFirstChild(bodyName) :: BasePart?
	if not body then
		return nil
	end
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = M.Fabric
	for key, value in pairs(props) do
		if key ~= "ClassName" then
			(p :: any)[key] = value
		end
	end
	p.CFrame = body.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	p.Parent = character
	return p
end

local function size(character: Model, name: string): Vector3
	local p = character:FindFirstChild(name) :: BasePart?
	return p and p.Size or Vector3.one
end

local function cylY(h: number, d: number): Vector3
	return Vector3.new(h, d, d)
end
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

local function hat(c: Model, brim: number, crownD: number, crownH: number, color: Color3, material: Enum.Material?)
	local head = size(c, "Head")
	local top = head.Y / 2
	attach(c, "Head", { Shape = Enum.PartType.Cylinder, Size = cylY(0.15, brim), Color = color, Material = material or M.Fabric },
		CFrame.new(0, top - 0.05, 0) * UPRIGHT)
	attach(c, "Head", { Shape = Enum.PartType.Cylinder, Size = cylY(crownH, crownD), Color = color, Material = material or M.Fabric },
		CFrame.new(0, top + crownH / 2 - 0.05, 0) * UPRIGHT)
end

local function skirt(c: Model, length: number, color: Color3, flare: number)
	local lt = size(c, "LowerTorso")
	attach(c, "LowerTorso", { Size = Vector3.new(lt.X * flare, length, lt.Z * (flare + 0.35)), Color = color },
		CFrame.new(0, -length / 2 + lt.Y / 2, 0))
end

local function apron(c: Model, color: Color3, length: number)
	local ut, lt = size(c, "UpperTorso"), size(c, "LowerTorso")
	attach(c, "UpperTorso", { Size = Vector3.new(ut.X * 0.75, ut.Y * 0.7, 0.1), Color = color }, CFrame.new(0, -ut.Y * 0.15, -ut.Z / 2 - 0.06))
	attach(c, "LowerTorso", { Size = Vector3.new(ut.X * 0.8, length, 0.1), Color = color }, CFrame.new(0, -length / 2 + lt.Y / 2, -lt.Z / 2 - 0.25))
end

local function belt(c: Model, color: Color3, buckle: Color3?)
	local lt = size(c, "LowerTorso")
	attach(c, "LowerTorso", { Size = Vector3.new(lt.X * 1.04, 0.28, lt.Z * 1.06), Color = color, Material = M.Leather }, CFrame.new(0, lt.Y / 2 - 0.05, 0))
	if buckle then
		attach(c, "LowerTorso", { Size = Vector3.new(0.4, 0.32, 0.1), Color = buckle, Material = M.Metal }, CFrame.new(0, lt.Y / 2 - 0.05, -lt.Z * 0.55))
	end
end

local function boots(c: Model, color: Color3)
	for _, side in ipairs({ "Left", "Right" }) do
		local foot = size(c, side .. "Foot")
		attach(c, side .. "Foot", { Size = foot + Vector3.new(0.12, 0.25, 0.15), Color = color, Material = M.Leather }, CFrame.new(0, 0.1, 0))
		local leg = size(c, side .. "LowerLeg")
		attach(c, side .. "LowerLeg", { Size = Vector3.new(leg.X + 0.1, leg.Y * 0.5, leg.Z + 0.1), Color = color, Material = M.Leather },
			CFrame.new(0, -leg.Y * 0.25, 0))
	end
end

local function gloves(c: Model, color: Color3)
	for _, side in ipairs({ "Left", "Right" }) do
		local hand = size(c, side .. "Hand")
		attach(c, side .. "Hand", { Size = hand + Vector3.new(0.1, 0.1, 0.1), Color = color, Material = M.Leather }, CFrame.new())
	end
end

local function beard(c: Model, color: Color3, length: number)
	local head = size(c, "Head")
	attach(c, "Head", { Size = Vector3.new(head.X * 0.6, length, 0.35), Color = color, Material = M.Fabric },
		CFrame.new(0, -head.Y / 2 - length / 2 + 0.35, -head.Z / 2 + 0.05))
end

local function cape(c: Model, color: Color3, length: number)
	local ut = size(c, "UpperTorso")
	attach(c, "UpperTorso", { Size = Vector3.new(ut.X * 1.1, length, 0.12), Color = color },
		CFrame.new(0, ut.Y / 2 - length / 2, ut.Z / 2 + 0.1))
end

local function scarf(c: Model, color: Color3)
	local ut = size(c, "UpperTorso")
	attach(c, "UpperTorso", { Shape = Enum.PartType.Cylinder, Size = cylY(0.4, ut.Z * 1.4), Color = color },
		CFrame.new(0, ut.Y / 2 + 0.05, 0) * UPRIGHT)
end

local function handProp(c: Model, side: string, props: { [string]: any }, offset: CFrame)
	return attach(c, side .. "Hand", props, offset)
end

local OUTFITS = {}

function OUTFITS.Merchant(c)
	skirt(c, 2.4, Color3.fromRGB(120, 30, 50), 1.2)
	apron(c, Color3.fromRGB(245, 240, 225), 2)
	belt(c, Color3.fromRGB(90, 60, 35), Color3.fromRGB(230, 185, 70))
	local head = size(c, "Head")
	attach(c, "Head", { Shape = Enum.PartType.Ball, Size = Vector3.one * head.X * 1.12, Color = Color3.fromRGB(200, 60, 70) },
		CFrame.new(0, 0.12, 0.18))
	attach(c, "LowerTorso", { Size = Vector3.new(0.6, 0.7, 0.4), Color = Color3.fromRGB(140, 95, 50), Material = M.Leather },
		CFrame.new(0.8, -0.2, -0.3))
	boots(c, Color3.fromRGB(70, 45, 30))
end

function OUTFITS.Smith(c)
	apron(c, Color3.fromRGB(95, 65, 40), 1.8)
	gloves(c, Color3.fromRGB(60, 40, 28))
	boots(c, Color3.fromRGB(45, 35, 30))
	belt(c, Color3.fromRGB(50, 35, 25), Color3.fromRGB(160, 160, 170))
	beard(c, Color3.fromRGB(110, 60, 35), 0.9)
	local head = size(c, "Head")
	attach(c, "Head", { Shape = Enum.PartType.Cylinder, Size = cylY(0.35, head.X * 1.06), Color = Color3.fromRGB(170, 40, 40) },
		CFrame.new(0, head.Y * 0.32, 0) * UPRIGHT)
	for _, x in ipairs({ -0.25, 0.25 }) do
		attach(c, "Head", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 0.42, 0.42), Color = Color3.fromRGB(255, 170, 60), Material = M.Glass },
			CFrame.new(x, head.Y * 0.38, -head.Z / 2 - 0.05) * CFrame.Angles(0, math.rad(90), 0))
	end
	handProp(c, "Right", { Size = Vector3.new(0.25, 2, 0.25), Color = Color3.fromRGB(100, 70, 45), Material = M.Wood }, CFrame.new(0, -0.6, -0.2) * CFrame.Angles(math.rad(90), 0, 0))
end

function OUTFITS.Sage(c)
	skirt(c, 3.2, Color3.fromRGB(35, 40, 100), 1.3)
	cape(c, Color3.fromRGB(25, 25, 70), 4.2)
	beard(c, Color3.fromRGB(235, 235, 240), 1.6)
	belt(c, Color3.fromRGB(220, 175, 60), nil)
	local head = size(c, "Head")
	local top = head.Y / 2
	attach(c, "Head", { Shape = Enum.PartType.Cylinder, Size = cylY(0.15, head.X * 2.1), Color = Color3.fromRGB(45, 45, 120) },
		CFrame.new(0, top, 0) * UPRIGHT)
	for i = 0, 4 do
		local d = head.X * (1.05 - i * 0.2)
		attach(c, "Head", { Shape = Enum.PartType.Cylinder, Size = cylY(0.55, d), Color = Color3.fromRGB(45, 45, 120) },
			CFrame.new(0.04 * i, top + 0.3 + i * 0.45, 0.05 * i) * UPRIGHT)
	end
	attach(c, "Head", { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.4, Color = Color3.fromRGB(255, 220, 110), Material = M.Neon },
		CFrame.new(0.2, top + 2.6, 0.25))
	local staff = handProp(c, "Right", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(6.5, 0.3, 0.3), Color = Color3.fromRGB(95, 65, 40), Material = M.Wood },
		CFrame.new(0, 1.2, 0) * UPRIGHT)
	if staff then
		attach(c, "RightHand", { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, Color = Color3.fromRGB(150, 220, 255), Material = M.Neon },
			CFrame.new(0, 4.5, 0))
	end
end

function OUTFITS.Explorer(c)
	hat(c, 2.4, 1.3, 0.7, Color3.fromRGB(140, 105, 65), M.Leather)
	scarf(c, Color3.fromRGB(190, 50, 50))
	local ut = size(c, "UpperTorso")
	for _, x in ipairs({ -1, 1 }) do
		attach(c, "UpperTorso", { Size = Vector3.new(ut.X * 0.32, ut.Y * 0.95, 0.1), Color = Color3.fromRGB(110, 75, 45), Material = M.Leather },
			CFrame.new(x * ut.X * 0.3, -0.02, -ut.Z / 2 - 0.05))
	end
	attach(c, "UpperTorso", { Size = Vector3.new(ut.X * 0.8, ut.Y * 0.9, 0.8), Color = Color3.fromRGB(120, 85, 50), Material = M.Leather },
		CFrame.new(0, -0.1, ut.Z / 2 + 0.4))
	attach(c, "UpperTorso", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(ut.X * 0.9, 0.6, 0.6), Color = Color3.fromRGB(70, 110, 80) },
		CFrame.new(0, ut.Y / 2 + 0.1, ut.Z / 2 + 0.4))
	belt(c, Color3.fromRGB(70, 45, 30), Color3.fromRGB(200, 170, 80))
	boots(c, Color3.fromRGB(80, 55, 35))
	handProp(c, "Left", { Size = Vector3.new(0.9, 0.05, 1.2), Color = Color3.fromRGB(235, 220, 180), Material = M.SmoothPlastic }, CFrame.new(0, -0.1, -0.4))
end

function OUTFITS.Guard(c)
	local head, ut = size(c, "Head"), size(c, "UpperTorso")
	attach(c, "Head", { Shape = Enum.PartType.Ball, Size = Vector3.one * head.X * 1.15, Color = Color3.fromRGB(170, 170, 180), Material = M.Metal, Reflectance = 0.2 },
		CFrame.new(0, 0.2, 0.05))
	attach(c, "Head", { Size = Vector3.new(0.2, 0.9, 1), Color = Color3.fromRGB(180, 40, 40) }, CFrame.new(0, head.Y / 2 + 0.55, 0.1))
	attach(c, "UpperTorso", { Size = ut + Vector3.new(0.15, -0.1, 0.15), Color = Color3.fromRGB(160, 160, 170), Material = M.Metal, Reflectance = 0.15 },
		CFrame.new(0, 0.05, 0))
	attach(c, "UpperTorso", { Size = Vector3.new(ut.X * 0.5, ut.Y * 1.6, 0.1), Color = Color3.fromRGB(130, 30, 40) }, CFrame.new(0, -0.45, -ut.Z / 2 - 0.15))
	for _, side in ipairs({ "Left", "Right" }) do
		local arm = size(c, side .. "UpperArm")
		attach(c, side .. "UpperArm", { Size = Vector3.new(arm.X + 0.3, 0.5, arm.Z + 0.3), Color = Color3.fromRGB(150, 150, 160), Material = M.Metal },
			CFrame.new(0, arm.Y / 2 - 0.1, 0))
	end
	belt(c, Color3.fromRGB(50, 35, 25), Color3.fromRGB(220, 180, 70))
	boots(c, Color3.fromRGB(40, 35, 35))
	handProp(c, "Right", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 0.25, 0.25), Color = Color3.fromRGB(100, 70, 45), Material = M.Wood },
		CFrame.new(0, 1.5, 0) * UPRIGHT)
	handProp(c, "Right", { ClassName = "WedgePart", Size = Vector3.new(0.15, 1, 0.5), Color = Color3.fromRGB(200, 200, 210), Material = M.Metal },
		CFrame.new(0, 5.4, 0))
end

function OUTFITS.Baker(c)
	apron(c, Color3.fromRGB(250, 248, 240), 1.8)
	skirt(c, 1.6, Color3.fromRGB(150, 110, 80), 1.15)
	local head = size(c, "Head")
	attach(c, "Head", { Shape = Enum.PartType.Cylinder, Size = cylY(1.1, head.X * 0.95), Color = Color3.fromRGB(250, 250, 250) },
		CFrame.new(0, head.Y / 2 + 0.45, 0) * UPRIGHT)
	attach(c, "Head", { Shape = Enum.PartType.Ball, Size = Vector3.one * head.X * 1.1, Color = Color3.fromRGB(250, 250, 250) },
		CFrame.new(0, head.Y / 2 + 1.1, 0))
	handProp(c, "Left", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.6, 0.6), Color = Color3.fromRGB(205, 150, 80), Material = M.SmoothPlastic },
		CFrame.new(0, -0.2, -0.3) * CFrame.Angles(0, math.rad(90), 0))
	boots(c, Color3.fromRGB(90, 60, 40))
end

function OUTFITS.Farmer(c)
	hat(c, 2.8, 1.3, 0.6, Color3.fromRGB(225, 195, 110), M.Grass)
	local ut = size(c, "UpperTorso")
	attach(c, "UpperTorso", { Size = Vector3.new(ut.X * 0.6, ut.Y * 0.55, 0.1), Color = Color3.fromRGB(60, 85, 140) }, CFrame.new(0, -ut.Y * 0.22, -ut.Z / 2 - 0.05))
	for _, x in ipairs({ -0.4, 0.4 }) do
		attach(c, "UpperTorso", { Size = Vector3.new(0.2, ut.Y, ut.Z + 0.15), Color = Color3.fromRGB(60, 85, 140) }, CFrame.new(x, 0, 0))
	end
	boots(c, Color3.fromRGB(70, 50, 35))
	-- Fourche tenue droite dans le poing : le manche passe dans la main,
	-- descend presque jusqu'au sol et dépasse au-dessus de la tête avec ses dents.
	local grip = CFrame.new(0.05, 0.6, -0.05) * CFrame.Angles(math.rad(-8), 0, 0)
	handProp(c, "Right", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(6.2, 0.22, 0.22), Color = Color3.fromRGB(125, 92, 58), Material = M.Wood },
		grip * UPRIGHT)
	local head = grip * CFrame.new(0, 3.1, 0)
	handProp(c, "Right", { Size = Vector3.new(1.3, 0.16, 0.16), Color = Color3.fromRGB(95, 95, 100), Material = M.Metal }, head * CFrame.new(0, 0.05, 0))
	handProp(c, "Right", { Size = Vector3.new(0.3, 0.35, 0.3), Color = Color3.fromRGB(95, 95, 100), Material = M.Metal }, head * CFrame.new(0, -0.15, 0))
	for _, x in ipairs({ -0.55, 0, 0.55 }) do
		handProp(c, "Right", { Size = Vector3.new(0.09, 1.4, 0.09), Color = Color3.fromRGB(170, 170, 178), Material = M.Metal }, head * CFrame.new(x, 0.75, 0))
	end
end

function OUTFITS.Lady(c)
	skirt(c, 2.9, Color3.fromRGB(60, 115, 100), 1.3)
	local ut = size(c, "UpperTorso")
	attach(c, "UpperTorso", { Size = Vector3.new(ut.X * 1.15, ut.Y * 0.45, ut.Z * 1.15), Color = Color3.fromRGB(220, 200, 160) }, CFrame.new(0, ut.Y * 0.32, 0))
	local head = size(c, "Head")
	attach(c, "Head", { Size = Vector3.new(head.X * 1.05, head.Y * 0.9, 0.5), Color = Color3.fromRGB(70, 45, 30) }, CFrame.new(0, 0.05, head.Z / 2 + 0.1))
	handProp(c, "Left", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 1.3, 1.3), Color = Color3.fromRGB(160, 120, 70), Material = M.Wood },
		CFrame.new(0, -0.6, 0) * UPRIGHT)
end

function OUTFITS.Fisher(c)
	hat(c, 2.2, 1.25, 0.7, Color3.fromRGB(240, 200, 50), M.SmoothPlastic)
	local ut = size(c, "UpperTorso")
	attach(c, "UpperTorso", { Size = ut + Vector3.new(0.12, 0, 0.12), Color = Color3.fromRGB(240, 200, 50), Material = M.SmoothPlastic }, CFrame.new())
	boots(c, Color3.fromRGB(50, 70, 50))
	beard(c, Color3.fromRGB(90, 70, 50), 0.5)
	handProp(c, "Right", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 0.15, 0.15), Color = Color3.fromRGB(150, 120, 80), Material = M.Wood },
		CFrame.new(0, 2.5, -1.2) * CFrame.Angles(math.rad(30), 0, 0) * UPRIGHT)
end

function OUTFITS.Mystic(c)
	skirt(c, 3.2, Color3.fromRGB(40, 110, 130), 1.3)
	cape(c, Color3.fromRGB(25, 60, 80), 4.4)
	local head = size(c, "Head")
	attach(c, "Head", { Shape = Enum.PartType.Ball, Size = Vector3.one * head.X * 1.2, Color = Color3.fromRGB(30, 75, 95) },
		CFrame.new(0, 0.15, 0.22))
	local ut = size(c, "UpperTorso")
	attach(c, "UpperTorso", { Size = Vector3.new(0.35, 0.55, 0.35), Color = Color3.fromRGB(150, 230, 255), Material = M.Neon },
		CFrame.new(0, -0.1, -ut.Z / 2 - 0.2) * CFrame.Angles(0, 0, math.rad(45)))
	belt(c, Color3.fromRGB(200, 220, 240), nil)
	local orb = handProp(c, "Right", { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, Color = Color3.fromRGB(170, 120, 255), Material = M.Neon },
		CFrame.new(0, 0.2, -0.6))
	if orb then
		light(orb, Color3.fromRGB(170, 130, 255), 2, 14)
	end
end

function OUTFITS.Miner(c)
	local head = size(c, "Head")
	attach(c, "Head", { Shape = Enum.PartType.Ball, Size = Vector3.one * head.X * 1.15, Color = Color3.fromRGB(230, 180, 40), Material = M.SmoothPlastic },
		CFrame.new(0, 0.25, 0))
	local lamp = attach(c, "Head", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.45, 0.45), Color = Color3.fromRGB(255, 250, 210), Material = M.Neon },
		CFrame.new(0, head.Y * 0.45, -head.Z / 2 - 0.1) * CFrame.Angles(0, math.rad(90), 0))
	if lamp then
		light(lamp, Color3.fromRGB(255, 240, 200), 1.5, 14)
	end
	beard(c, Color3.fromRGB(80, 60, 45), 0.8)
	gloves(c, Color3.fromRGB(70, 50, 35))
	boots(c, Color3.fromRGB(50, 40, 35))
	belt(c, Color3.fromRGB(50, 35, 25), Color3.fromRGB(160, 160, 170))
	handProp(c, "Right", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 0.25, 0.25), Color = Color3.fromRGB(110, 80, 50), Material = M.Wood },
		CFrame.new(0, 1.2, 0) * UPRIGHT)
	handProp(c, "Right", { Size = Vector3.new(0.3, 0.3, 2.6), Color = Color3.fromRGB(120, 120, 130), Material = M.Metal },
		CFrame.new(0, 3.1, 0))
end

-- Cheveux en volumes : calotte, mèches sur les côtés et longueur dans le dos.
local function hair(c: Model, color: Color3, length: number, bangs: boolean?)
	local head = size(c, "Head")
	attach(c, "Head", { Shape = Enum.PartType.Ball, Size = Vector3.new(head.X * 1.12, head.Y * 0.9, head.Z * 1.15), Color = color },
		CFrame.new(0, head.Y * 0.18, head.Z * 0.08))
	for _, x in ipairs({ -1, 1 }) do
		attach(c, "Head", { Size = Vector3.new(0.25, head.Y * 0.8 + length * 0.4, head.Z * 0.7), Color = color },
			CFrame.new(x * head.X * 0.52, -length * 0.2, head.Z * 0.1))
	end
	if length > 0 then
		attach(c, "Head", { Size = Vector3.new(head.X * 0.95, length, 0.3), Color = color },
			CFrame.new(0, -length / 2 + head.Y * 0.2, head.Z * 0.55))
	end
	if bangs then
		attach(c, "Head", { ClassName = "WedgePart", Size = Vector3.new(head.X * 0.9, 0.35, 0.4), Color = color },
			CFrame.new(0, head.Y * 0.4, -head.Z * 0.48) * CFrame.Angles(0, math.pi, 0))
	end
end

-- Gardienne des cristaux : robe à deux étages, étole, longue chevelure argentée,
-- diadème de cristaux et bâton surmonté d'une gemme.
function OUTFITS.CrystalKeeper(c)
	local head, ut = size(c, "Head"), size(c, "UpperTorso")
	local robe, robeDark = Color3.fromRGB(60, 50, 120), Color3.fromRGB(35, 28, 80)
	skirt(c, 3.3, robeDark, 1.45)
	skirt(c, 2.3, robe, 1.25)
	attach(c, "UpperTorso", { Size = ut + Vector3.new(0.1, -0.2, 0.1), Color = robe }, CFrame.new(0, 0.1, 0))
	attach(c, "UpperTorso", { Size = Vector3.new(ut.X * 0.35, ut.Y * 1.7, 0.08), Color = Color3.fromRGB(200, 170, 90) },
		CFrame.new(0, -0.6, -ut.Z / 2 - 0.12))
	cape(c, Color3.fromRGB(25, 22, 55), 4.6)
	belt(c, Color3.fromRGB(200, 170, 90), Color3.fromRGB(150, 230, 255))
	for _, side in ipairs({ "Left", "Right" }) do
		local arm = size(c, side .. "LowerArm")
		attach(c, side .. "LowerArm", { Size = Vector3.new(arm.X * 1.6, arm.Y * 0.8, arm.Z * 1.6), Color = robe }, CFrame.new(0, -0.15, 0))
	end
	hair(c, Color3.fromRGB(215, 225, 240), 3, true)
	attach(c, "Head", { Shape = Enum.PartType.Cylinder, Size = cylY(0.18, head.X * 1.16), Color = Color3.fromRGB(220, 190, 110), Material = M.Metal },
		CFrame.new(0, head.Y * 0.32, 0) * UPRIGHT)
	for k = -1, 1 do
		local gem = attach(c, "Head", { Size = Vector3.new(0.22, k == 0 and 0.7 or 0.45, 0.22), Color = Color3.fromRGB(160, 220, 255), Material = M.Neon },
			CFrame.new(k * 0.3, head.Y * 0.5 + (k == 0 and 0.2 or 0.08), -head.Z * 0.5) * CFrame.Angles(0, math.rad(45), 0))
		if gem and k == 0 then
			light(gem, Color3.fromRGB(160, 200, 255), 1, 8)
		end
	end
	local staff = handProp(c, "Right", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(6.6, 0.28, 0.28), Color = Color3.fromRGB(70, 50, 90), Material = M.Wood },
		CFrame.new(0, 1.3, 0) * UPRIGHT)
	if staff then
		for k = 0, 3 do
			handProp(c, "Right", { Size = Vector3.new(0.12, 1.1, 0.12), Color = Color3.fromRGB(220, 190, 110), Material = M.Metal },
				CFrame.new(0, 4.5, 0) * CFrame.Angles(0, k * math.pi / 2, math.rad(20)) * CFrame.new(0, 0.3, 0))
		end
		local orb = handProp(c, "Right", { Size = Vector3.new(0.6, 1.2, 0.6), Color = Color3.fromRGB(180, 140, 255), Material = M.Neon },
			CFrame.new(0, 5, 0) * CFrame.Angles(0, math.rad(45), 0))
		if orb then
			light(orb, Color3.fromRGB(170, 130, 255), 2, 16)
		end
	end
	boots(c, Color3.fromRGB(40, 32, 60))
end

-- Mineur de cristaux : casque à lampe, salopette, hotte pleine de cristaux, pioche.
function OUTFITS.CrystalMiner(c)
	OUTFITS.Miner(c)
	local ut, lt = size(c, "UpperTorso"), size(c, "LowerTorso")
	local denim = Color3.fromRGB(60, 75, 110)
	attach(c, "UpperTorso", { Size = Vector3.new(ut.X * 0.7, ut.Y * 0.55, 0.1), Color = denim }, CFrame.new(0, -ut.Y * 0.22, -ut.Z / 2 - 0.05))
	for _, x in ipairs({ -0.38, 0.38 }) do
		attach(c, "UpperTorso", { Size = Vector3.new(0.22, ut.Y, ut.Z + 0.14), Color = denim }, CFrame.new(x, 0, 0))
	end
	attach(c, "LowerTorso", { Size = lt + Vector3.new(0.1, 0, 0.1), Color = denim }, CFrame.new())
	attach(c, "UpperTorso", { Size = Vector3.new(ut.X * 0.85, ut.Y * 1.1, 1), Color = Color3.fromRGB(150, 110, 65), Material = M.WoodPlanks },
		CFrame.new(0, 0, ut.Z / 2 + 0.55))
	for k = -1, 1 do
		local crystal = attach(c, "UpperTorso", { Size = Vector3.new(0.3, 0.9, 0.3),
			Color = k == 0 and Color3.fromRGB(180, 140, 255) or Color3.fromRGB(120, 220, 255), Material = M.Neon },
			CFrame.new(k * 0.4, ut.Y * 0.65, ut.Z / 2 + 0.55) * CFrame.Angles(0, 0, math.rad(k * 18)))
		if crystal and k == 0 then
			light(crystal, Color3.fromRGB(170, 140, 255), 1, 8)
		end
	end
end

-- Herboriste : capuche, châle, panier de champignons lumineux.
function OUTFITS.Herbalist(c)
	local head, ut = size(c, "Head"), size(c, "UpperTorso")
	local green = Color3.fromRGB(60, 95, 80)
	skirt(c, 3, Color3.fromRGB(110, 75, 60), 1.3)
	apron(c, Color3.fromRGB(215, 200, 170), 2.2)
	hair(c, Color3.fromRGB(150, 70, 45), 1.6, true)
	attach(c, "Head", { Shape = Enum.PartType.Ball, Size = Vector3.new(head.X * 1.3, head.Y * 1.15, head.Z * 1.3), Color = green },
		CFrame.new(0, 0.12, 0.25))
	attach(c, "UpperTorso", { Size = Vector3.new(ut.X * 1.2, ut.Y * 0.5, ut.Z * 1.2), Color = green }, CFrame.new(0, ut.Y * 0.3, 0))
	belt(c, Color3.fromRGB(90, 60, 35), Color3.fromRGB(200, 170, 80))
	boots(c, Color3.fromRGB(70, 50, 35))
	local basket = handProp(c, "Left", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 1.5, 1.5), Color = Color3.fromRGB(165, 125, 75), Material = M.WoodPlanks },
		CFrame.new(0, -0.7, -0.2) * UPRIGHT)
	if basket then
		for k = 0, 2 do
			handProp(c, "Left", { Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.35, 0.6),
				Color = k == 1 and Color3.fromRGB(255, 130, 215) or Color3.fromRGB(120, 225, 255), Material = M.Neon },
				CFrame.new((k - 1) * 0.35, -0.15, -0.2))
		end
		light(basket, Color3.fromRGB(140, 220, 255), 0.8, 8)
	end
end

-- Barde : chapeau à plume, gilet, écharpe, luth.
function OUTFITS.Bard(c)
	local head, ut = size(c, "Head"), size(c, "UpperTorso")
	hair(c, Color3.fromRGB(60, 40, 30), 0.8, false)
	hat(c, 2.1, 1.2, 0.55, Color3.fromRGB(110, 40, 70))
	attach(c, "Head", { Size = Vector3.new(0.12, 1.6, 0.35), Color = Color3.fromRGB(120, 220, 255), Material = M.Neon },
		CFrame.new(0.55, head.Y / 2 + 0.7, 0.3) * CFrame.Angles(math.rad(-25), 0, math.rad(-20)))
	attach(c, "UpperTorso", { Size = ut + Vector3.new(0.12, -0.15, 0.12), Color = Color3.fromRGB(150, 55, 85) }, CFrame.new(0, 0.05, 0))
	scarf(c, Color3.fromRGB(230, 190, 90))
	belt(c, Color3.fromRGB(60, 40, 30), Color3.fromRGB(220, 180, 70))
	boots(c, Color3.fromRGB(60, 40, 30))
	attach(c, "UpperTorso", { Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.6, 0.6), Color = Color3.fromRGB(170, 115, 60), Material = M.Wood },
		CFrame.new(0.2, -0.4, -ut.Z / 2 - 0.45) * CFrame.Angles(0, 0, math.rad(-35)))
	attach(c, "UpperTorso", { Size = Vector3.new(0.25, 2, 0.15), Color = Color3.fromRGB(90, 60, 35), Material = M.Wood },
		CFrame.new(-0.55, 0.5, -ut.Z / 2 - 0.5) * CFrame.Angles(0, 0, math.rad(-35)))
end

function OUTFITS.Champion(c)
	local head, ut = size(c, "Head"), size(c, "UpperTorso")
	local gold = Color3.fromRGB(215, 170, 70)
	attach(c, "Head", { Shape = Enum.PartType.Ball, Size = Vector3.one * head.X * 1.15, Color = gold, Material = M.Metal, Reflectance = 0.15 },
		CFrame.new(0, 0.22, 0.05))
	attach(c, "Head", { Size = Vector3.new(0.25, 0.9, 1.6), Color = Color3.fromRGB(170, 30, 35) }, CFrame.new(0, head.Y / 2 + 0.55, 0.15))
	attach(c, "UpperTorso", { Size = ut + Vector3.new(0.2, -0.1, 0.2), Color = gold, Material = M.Metal, Reflectance = 0.15 }, CFrame.new(0, 0.05, 0))
	for _, side in ipairs({ "Left", "Right" }) do
		local arm = size(c, side .. "UpperArm")
		attach(c, side .. "UpperArm", { Shape = Enum.PartType.Ball, Size = Vector3.one * (arm.X + 0.6), Color = gold, Material = M.Metal },
			CFrame.new(0, arm.Y / 2 - 0.2, 0))
		local fore = size(c, side .. "LowerArm")
		attach(c, side .. "LowerArm", { Size = fore + Vector3.new(0.15, -0.2, 0.15), Color = Color3.fromRGB(90, 60, 40), Material = M.Leather }, CFrame.new())
	end
	cape(c, Color3.fromRGB(150, 25, 35), 4.6)
	skirt(c, 1.5, Color3.fromRGB(110, 75, 45), 1.15)
	belt(c, Color3.fromRGB(60, 40, 25), gold)
	boots(c, Color3.fromRGB(70, 50, 35))
	handProp(c, "Right", { Size = Vector3.new(0.3, 4.4, 0.12), Color = Color3.fromRGB(205, 205, 215), Material = M.Metal, Reflectance = 0.3 },
		CFrame.new(0, 2.4, 0))
	handProp(c, "Right", { Size = Vector3.new(1.4, 0.25, 0.25), Color = gold, Material = M.Metal }, CFrame.new(0, 0.3, 0))
	handProp(c, "Left", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.6, 2.6), Color = Color3.fromRGB(130, 30, 35), Material = M.Metal },
		CFrame.new(-0.4, 0, 0))
end

function OUTFITS.Child(c)
	hat(c, 0.1, 1.35, 0.5, Color3.fromRGB(60, 120, 200), M.Fabric)
	local head = size(c, "Head")
	attach(c, "Head", { Size = Vector3.new(1, 0.1, 0.7), Color = Color3.fromRGB(60, 120, 200) }, CFrame.new(0, head.Y / 2, -head.Z / 2 - 0.25))
	scarf(c, Color3.fromRGB(240, 120, 60))
end

local function playAnimation(humanoid: Humanoid, id: string): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if ok and track then
		track.Looped = true
		track:Play(0.2)
		return track
	end
	return nil
end

local function buildCharacter(name: string, look, cframe: CFrame, parent: Instance, scale: number?): Model?
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = look.Skin
	desc.LeftArmColor = look.Sleeves or look.Shirt
	desc.RightArmColor = look.Sleeves or look.Shirt
	desc.TorsoColor = look.Shirt
	desc.LeftLegColor = look.Pants
	desc.RightLegColor = look.Pants
	if scale then
		desc.HeightScale = scale
		desc.WidthScale = scale
		desc.DepthScale = scale
	end
	local ok, character = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not character then
		warn("[Village] Impossible de créer le PNJ " .. name .. " :", character)
		return nil
	end
	character.Name = name
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	for _, script in ipairs(character:GetDescendants()) do
		if script:IsA("LuaSourceContainer") then
			script:Destroy()
		end
	end
	humanoid.DisplayName = look.Name or name
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 50
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.WalkSpeed = 7

	local height = humanoid.HipHeight + root.Size.Y / 2
	character:PivotTo(cframe + Vector3.new(0, height, 0))

	local outfit = OUTFITS[look.Outfit]
	if outfit then
		outfit(character)
	end
	character.Parent = parent
	return character
end

local function nameTag(npc: Model, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "RoleTag"
	gui.Size = UDim2.fromOffset(220, 24)
	gui.StudsOffset = Vector3.new(0, 3.3, 0)
	gui.MaxDistance = 50
	gui.Adornee = npc:FindFirstChild("Head")
	gui.Parent = npc
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 215, 130)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
end

local npcFolder = Instance.new("Folder")
npcFolder.Name = "NPCs"
npcFolder.Parent = World

local npcSpots = {
	Elya = shopCf * CFrame.new(0, 0, -8.6),
	Borin = forgeCf * CFrame.new(-3, 1, -5),
	Varek = (function()
		local c = L.Colosseum
		local gate = math.rad(L.ColosseumGate)
		-- Au bord du Cercle des Arcanes, à côté de l'allée d'entrée.
		local a = gate + math.rad(16)
		local pos = Vector3.new(c.X, L.Ground + 0.5, c.Y) + Vector3.new(math.cos(a), 0, math.sin(a)) * 52
		local outward = Vector3.new(math.cos(gate), 0, math.sin(gate))
		return CFrame.lookAt(pos, pos + outward)
	end)(),
}

-- Quartiers : un PNJ et son étal (comptoir, auvent rayé, enseigne, lanterne).
local stallsFolder = model("Stalls", World)
local function stall(cf: CFrame, color: Color3, title: string)
	local m = model("Stall_" .. title, stallsFolder)
	local wood = Color3.fromRGB(120, 82, 50)
	local woodLight = Color3.fromRGB(165, 120, 75)
	part({ Name = "Comptoir", Size = Vector3.new(6, 3, 1.6), CFrame = cf * CFrame.new(0, 1.5, -2.6), Material = M.WoodPlanks, Color = wood, Parent = m })
	part({ Name = "Plateau", Size = Vector3.new(6.6, 0.3, 2.1), CFrame = cf * CFrame.new(0, 3.1, -2.6), Material = M.Wood, Color = woodLight, Parent = m })
	for _, x in ipairs({ -3.2, 3.2 }) do
		for _, z in ipairs({ -3.3, 1.4 }) do
			deco(part({ Name = "Poteau", Size = Vector3.new(0.4, 8.4, 0.4), CFrame = cf * CFrame.new(x, 4.2, z), Material = M.Wood, Color = wood, Parent = m }))
		end
	end
	-- Auvent rayé (couleur du quartier / crème), légèrement incliné vers l'avant.
	for i = 0, 5 do
		deco(part({ Name = "Toile", Size = Vector3.new(1.2, 0.25, 5.6), CFrame = cf * CFrame.new(-3 + i * 1.2 + 0.6, 8.6, -1) * CFrame.Angles(math.rad(-10), 0, 0),
			Material = M.Fabric, Color = i % 2 == 0 and color or Color3.fromRGB(240, 230, 210), Parent = m }))
	end
	local board = deco(part({ Name = "Enseigne", Size = Vector3.new(5.4, 1.3, 0.25), CFrame = cf * CFrame.new(0, 7.4, -3.75), Material = M.Wood,
		Color = Color3.fromRGB(70, 45, 28), Parent = m }))
	textSign(board, title, Color3.fromRGB(255, 215, 130), Enum.Font.Fantasy, { Enum.NormalId.Front })
	-- L'enseigne regarde vers l'avant (-Z du repère) : on la retourne vers les passants.
	board.CFrame = board.CFrame * CFrame.Angles(0, math.pi, 0)
	local lantern = deco(part({ Name = "Lanterne", Size = Vector3.new(0.6, 0.8, 0.6), CFrame = cf * CFrame.new(2.6, 6.6, -3.3), Material = M.Neon,
		Color = Color3.fromRGB(255, 200, 120), Parent = m }))
	light(lantern, Color3.fromRGB(255, 190, 120), 1.6, 16)
end

local DISTRICT_NPCS = {
	-- id, x, z, regard (vers la rue), couleur de l'auvent, enseigne
	-- En bord de rue, tournés vers elle (les villageois y passent).
	{ "Rhea", 268, -212, NORTH, Color3.fromRGB(60, 70, 120), "Caserne" },
	{ "Oswin", 175, 212, SOUTH, Color3.fromRGB(160, 90, 30), "Étal d'Oswin" },
	{ "Maelis", 34, -188, SOUTH, Color3.fromRGB(90, 40, 110), "Archives" },
	{ "Gaelle", -175, -212, NORTH, Color3.fromRGB(110, 140, 70), "Ferme" },
	{ "Odile", -232, 181, SOUTH, Color3.fromRGB(150, 110, 160), "Contes" },
}
for _, d in ipairs(DISTRICT_NPCS) do
	local cf = at(d[2], d[3], d[4])
	npcSpots[d[1]] = cf
	stall(cf, d[5], d[6])
end

for id, spot in pairs(npcSpots) do
	local look = VillageData.Npcs[id]
	local npc = buildCharacter(id, look, spot, npcFolder)
	if npc then
		npc:SetAttribute("NpcId", id)
		local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
		root.Anchored = true
		nameTag(npc, look.Role)
		playAnimation(npc:FindFirstChildOfClass("Humanoid"), IDLE_ANIM)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TalkPrompt"
		prompt.ActionText = "Parler"
		prompt.ObjectText = look.Name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("NpcId", id)
		prompt.Parent = root
	end
end



---------------------------------------------------------------------------
-- Villageois qui se promènent
---------------------------------------------------------------------------
local walkersFolder = Instance.new("Folder")
walkersFolder.Name = "Walkers"
walkersFolder.Parent = World

local function loop(points: { Vector2 }): { Vector2 }
	return points
end
local function ringRoute(c: Vector2, radius: number, count: number): { Vector2 }
	local points = {}
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		table.insert(points, c + Vector2.new(math.cos(a), math.sin(a)) * radius)
	end
	return points
end
local routes = {
	Gaspard = loop({ Vector2.new(3, 135), Vector2.new(3, 175), Vector2.new(-3, 175), Vector2.new(-3, 135) }),
	Lina = loop(ringRoute(L.Fountain, 47, 12)),
	Tobias = loop({ Vector2.new(-140, -222), Vector2.new(-320, -222), Vector2.new(-320, -221), Vector2.new(-140, -221) }),
	Mira = loop(ringRoute(Vector2.zero, 100, 14)),
	Joran = loop({ Vector2.new(116, 3), Vector2.new(158, 3), Vector2.new(158, -3), Vector2.new(116, -3) }),
	Nell = loop({ Vector2.new(-318, 161), Vector2.new(-142, 161), Vector2.new(-142, 162), Vector2.new(-318, 162) }),
	Bram = loop({ Vector2.new(140, -222), Vector2.new(320, -222), Vector2.new(320, -221), Vector2.new(140, -221) }),
	Elise = loop({ Vector2.new(-318, 191), Vector2.new(-140, 191), Vector2.new(-140, 192), Vector2.new(-318, 192) }),
	Odo = loop({ Vector2.new(-118, 3), Vector2.new(-320, 3), Vector2.new(-320, -3), Vector2.new(-118, -3) }),
	Timo = loop({ Vector2.new(-125, -125), Vector2.new(125, -125), Vector2.new(125, 125), Vector2.new(-125, 125) }),
}

for _, look in ipairs(VillageData.Villagers) do
	local route = routes[look.Name]
	if route then
		local start = route[1]
		local npc = buildCharacter(look.Name, look, at(start.X, start.Y), walkersFolder, look.Outfit == "Child" and 0.75 or nil)
		if npc then
			npc:SetAttribute("Villager", look.Name)
			local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
			local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
			humanoid.WalkSpeed = look.Outfit == "Child" and 9 or 6
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
			local idle = playAnimation(humanoid, IDLE_ANIM)
			local walk = playAnimation(humanoid, WALK_ANIM)
			if walk then
				walk:AdjustWeight(0.01)
			end
			humanoid.Running:Connect(function(speed)
				if walk and idle then
					local moving = speed > 0.5
					walk:AdjustWeight(moving and 1 or 0.01, 0.2)
					idle:AdjustWeight(moving and 0.01 or 1, 0.2)
					walk:AdjustSpeed(speed / 12)
				end
			end)
			task.spawn(function()
				local index = 1
				while npc.Parent do
					index = index % #route + 1
					local target = route[index]
					local y = GROUND
					local world = Vector3.new(center.X + target.X, y, center.Z + target.Y)
					humanoid:MoveTo(world)
					humanoid.MoveToFinished:Wait()
					task.wait(random:NextNumber(1.5, 4))
				end
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Trésor caché
---------------------------------------------------------------------------
local treasure: Model? = nil

local function findTreasureSpot(): Vector3
	for _ = 1, 50 do
		local spot = treasureSpots[random:NextInteger(1, #treasureSpots)]
		if Vector2.new(spot.X, spot.Z).Magnitude > 100 then
			return spot
		end
	end
	return treasureSpots[1] or Vector3.new(-150, GROUND, 150)
end

local spawnTreasure

local function openTreasure(player: Player)
	local profile = DataService.Get(player)
	if not profile or treasure == nil then
		return
	end
	local current = treasure
	treasure = nil
	current:Destroy()
	local reward = random:NextInteger(VillageData.Treasure.MinReward, VillageData.Treasure.MaxReward)
	profile.Coins += reward
	profile.Treasures += 1
	DataService.MarkChanged(player)
	Notify:FireClient(player, string.format("Trésor trouvé : +%d ◆", reward), "Gold")
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			Notify:FireClient(other, player.DisplayName .. " a trouvé le trésor ! Demande à Pip où est le prochain.", "Info")
		end
	end
	task.delay(VillageData.Treasure.RespawnDelay, spawnTreasure)
end

function spawnTreasure()
	local pos = findTreasureSpot()
	local m = model("Treasure", World)
	local origin = CFrame.new(pos) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	local box = part({ Size = Vector3.new(3, 1.8, 2), CFrame = origin * CFrame.new(0, 0.9, 0), Material = M.WoodPlanks,
		Color = Color3.fromRGB(130, 85, 45), Parent = m })
	part({ Size = Vector3.new(3.1, 0.9, 2.1), CFrame = origin * CFrame.new(0, 2.25, 0), Material = M.Wood,
		Color = Color3.fromRGB(110, 70, 38), Parent = m })
	deco(part({ Size = Vector3.new(3.2, 0.25, 0.3), CFrame = origin * CFrame.new(0, 1.8, -1.0), Material = M.Metal,
		Color = Color3.fromRGB(230, 180, 60), Reflectance = 0.3, Parent = m }))
	deco(part({ Size = Vector3.new(0.5, 0.6, 0.15), CFrame = origin * CFrame.new(0, 1.6, -1.1), Material = M.Neon,
		Color = Color3.fromRGB(255, 210, 90), Parent = m }))
	light(box, Color3.fromRGB(255, 210, 110), 2, 16)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(1, 2)
	sparkle.Speed = NumberRange.new(2, 4)
	sparkle.SpreadAngle = Vector2.new(30, 30)
	sparkle.EmissionDirection = Enum.NormalId.Top
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.4, 0)
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120))
	sparkle.Parent = box
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ouvrir le coffre"
	prompt.ObjectText = "Trésor caché"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = box
	prompt.Triggered:Connect(openTreasure)
	treasure = m
end
-- Chasse au trésor désactivée : aucun coffre n'apparaît.

local function compassHint(): string
	if treasure == nil then
		return "Quelqu'un vient de trouver le trésor ! Un nouveau coffre apparaîtra bientôt, repasse me voir."
	end
	local pos = treasure:GetPivot().Position
	local fromArena = Vector3.new(pos.X, 0, pos.Z)
	local angle = math.deg(math.atan2(-fromArena.Z, fromArena.X)) % 360
	local names = { "l'est", "le nord-est", "le nord", "le nord-ouest", "l'ouest", "le sud-ouest", "le sud", "le sud-est" }
	local dir = names[math.floor((angle + 22.5) / 45) % 8 + 1]
	local dist = math.floor(fromArena.Magnitude / 10 + 0.5) * 10
	local flat = Vector2.new(pos.X, pos.Z)
	local nearest, best = nil, math.huge
	for _, district in ipairs(VillageData.Districts) do
		local d = (flat - district.Center).Magnitude
		if d < best then
			nearest, best = district, d
		end
	end
	local terrainHint = nearest and string.format(" Je l'ai aperçu du côté de %s.", nearest.Label) or ""
	return string.format("Le coffre se trouve vers %s, à environ %d studs de l'arène.%s Suis les étincelles dorées !", dir, dist, terrainHint)
end

---------------------------------------------------------------------------
-- Exploration : lieux découverts
---------------------------------------------------------------------------
local function visit(player: Player, profile, key: string, label: string)
	if not profile.Visited[key] then
		-- Suivi silencieux (utilisé par les épreuves « Visited:<lieu> ») :
		-- plus de notification ni de son à chaque nouvel endroit.
		profile.Visited[key] = true
		DataService.MarkChanged(player)
	end
end

task.spawn(function()
	while true do
		task.wait(2)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = DataService.Get(player)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if profile and root then
				local p = root.Position
				for key, place in pairs(VillageData.Places) do
					if (Vector2.new(p.X, p.Z) - place.Center).Magnitude < place.Radius and (place.MaxY == nil or p.Y < place.MaxY) then
						visit(player, profile, key, place.Label)
					end
				end
				if p.Y > L.WallHeight - 1 and math.max(math.abs(p.X), math.abs(p.Z)) > L.Wall - 1 then
					visit(player, profile, "rampart", "Les remparts de Brumeval")
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Actions des PNJ
---------------------------------------------------------------------------
local function duplicatesByRarity(profile): { [string]: number }
	local counts = {}
	for _, rarity in ipairs(CardsData.Rarities) do
		counts[rarity.Id] = 0
	end
	for id, count in pairs(profile.Cards) do
		local card = CardsData.CardById[id]
		if card and count > 1 then
			counts[card.Rarity] += count - 1
		end
	end
	return counts
end

local function nearNpc(player: Player, npcId: string): boolean
	local npc = npcFolder:FindFirstChild(npcId)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return npc ~= nil and root ~= nil and (npc:GetPivot().Position - root.Position).Magnitude < 25
end

local actions = {}

function actions.Talk(player, profile, npcId)
	if VillageData.Npcs[npcId] == nil then
		return { ok = false }
	end
	if not profile.Talked[npcId] then
		profile.Talked[npcId] = true
		DataService.MarkChanged(player)
	end
	local info = {}
	if npcId == "Orin" then
		info.Quests = VillageData.questStates(profile)
	elseif npcId == "Borin" then
		info.Duplicates = duplicatesByRarity(profile)
	elseif npcId == "Pip" then
		info.Hint = compassHint()
	end
	return { ok = true, info = info }
end

---------------------------------------------------------------------------
-- PNJ des quartiers
---------------------------------------------------------------------------
local function today(): number
	return DataService.Today()
end

-- Oswin : étal du jour (3 créatures, une seule fois chacune par jour).
function actions.StallList(player, profile)
	if not nearNpc(player, "Oswin") then
		return { ok = false, reason = "Approche-toi de l'étal d'Oswin." }
	end
	local day = today()
	if profile.StallDay ~= day then
		profile.StallDay = day
		profile.StallBought = {}
	end
	local items = {}
	for _, id in ipairs(VillageData.stallFor(day)) do
		local card = CardsData.CardById[id]
		table.insert(items, { Id = id, Price = VillageData.StallPrices[card.Rarity], Sold = profile.StallBought[id] == true })
	end
	return { ok = true, items = items }
end

function actions.StallBuy(player, profile, id)
	if not nearNpc(player, "Oswin") then
		return { ok = false, reason = "Approche-toi de l'étal d'Oswin." }
	end
	local day = today()
	if profile.StallDay ~= day then
		profile.StallDay = day
		profile.StallBought = {}
	end
	if type(id) ~= "string" or not table.find(VillageData.stallFor(day), id) then
		return { ok = false, reason = "Cette créature n'est pas à l'étal aujourd'hui." }
	end
	if profile.StallBought[id] then
		return { ok = false, reason = "Déjà vendue ! Reviens demain pour un nouvel étal." }
	end
	local card = CardsData.CardById[id]
	local price = VillageData.StallPrices[card.Rarity]
	if profile.Coins < price then
		return { ok = false, reason = "Il te manque des gemmes, l'ami." }
	end
	profile.Coins -= price
	profile.StallBought[id] = true
	return { ok = true, results = { CardService.grant(profile, card) } }
end

-- Rhéa : défi quotidien (gagner un entraînement) ; lance aussi l'entraînement.
function actions.RheaInfo(player, profile)
	return { ok = true, done = profile.DailyDuelDay >= today(), reward = VillageData.DailyDuelReward }
end

-- Gaëlle : panier du jour.
function actions.FarmBasket(player, profile)
	if not nearNpc(player, "Gaelle") then
		return { ok = false, reason = "Approche-toi de Gaëlle, à la ferme." }
	end
	if profile.FarmDay >= today() then
		return { ok = false, reason = "Tu as déjà eu ton panier aujourd'hui ! Reviens demain." }
	end
	profile.FarmDay = today()
	local gems = math.random(VillageData.FarmBasket.Min, VillageData.FarmBasket.Max)
	profile.Coins += gems
	return { ok = true, gems = gems }
end

-- Maelis : collections élémentaires (toutes les créatures d'un élément).
local function setStates(profile)
	local states = {}
	for element, el in pairs(CardsData.Elements) do
		local total, owned = 0, 0
		for _, c in ipairs(CardsData.Cards) do
			if c.Element == element then
				total += 1
				if (profile.Cards[c.Id] or 0) > 0 then
					owned += 1
				end
			end
		end
		table.insert(states, { Element = element, Label = el.Label, Owned = owned, Total = total, Claimed = profile.SetsClaimed[element] == true })
	end
	table.sort(states, function(a, b)
		return a.Label < b.Label
	end)
	return states
end

function actions.SetsInfo(player, profile)
	return { ok = true, sets = setStates(profile), reward = VillageData.ElementSetReward }
end

function actions.ClaimSet(player, profile, element)
	if not nearNpc(player, "Maelis") then
		return { ok = false, reason = "Approche-toi de Maelis, aux archives du donjon." }
	end
	if type(element) ~= "string" or not CardsData.Elements[element] then
		return { ok = false }
	end
	for _, s in ipairs(setStates(profile)) do
		if s.Element == element then
			if s.Claimed then
				return { ok = false, reason = "Cette collection est déjà récompensée." }
			end
			if s.Owned < s.Total then
				return { ok = false, reason = string.format("Il te manque encore %d créature(s) %s.", s.Total - s.Owned, s.Label) }
			end
			profile.SetsClaimed[element] = true
			profile.Coins += VillageData.ElementSetReward
			return { ok = true, gems = VillageData.ElementSetReward }
		end
	end
	return { ok = false }
end

function actions.BuyBundle(player, profile)
	if not nearNpc(player, "Elya") then
		return { ok = false, reason = "Approche-toi de la boutique d'Elya." }
	end
	local shopData = VillageData.Shop
	local results, reason = CardService.openPaid(profile, shopData.BundlePrice, shopData.BundleCount)
	if not results then
		return { ok = false, reason = reason }
	end
	return { ok = true, results = results }
end

function actions.BuyElement(player, profile, element)
	if not nearNpc(player, "Elya") then
		return { ok = false, reason = "Approche-toi de la boutique d'Elya." }
	end
	if type(element) ~= "string" or CardsData.Elements[element] == nil then
		return { ok = false, reason = "Élément inconnu." }
	end
	local results, reason = CardService.openPaid(profile, VillageData.Shop.ElementPrice, 1, function(card)
		return card.Element == element
	end)
	if not results then
		return { ok = false, reason = reason }
	end
	return { ok = true, results = results }
end

function actions.SellDuplicates(player, profile)
	if not nearNpc(player, "Borin") then
		return { ok = false, reason = "Approche-toi de la forge de Borin." }
	end
	local total = 0
	for id, count in pairs(profile.Cards) do
		local card = CardsData.CardById[id]
		if card and count > 1 then
			total += math.floor((count - 1) * (CardsData.Economy.DuplicateRefund[card.Rarity] or 0) * VillageData.SellBonus)
			profile.Cards[id] = 1
		end
	end
	if total == 0 then
		return { ok = false, reason = "Tu n'as aucun doublon à vendre." }
	end
	profile.Coins += total
	return { ok = true, amount = total }
end

function actions.Fuse(player, profile, rarityId)
	if not nearNpc(player, "Borin") then
		return { ok = false, reason = "Approche-toi de la forge de Borin." }
	end
	local rarity = CardsData.RarityById[rarityId]
	local nextRarity = rarity and CardsData.Rarities[rarity.Order + 1]
	if not nextRarity then
		return { ok = false, reason = "Impossible de fusionner cette rareté." }
	end
	local cost = VillageData.FusionCost
	if duplicatesByRarity(profile)[rarityId] < cost then
		return { ok = false, reason = string.format("Il te faut %d doublons %s.", cost, rarity.Label) }
	end
	local remaining = cost
	while remaining > 0 do
		local bestId, bestCount = nil, 1
		for id, count in pairs(profile.Cards) do
			local card = CardsData.CardById[id]
			if card and card.Rarity == rarityId and count > bestCount then
				bestId, bestCount = id, count
			end
		end
		if not bestId then
			break
		end
		profile.Cards[bestId] -= 1
		remaining -= 1
	end
	local card = CardService.draw(function(c)
		return c.Rarity == nextRarity.Id
	end)
	return { ok = true, results = { CardService.grant(profile, card) } }
end

function actions.ClaimQuest(player, profile, questId)
	for _, state in ipairs(VillageData.questStates(profile)) do
		if state.Id == questId then
			if state.Claimed then
				return { ok = false, reason = "Récompense déjà réclamée." }
			elseif not state.Done then
				return { ok = false, reason = "Cette épreuve n'est pas terminée." }
			end
			profile.Quests[questId] = true
			profile.Coins += state.Reward
			return { ok = true, amount = state.Reward, quests = VillageData.questStates(profile) }
		end
	end
	return { ok = false, reason = "Quête inconnue." }
end

function actions.BuyMystic(player, profile)
	if not nearNpc(player, "Selene") then
		return { ok = false, reason = "Approche-toi de Sélène." }
	end
	local results, reason = CardService.openPaid(profile, VillageData.MysticPrice, 1, function(card)
		return CardsData.RarityById[card.Rarity].Order >= 4
	end)
	if not results then
		return { ok = false, reason = reason }
	end
	return { ok = true, results = results }
end

---------------------------------------------------------------------------
-- Duels entre joueurs, lancés auprès de Varek dans l'Arène des Champions
---------------------------------------------------------------------------
local DUEL_INVITE_TIME = 20
local DUEL_REWARD_WIN, DUEL_REWARD_LOSE, DUEL_REWARD_DRAW = 150, 30, 60
local duelInvites: { [Player]: { From: Player, Expires: number } } = {}
local inDuel: { [Player]: Player } = {}
-- Joueurs en entraînement contre le mannequin de Varek.
local training: { [Player]: boolean } = {}

local function colosseumCenter(): Vector3
	local c = L.Colosseum
	return Vector3.new(c.X, L.Ground + 0.5, c.Y)
end

-- Spectateurs : les joueurs proches du Cercle des Arcanes (et hors duel)
-- voient le combat en 3D. Les retardataires reçoivent l'état en cours.
local SPECTATE_RANGE = 110
local spectated = nil -- { Start = données, Latest = dernier état, Viewers = { [Player] = true } }

local function nearCircle(p: Player): boolean
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (root.Position - colosseumCenter()).Magnitude < SPECTATE_RANGE
end

local function spectateHook(a: Player)
	local view = { Viewers = {} }
	spectated = view
	return function(kind: string, data)
		if spectated ~= view then
			return
		end
		if kind == "Start" then
			view.Start = data
			view.Latest = data
		elseif kind == "Resolve" then
			view.Latest = data
		end
		for _, p in ipairs(Players:GetPlayers()) do
			local watching = view.Viewers[p]
			if not inDuel[p] and not training[p] and p ~= a and nearCircle(p) then
				if kind == "Start" or (kind == "Resolve" and watching) then
					view.Viewers[p] = true
					DuelEvent:FireClient(p, "Spec" .. kind, data)
				end
			end
			if kind == "End" and watching then
				DuelEvent:FireClient(p, "SpecEnd", data)
			end
		end
		if kind == "End" then
			spectated = nil
		end
	end
end

task.spawn(function()
	while true do
		task.wait(1)
		local view = spectated
		if view and view.Start then
			for _, p in ipairs(Players:GetPlayers()) do
				local near = nearCircle(p) and not inDuel[p] and not training[p]
				if near and not view.Viewers[p] then
					-- Arrivée en cours de duel : état actuel des deux équipes.
					local data = table.clone(view.Latest)
					data.MeInfo, data.OppInfo = view.Start.MeInfo, view.Start.OppInfo
					data.Events = nil
					view.Viewers[p] = true
					DuelEvent:FireClient(p, "SpecStart", data)
				elseif not near and view.Viewers[p] then
					view.Viewers[p] = nil
					DuelEvent:FireClient(p, "SpecEnd", {})
				end
			end
		end
	end
end)

local function endDuel(a: Player, reason: string)
	local b = inDuel[a]
	inDuel[a] = nil
	if b then
		inDuel[b] = nil
	end
	for _, p in ipairs({ a, b }) do
		if p and p.Parent then
			Notify:FireClient(p, reason, "Info")
			DuelEvent:FireClient(p, "End", {})
		end
	end
end

local function startDuel(a: Player, b: Player)
	inDuel[a], inDuel[b] = b, a
	local center = colosseumCenter()
	local gate = math.rad(L.ColosseumGate)
	-- Les deux duellistes se font face, perpendiculairement à l'axe des portes.
	local side = Vector3.new(-math.sin(gate), 0, math.cos(gate))
	for index, p in ipairs({ a, b }) do
		local character = p.Character
		if character then
			local pos = center + side * (index == 1 and 20 or -20) + Vector3.new(0, 4, 0)
			character:PivotTo(CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)))
		end
	end
	-- Combat de cartes : récompenses à la fin, puis fin du duel.
	local profileA, profileB = DataService.Get(a), DataService.Get(b)
	if not (profileA and profileB) then
		endDuel(a, "Le duel n'a pas pu commencer.")
		return
	end
	DuelCombat.start(a, b, profileA, profileB, function(player, kind, data)
		DuelEvent:FireClient(player, kind, data)
	end, function(winner, loser, reason)
		for _, pl in ipairs({ a, b }) do
			local profile = pl.Parent and DataService.Get(pl)
			if profile then
				local reward = winner == nil and DUEL_REWARD_DRAW or (pl == winner and DUEL_REWARD_WIN or DUEL_REWARD_LOSE)
				profile.Coins += reward
				DataService.MarkChanged(pl)
			end
		end
		task.delay(5, function()
			if inDuel[a] == b then
				endDuel(a, reason)
			end
		end)
	end, spectateHook(a))
end

-- Un duelliste qui quitte l'arène abandonne le duel.
task.spawn(function()
	while true do
		task.wait(2)
		local center = colosseumCenter()
		for p in pairs(inDuel) do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if p.Parent == nil or root == nil or (root.Position - center).Magnitude > L.ColosseumRadius + 15 then
				DuelCombat.forfeit(p, p.DisplayName .. " a quitté l'arène : abandon.")
				endDuel(p, "Le duel est terminé : un duelliste a quitté l'arène.")
			end
		end
	end
end)

function actions.DuelList(player)
	if not nearNpc(player, "Varek") then
		return { ok = false, reason = "Approche-toi de Varek, dans l'Arène des Champions." }
	end
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and not inDuel[other] then
			table.insert(list, { UserId = other.UserId, Name = other.DisplayName })
		end
	end
	return { ok = true, players = list }
end

function actions.DuelInvite(player, _profile, userId)
	if not nearNpc(player, "Varek") then
		return { ok = false, reason = "Approche-toi de Varek, dans l'Arène des Champions." }
	end
	if inDuel[player] or DuelCombat.isFighting(player) then
		return { ok = false, reason = "Tu es déjà en combat !" }
	end
	local target = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	if not target or target == player then
		return { ok = false, reason = "Ce dresseur n'est plus là." }
	end
	if inDuel[target] or DuelCombat.isFighting(target) then
		return { ok = false, reason = target.DisplayName .. " est déjà en plein combat." }
	end
	if #DuelCombat.deckFor(_profile) == 0 then
		return { ok = false, reason = "Il te faut au moins une créature : ouvre un booster à l'autel !" }
	end
	duelInvites[target] = { From = player, Expires = os.clock() + DUEL_INVITE_TIME }
	DuelEvent:FireClient(target, "Invite", { FromId = player.UserId, FromName = player.DisplayName, Duration = DUEL_INVITE_TIME })
	return { ok = true, message = string.format("Défi envoyé à %s ! Attends sa réponse...", target.DisplayName) }
end

function actions.DuelRespond(player, _profile, data)
	local invite = duelInvites[player]
	duelInvites[player] = nil
	if type(data) ~= "table" or not invite or invite.From.UserId ~= data.FromId or os.clock() > invite.Expires or invite.From.Parent == nil then
		return { ok = false, reason = "Ce défi n'est plus valable." }
	end
	if not data.Accept then
		Notify:FireClient(invite.From, player.DisplayName .. " a décliné ton défi.", "Info")
		return { ok = true }
	end
	if inDuel[player] or inDuel[invite.From] then
		return { ok = false, reason = "L'un de vous est déjà en duel." }
	end
	local myProfile = DataService.Get(player)
	if not myProfile or #DuelCombat.deckFor(myProfile) == 0 then
		Notify:FireClient(invite.From, player.DisplayName .. " n'a pas encore de créature pour combattre.", "Info")
		return { ok = false, reason = "Il te faut au moins une créature : ouvre un booster à l'autel !" }
	end
	startDuel(invite.From, player)
	return { ok = true }
end

Players.PlayerRemoving:Connect(function(player)
	duelInvites[player] = nil
	if inDuel[player] then
		DuelCombat.forfeit(player, player.DisplayName .. " est parti : abandon.")
		endDuel(player, "Le duel est terminé : ton adversaire est parti.")
	end
end)

-- Mode entraînement : combat contre un bot, sans récompense.
function actions.TrainingStart(player, profile)
	if not (nearNpc(player, "Varek") or nearNpc(player, "Rhea")) then
		return { ok = false, reason = "Approche-toi de Varek, au Cercle des Arcanes." }
	end
	if inDuel[player] or training[player] or DuelCombat.isFighting(player) then
		return { ok = false, reason = "Tu es déjà en combat !" }
	end
	if #DuelCombat.deckFor(profile) == 0 then
		return { ok = false, reason = "Il te faut au moins une créature : ouvre un booster à l'autel !" }
	end
	training[player] = true
	local center = colosseumCenter()
	local gate = math.rad(L.ColosseumGate)
	local sideDir = Vector3.new(-math.sin(gate), 0, math.cos(gate))
	local character = player.Character
	if character then
		local pos = center + sideDir * 20 + Vector3.new(0, 4, 0)
		character:PivotTo(CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)))
	end
	local bot = DuelCombat.newBot("Mannequin de Varek")
	DuelCombat.start(player, bot, profile, nil, function(target, kind, data)
		DuelEvent:FireClient(target, kind, data)
	end, function(winner, _loser, reason)
		-- Défi quotidien de Rhéa : la première victoire du jour rapporte des gemmes.
		local p = DataService.Get(player)
		if winner == player and p and p.DailyDuelDay < DataService.Today() then
			p.DailyDuelDay = DataService.Today()
			p.Coins += VillageData.DailyDuelReward
			DataService.MarkChanged(player)
			Notify:FireClient(player, string.format("Défi du jour réussi : +%d ◆ !", VillageData.DailyDuelReward), "Gold")
		end
		task.delay(5, function()
			training[player] = nil
			if player.Parent then
				Notify:FireClient(player, "Entraînement terminé : " .. reason, "Info")
				DuelEvent:FireClient(player, "End", {})
			end
		end)
	end, spectateHook(player))
	return { ok = true }
end

Players.PlayerRemoving:Connect(function(player)
	if training[player] then
		DuelCombat.forfeit(player, "Entraînement abandonné.")
		training[player] = nil
	end
end)

function actions.DuelPick(player, _profile, ids)
	local ok, reason = DuelCombat.pick(player, ids)
	return { ok = ok, reason = reason }
end

function actions.DuelAction(player, _profile, action)
	local ok, reason = DuelCombat.choose(player, action)
	return { ok = ok, reason = reason }
end

-- Téléportation depuis la carte du monde.
local lastTeleport: { [Player]: number } = {}
function actions.Teleport(player, _profile, id)
	if inDuel[player] then
		return { ok = false, reason = "Impossible de se téléporter pendant un duel." }
	end
	if os.clock() - (lastTeleport[player] or 0) < 3 then
		return { ok = false, reason = "Patiente un instant avant de te téléporter à nouveau." }
	end
	local point
	for _, p in ipairs(VillageData.Teleports) do
		if p.Id == id then
			point = p
		end
	end
	local character = player.Character
	if not (point and character) then
		return { ok = false, reason = "Destination inconnue." }
	end
	local hit = workspace:Raycast(Vector3.new(point.Pos.X, 250, point.Pos.Y), Vector3.new(0, -400, 0), rayParams)
	local y = hit and hit.Position.Y or 10
	lastTeleport[player] = os.clock()
	character:PivotTo(CFrame.new(point.Pos.X, y + 4, point.Pos.Y))
	return { ok = true, message = point.Label }
end

function actions.TutorialDone(_player, profile)
	profile.TutorialSeen = true
	return { ok = true }
end

local lastAction: { [Player]: number } = {}
local RateLimit = require(script.Parent:WaitForChild("RateLimit"))
local ECONOMY_ACTIONS = { BuyBundle = true, BuyElement = true, SellDuplicates = true, Fuse = true, ClaimQuest = true, BuyMystic = true,
	StallBuy = true, FarmBasket = true, ClaimSet = true }
NpcAction.OnServerInvoke = function(player, action, arg)
	local handler = type(action) == "string" and actions[action]
	local profile = DataService.Get(player)
	if not handler or not profile or not RateLimit.safeArg(arg) then
		return { ok = false, reason = "Action impossible." }
	end
	-- Débit global, plus serré pour les actions qui touchent à l'économie.
	if not RateLimit.allow(player, "NpcAction", 4, 8) then
		return { ok = false, reason = "Doucement !" }
	end
	if ECONOMY_ACTIONS[action] and not RateLimit.allow(player, "Eco", 1, 3) then
		return { ok = false, reason = "Doucement !" }
	end
	lastAction[player] = os.clock()
	local ok, result = pcall(handler, player, profile, arg)
	if not ok then
		warn("[Village] Action " .. tostring(action) .. " :", result)
		return { ok = false, reason = "Une erreur est survenue." }
	end
	result.profile = DataService.Snapshot(player)
	if result.ok and action ~= "Talk" then
		DataService.MarkChanged(player)
	end
	return result
end

Players.PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
end)

-- Tout est construit : on publie le nombre d'objets pour que les clients
-- attendent d'avoir tout reçu avant de lancer la partie.
-- Éclairage de nuit plus doux : on atténue toutes les sources lumineuses.
-- Les modèles sont toujours affichés en pleine qualité (pas de version simplifiée au loin).
for _, inst in ipairs(World:GetDescendants()) do
	if inst:IsA("Model") then
		pcall(function()
			(inst :: any).LevelOfDetail = Enum.ModelLevelOfDetail.Disabled
		end)
	end
	if inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
		inst.Brightness *= 0.45
		inst.Range *= 0.8
	end
end

workspace:SetAttribute("WorldPartCount", #World:GetDescendants())
workspace:SetAttribute("VillageReady", true)
