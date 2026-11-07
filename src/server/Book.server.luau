local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")
local Workspace = game:GetService("Workspace")

local TOOL_NAME = "Carnet"

-- Couleurs du fichier livre_arcana_magique.glb, pièce par pièce.
local BOOK_PALETTE = {
	couverture = { Color3.fromRGB(62, 22, 19), Enum.Material.Leather },
	couverture_avant = { Color3.fromRGB(62, 22, 19), Enum.Material.Leather },
	couverture_dos = { Color3.fromRGB(62, 22, 19), Enum.Material.Leather },
	dos = { Color3.fromRGB(62, 22, 19), Enum.Material.Leather },
	dos_reliure = { Color3.fromRGB(176, 138, 62), Enum.Material.Metal },
	["or"] = { Color3.fromRGB(201, 160, 74), Enum.Material.Metal },
	metal = { Color3.fromRGB(176, 138, 62), Enum.Material.Metal },
	gemme = { Color3.fromRGB(42, 184, 216), Enum.Material.Glass },
	pages = { Color3.fromRGB(232, 216, 178), Enum.Material.SmoothPlastic },
	ruban = { Color3.fromRGB(122, 26, 20), Enum.Material.Fabric },
}

local function makePart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Parent = parent
	return part
end

local function createBookTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.ToolTip = "Ouvrir le carnet"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0.3, -0.25, 0.18)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 0.4, 0.4)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local source = ServerStorage:FindFirstChild("CarnetModel")
		or ReplicatedStorage:FindFirstChild("CarnetModel")
		or Workspace:FindFirstChild("CarnetModel")
	local book = if source and source:IsA("Model") then source:Clone() else Instance.new("Model")
	book.Name = "CarnetVisuel"
	if not source then
		local origin = CFrame.new()
		makePart(book, "CoverBack", Vector3.new(1.9, 2.5, 0.08), origin * CFrame.new(0, 0, 0.22), Color3.fromRGB(125, 30, 35), Enum.Material.Fabric)
		makePart(book, "Pages", Vector3.new(1.75, 2.3, 0.32), origin, Color3.fromRGB(242, 235, 215), Enum.Material.SmoothPlastic)
		makePart(book, "CoverFront", Vector3.new(1.9, 2.5, 0.08), origin * CFrame.new(0, 0, -0.22), Color3.fromRGB(155, 38, 40), Enum.Material.Fabric)
		makePart(book, "Spine", Vector3.new(0.14, 2.55, 0.48), origin * CFrame.new(-0.9, 0, 0), Color3.fromRGB(80, 20, 28), Enum.Material.Fabric)
		makePart(book, "Emblem", Vector3.new(0.65, 0.65, 0.05), origin * CFrame.new(0, 0.2, -0.27), Color3.fromRGB(230, 185, 80), Enum.Material.Metal)
	end
	-- L'import 3D perd les couleurs unies du fichier : on les réapplique
	-- d'après le nom des pièces (les pièces texturées restent en blanc).
	for _, descendant in ipairs(book:GetDescendants()) do
		if descendant:IsA("MeshPart") then
			local look = BOOK_PALETTE[string.lower(descendant.Name)]
			if look then
				descendant.Color = look[1]
				descendant.Material = look[2]
			else
				if descendant:FindFirstChildWhichIsA("SurfaceAppearance") or descendant.TextureID ~= "" then
					descendant.Color = Color3.new(1, 1, 1)
				end
			end
		end
	end
	local _, bounds = book:GetBoundingBox()
	local largest = math.max(bounds.X, bounds.Y, bounds.Z)
	if largest > 0 then
		book:ScaleTo(book:GetScale() * 1.6 / largest)
	end

	-- Orientation en main. Repère de la poignée Roblox (bras le long du
	-- corps) : +Z = haut, +Y = devant, +X = extérieur (droite).
	-- Repère du livre : +Y = haut, -Z = couverture avant, +X = reliure.
	-- On veut le livre debout, couverture avant tournée vers l'extérieur,
	-- comme dans l'animation d'ouverture.
	local inHand = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(0, 0, 1))
	local boxCF = book:GetBoundingBox()
	local centerOffset = book:GetPivot():ToObjectSpace(boxCF)
	-- La main tient le bas du livre : centre un peu au-dessus de la poignée.
	book:PivotTo(handle.CFrame * CFrame.new(0, 0, 0.35) * inHand * CFrame.new(-centerOffset.Position))
	for _, descendant in ipairs(book:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
	book.Parent = tool
	return tool
end

local function giveBook(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	if backpack:FindFirstChild(TOOL_NAME) or (player.Character and player.Character:FindFirstChild(TOOL_NAME)) then
		return
	end
	local template = StarterPack:FindFirstChild(TOOL_NAME)
	if template then
		template:Clone().Parent = backpack
	end
end

local existing = StarterPack:FindFirstChild(TOOL_NAME)
if existing then
	existing:Destroy()
end
createBookTool().Parent = StarterPack

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.defer(giveBook, player)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.defer(giveBook, player)
end
