-- Ville de Brumeval (décor : BrumevalMap, construit par World) : PNJ R15
-- habillés et animés, villageois qui se promènent, Comptoir des Merveilles,
-- chasse au trésor et actions des PNJ (boutique, fusion, quêtes, duels).
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

local M = Enum.Material
local L = VillageData.Layout
local random = Random.new(2024)

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
-- Sol de la ville (dalles de BrumevalMap) et place de l'autel, pour les téléportations.
rayParams.FilterDescendantsInstances = { Terrain, World:WaitForChild("Brumeval"), World:WaitForChild("Arena") }

---------------------------------------------------------------------------
-- Ville de Brumeval : le décor est construit par World (BrumevalMap). Ici,
-- seulement ce qui sert au jeu : cachettes du trésor, boutique d'Elya, forge
-- de Borin et Comptoir des Merveilles (boutique Robux).
---------------------------------------------------------------------------
local NORTH, SOUTH, EAST, WEST = Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(1, 0), Vector2.new(-1, 0)

-- Cachettes du trésor (chasse désactivée pour l'instant).
local treasureSpots: { Vector3 } = {}
for _, c in ipairs({ { -150, -300 }, { -60, -60 }, { 300, -60 }, { -300, 60 }, { 190, -300 }, { 300, 300 }, { -150, 300 }, { 140, 160 } }) do
	table.insert(treasureSpots, Vector3.new(c[1], GROUND, c[2]))
end

-- Façades de la Grand-Place (bâtiments de 87 × 30 studs, façade au sud, z = 179).
local FACADE_Z = 179
local function facadeSign(x: number, text: string, color: Color3)
	local pos = Vector3.new(x, GROUND + 13, FACADE_Z + 0.25)
	local board = deco(part({ Name = "Enseigne", Size = Vector3.new(44, 4, 0.4), CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1)),
		Material = M.WoodPlanks, Color = Color3.fromRGB(60, 35, 95), Parent = villageFolder }))
	textSign(board, text, color, Enum.Font.Merriweather, { Enum.NormalId.Front })
	light(board, Color3.fromRGB(255, 220, 160), 1, 14)
end
facadeSign(59.5, "BOUTIQUE D'ELYA", Color3.fromRGB(255, 220, 140))
facadeSign(-59.5, "COMPTOIR DES MERVEILLES", Color3.fromRGB(225, 180, 80))

-- Elya devant sa boutique, Borin devant sa forge (entre les deux enclumes).
local shopCf = at(59.5, 175.4, SOUTH)
local forgeCf = at(-233, -261, SOUTH)

-- Comptoir des Merveilles : invite « Ouvrir la boutique » devant la façade.
do
	local m = model("WonderKiosk", villageFolder)
	local k = at(-59.5, FACADE_Z + 4, SOUTH)
	local violet, gold = Color3.fromRGB(95, 55, 160), Color3.fromRGB(225, 180, 80)
	for i = -3, 3 do
		local a = math.rad(i * 22)
		local cf = k * CFrame.Angles(0, a, 0) * CFrame.new(0, 1.2, -3.2)
		part({ Size = Vector3.new(1.35, 2.4, 0.9), CFrame = cf, Material = M.WoodPlanks, Color = violet, Parent = m })
		deco(part({ Size = Vector3.new(1.4, 0.25, 1.2), CFrame = cf * CFrame.new(0, 1.3, 0), Material = M.Metal, Color = gold, Reflectance = 0.2, Parent = m }))
	end
	local crystal = deco(part({ Size = Vector3.new(1.4, 2.6, 1.4), CFrame = k * CFrame.new(0, 6, 0) * CFrame.Angles(0, math.rad(45), 0), Material = M.Neon,
		Color = Color3.fromRGB(120, 230, 255), Parent = m }))
	light(crystal, Color3.fromRGB(140, 220, 255), 2, 22)
	local anchor = deco(part({ Size = Vector3.new(1, 1, 1), CFrame = k * CFrame.new(0, 3, -3.6), Transparency = 1, Parent = m }))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Ouvrir la boutique"
	prompt.ObjectText = "Comptoir des Merveilles"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
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
}
-- Varek : un de chaque côté, sur l'estrade devant les arènes de sa zone,
-- face aux dresseurs qui arrivent par l'avenue.
local function varekSpot(c: Vector2, gateDeg: number): CFrame
	local gate = math.rad(gateDeg)
	local outward = Vector3.new(math.cos(gate), 0, math.sin(gate))
	-- Sur son estrade, bien en avant des arènes (pas collé à l'arène centrale).
	local pos = Vector3.new(c.X, L.Ground + 1.1, c.Y) + outward * VillageData.Arena.VarekFront
	return CFrame.lookAt(pos, pos + outward)
end
npcSpots.Varek = varekSpot(L.Colosseum, L.ColosseumGate)
local npcExtras = { { "Varek", varekSpot(L.ArenaWest, L.ArenaWestGate) } }

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
	{ "Rhea", -156, -40, EAST, Color3.fromRGB(60, 70, 120), "Entraînement" }, -- parvis du colisée Ouest
	{ "Oswin", -200, 165, NORTH, Color3.fromRGB(160, 90, 30), "Étal d'Oswin" }, -- bourse aux cartes
	{ "Maelis", 24, -152, SOUTH, Color3.fromRGB(90, 40, 110), "Archives" }, -- galerie des collections
	{ "Gaelle", 150, -200, WEST, Color3.fromRGB(110, 140, 70), "Panier du jour" }, -- entrée du parc
	{ "Odile", 60, 272, SOUTH, Color3.fromRGB(150, 110, 160), "Contes" }, -- estrade des bardes
}
for _, d in ipairs(DISTRICT_NPCS) do
	local cf = at(d[2], d[3], d[4])
	npcSpots[d[1]] = cf
	stall(cf, d[5], d[6])
end

local function spawnNpc(id: string, spotCf: CFrame)
	local look = VillageData.Npcs[id]
	local npc = buildCharacter(id, look, spotCf, npcFolder)
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
for id, spotCf in pairs(npcSpots) do
	spawnNpc(id, spotCf)
end
for _, extra in ipairs(npcExtras) do
	spawnNpc(extra[1], extra[2])
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
	-- Avenue du Sud, allée de la Grand-Place, les quatre rues droites, avenue de l'Ouest.
	Gaspard = loop({ Vector2.new(3, 140), Vector2.new(3, 320), Vector2.new(-3, 320), Vector2.new(-3, 140) }),
	Lina = loop({ Vector2.new(-100, 223), Vector2.new(100, 223), Vector2.new(100, 227), Vector2.new(-100, 227) }),
	Tobias = loop({ Vector2.new(-320, -126), Vector2.new(320, -126), Vector2.new(320, -124), Vector2.new(-320, -124) }),
	Mira = loop(ringRoute(Vector2.zero, 100, 14)),
	Nell = loop({ Vector2.new(-320, 124), Vector2.new(320, 124), Vector2.new(320, 126), Vector2.new(-320, 126) }),
	Bram = loop({ Vector2.new(-126, -320), Vector2.new(-126, 320), Vector2.new(-124, 320), Vector2.new(-124, -320) }),
	Elise = loop({ Vector2.new(124, -320), Vector2.new(124, 320), Vector2.new(126, 320), Vector2.new(126, -320) }),
	Odo = loop({ Vector2.new(-114, 3), Vector2.new(-175, 3), Vector2.new(-175, -3), Vector2.new(-114, -3) }),
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
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	-- Plusieurs PNJ peuvent partager un id (un Varek par zone d'arènes).
	for _, npc in ipairs(npcFolder:GetChildren()) do
		if npc:GetAttribute("NpcId") == npcId and (npc:GetPivot().Position - root.Position).Magnitude < 25 then
			return true
		end
	end
	return false
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
		return { ok = false, reason = "Approche-toi de Gaëlle, à l'entrée du parc." }
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
		return { ok = false, reason = "Approche-toi de Maelis, à la galerie des collections." }
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

-- Arènes des Champions : six arènes (VillageData.arenaSlots), une par duel ou
-- entraînement en cours. Chaque combat réserve la sienne et la libère à la fin.
local ARENA = VillageData.Arena
local arenaBusy: { [string]: boolean } = {}
local arenaOf: { [Player]: any } = {} -- arène réservée par chaque combattant

local function arenaCenter(slot): Vector3
	return Vector3.new(slot.Center.X, L.Ground + ARENA.FloorHeight, slot.Center.Y)
end

-- Zone (Est / Ouest) la plus proche d'un joueur : on lui donne une arène de son côté.
local function zoneOf(player: Player): string?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local p = Vector2.new(root.Position.X, root.Position.Z)
	return if (p - L.Colosseum).Magnitude <= (p - L.ArenaWest).Magnitude then "Est" else "Ouest"
end

local function freeArena(preferredZone: string?): any?
	local fallback = nil
	for _, slot in ipairs(VillageData.arenaSlots()) do
		if not arenaBusy[slot.Id] then
			if slot.Zone == preferredZone then
				return slot
			end
			fallback = fallback or slot
		end
	end
	return fallback
end

-- Murs invisibles autour d'une arène pendant un combat : personne d'autre ne
-- peut y entrer (les spectateurs regardent depuis l'extérieur). Les joueurs
-- déjà dedans qui ne combattent pas sont reconduits devant l'entrée.
local BARRIER_HEIGHT = 40
local barriers: { [string]: Folder } = {}

local function closeArena(slot, fighters: { Player })
	if barriers[slot.Id] then
		return
	end
	local center = arenaCenter(slot)
	local axis = Vector3.new(slot.Axis.X, 0, slot.Axis.Y)
	local across = Vector3.new(-slot.Axis.Y, 0, slot.Axis.X)
	local halfL, halfW = ARENA.Length / 2 + 1, ARENA.Width / 2 + 1
	local folder = Instance.new("Folder")
	folder.Name = "Barriere_" .. slot.Id
	local base = CFrame.fromMatrix(center + Vector3.new(0, BARRIER_HEIGHT / 2 - ARENA.FloorHeight, 0), across, Vector3.yAxis)
	for _, w in ipairs({
		{ CFrame.new(0, 0, halfL), Vector3.new(halfW * 2 + 2, BARRIER_HEIGHT, 1) },
		{ CFrame.new(0, 0, -halfL), Vector3.new(halfW * 2 + 2, BARRIER_HEIGHT, 1) },
		{ CFrame.new(halfW, 0, 0), Vector3.new(1, BARRIER_HEIGHT, halfL * 2 + 2) },
		{ CFrame.new(-halfW, 0, 0), Vector3.new(1, BARRIER_HEIGHT, halfL * 2 + 2) },
	}) do
		local wall = Instance.new("Part")
		wall.Name = "MurInvisible"
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanQuery = false -- ne gêne ni les caméras ni les rayons du combat
		wall.CanTouch = false
		wall.Transparency = 1
		wall.CastShadow = false
		wall.Size = w[2]
		wall.CFrame = base * w[1]
		wall.Parent = folder
	end
	folder.Parent = World
	barriers[slot.Id] = folder

	-- Intrus déjà sur la piste : reconduits devant l'entrée de l'arène.
	local exitPos = center + axis * (halfL + 6) + Vector3.new(0, 3, 0)
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and not table.find(fighters, p) then
			local rel = root.Position - center
			if math.abs(rel:Dot(axis)) < halfL + 1 and math.abs(rel:Dot(across)) < halfW + 1 then
				p.Character:PivotTo(CFrame.lookAt(exitPos, Vector3.new(center.X, exitPos.Y, center.Z)))
			end
		end
	end
end

local function openArena(slotId: string)
	local folder = barriers[slotId]
	if folder then
		folder:Destroy()
		barriers[slotId] = nil
	end
end

local function reserveArena(players: { Player }, preferredZone: string?): any?
	local slot = freeArena(preferredZone)
	if slot then
		arenaBusy[slot.Id] = true
		for _, p in ipairs(players) do
			arenaOf[p] = slot
			p:SetAttribute("DuelArena", slot.Id)
		end
		closeArena(slot, players)
	end
	return slot
end

local function releaseArena(players: { Player? })
	for _, p in ipairs(players) do
		if p then
			local slot = arenaOf[p]
			if slot then
				arenaBusy[slot.Id] = nil
				openArena(slot.Id)
			end
			arenaOf[p] = nil
			if p.Parent then
				p:SetAttribute("DuelArena", nil)
			end
		end
	end
end

-- Place un combattant sur sa marque (±20 studs sur l'axe), face au centre.
local function placeOnArena(character: Model?, slot, sign: number)
	if not character then
		return
	end
	local center = arenaCenter(slot)
	local axis = Vector3.new(slot.Axis.X, 0, slot.Axis.Y)
	local pos = center + axis * 20 * sign + Vector3.new(0, 3, 0)
	character:PivotTo(CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)))
end

-- Spectateurs : les joueurs proches d'une arène (et hors combat) voient son
-- duel en 3D. Les retardataires reçoivent l'état en cours.
local SPECTATE_RANGE = 45
local spectated: { [string]: any } = {} -- [id d'arène] = { Start, Latest, Viewers }

-- Arène la plus proche d'un joueur, si elle est à portée de regard.
local function arenaNear(p: Player): string?
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local best, bestD = nil, SPECTATE_RANGE
	for _, slot in ipairs(VillageData.arenaSlots()) do
		local d = (root.Position - arenaCenter(slot)).Magnitude
		if d < bestD then
			best, bestD = slot.Id, d
		end
	end
	return best
end

local function spectateHook(a: Player, slot)
	local view = { Viewers = {} }
	spectated[slot.Id] = view
	return function(kind: string, data)
		if spectated[slot.Id] ~= view then
			return
		end
		if type(data) == "table" then
			data.Arena = slot.Id
		end
		if kind == "Start" then
			view.Start = data
			view.Latest = data
		elseif kind == "Resolve" then
			view.Latest = data
		end
		for _, p in ipairs(Players:GetPlayers()) do
			local watching = view.Viewers[p]
			if not inDuel[p] and not training[p] and p ~= a and arenaNear(p) == slot.Id then
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
			spectated[slot.Id] = nil
		end
	end
end

task.spawn(function()
	while true do
		task.wait(1)
		for id, view in pairs(spectated) do
			if view.Start then
				for _, p in ipairs(Players:GetPlayers()) do
					local near = arenaNear(p) == id and not inDuel[p] and not training[p]
					if near and not view.Viewers[p] then
						-- Arrivée en cours de duel : état actuel des deux équipes.
						local data = table.clone(view.Latest)
						data.MeInfo, data.OppInfo = view.Start.MeInfo, view.Start.OppInfo
						data.Events = nil
						data.Arena = id
						view.Viewers[p] = true
						DuelEvent:FireClient(p, "SpecStart", data)
					elseif not near and view.Viewers[p] then
						view.Viewers[p] = nil
						DuelEvent:FireClient(p, "SpecEnd", {})
					end
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
	releaseArena({ a, b })
	for _, p in ipairs({ a, b }) do
		if p and p.Parent then
			Notify:FireClient(p, reason, "Info")
			DuelEvent:FireClient(p, "End", {})
		end
	end
end

local function startDuel(a: Player, b: Player)
	local slot = reserveArena({ a, b }, zoneOf(a))
	if not slot then
		for _, p in ipairs({ a, b }) do
			Notify:FireClient(p, "Toutes les arènes sont occupées : réessaie dans un instant.", "Info")
		end
		return
	end
	inDuel[a], inDuel[b] = b, a
	-- Les deux duellistes se font face sur l'axe de leur arène.
	placeOnArena(a.Character, slot, 1)
	placeOnArena(b.Character, slot, -1)
	-- Combat de cartes : récompenses à la fin, puis fin du duel.
	local profileA, profileB = DataService.Get(a), DataService.Get(b)
	if not (profileA and profileB) then
		endDuel(a, "Le duel n'a pas pu commencer.")
		return
	end
	DuelCombat.start(a, b, profileA, profileB, function(player, kind, data)
		if kind == "Start" and type(data) == "table" then
			data.Arena = slot.Id
		end
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
	end, spectateHook(a, slot))
end

-- Un duelliste qui quitte son arène abandonne le duel.
task.spawn(function()
	while true do
		task.wait(2)
		for p in pairs(inDuel) do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			local slot = arenaOf[p]
			local far = slot and root and (root.Position - arenaCenter(slot)).Magnitude > ARENA.Length / 2 + 18
			if p.Parent == nil or root == nil or far then
				DuelCombat.forfeit(p, p.DisplayName .. " a quitté l'arène : abandon.")
				endDuel(p, "Le duel est terminé : un duelliste a quitté l'arène.")
			end
		end
	end
end)

function actions.DuelList(player)
	if not nearNpc(player, "Varek") then
		return { ok = false, reason = "Approche-toi de Varek, aux Arènes des Champions." }
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
		return { ok = false, reason = "Approche-toi de Varek, aux Arènes des Champions." }
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
	if not freeArena(nil) then
		return { ok = false, reason = "Les six arènes sont occupées : réessaie dans un instant." }
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
	if not freeArena(nil) then
		Notify:FireClient(invite.From, "Les six arènes sont occupées : relance le défi dans un instant.", "Info")
		return { ok = false, reason = "Les six arènes sont occupées : réessaie dans un instant." }
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

-- Mode entraînement : combat contre un bot, sans récompense, dans une arène libre.
function actions.TrainingStart(player, profile)
	if not (nearNpc(player, "Varek") or nearNpc(player, "Rhea")) then
		return { ok = false, reason = "Approche-toi de Varek, aux Arènes des Champions." }
	end
	if inDuel[player] or training[player] or DuelCombat.isFighting(player) then
		return { ok = false, reason = "Tu es déjà en combat !" }
	end
	if #DuelCombat.deckFor(profile) == 0 then
		return { ok = false, reason = "Il te faut au moins une créature : ouvre un booster à l'autel !" }
	end
	local slot = reserveArena({ player }, zoneOf(player))
	if not slot then
		return { ok = false, reason = "Les six arènes sont occupées : réessaie dans un instant." }
	end
	training[player] = true
	placeOnArena(player.Character, slot, 1)
	local bot = DuelCombat.newBot("Mannequin de Varek")
	DuelCombat.start(player, bot, profile, nil, function(target, kind, data)
		if kind == "Start" and type(data) == "table" then
			data.Arena = slot.Id
		end
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
			releaseArena({ player })
			if player.Parent then
				Notify:FireClient(player, "Entraînement terminé : " .. reason, "Info")
				DuelEvent:FireClient(player, "End", {})
			end
		end)
	end, spectateHook(player, slot))
	return { ok = true }
end

Players.PlayerRemoving:Connect(function(player)
	if training[player] then
		DuelCombat.forfeit(player, "Entraînement abandonné.")
		training[player] = nil
		releaseArena({ player })
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
