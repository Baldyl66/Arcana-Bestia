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
			local textured = descendant:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil or descendant.TextureID ~= ""
			if textured then
				-- Une pièce texturée (couvertures « ARCANA », reliure, pages de menu)
				-- garde les couleurs de sa texture : une teinte la noircirait.
				descendant.Color = Color3.new(1, 1, 1)
				descendant.Material = Enum.Material.SmoothPlastic
			elseif look then
				descendant.Color = look[1]
				descendant.Material = look[2]
			end
		end
	end
	-- La coque en cuir (« couverture ») déborde un peu de sa boîte à l'avant et à
	-- l'arrière : elle recouvrait les couvertures texturées. On les sort, chacune
	-- de son côté (l'avant regarde vers -Z, le dos vers +Z) ; valeur testée en jeu.
	-- Le modèle importé contient ses propres articulations (Motor6D) : en main,
	-- elles ramèneraient chaque pièce à sa place d'origine et annuleraient le
	-- décalage ci-dessous. Tout est soudé à la poignée plus bas, on les retire.
	for _, joint in ipairs(book:GetDescendants()) do
		if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
			joint:Destroy()
		end
	end
	-- L'anneau doré et la gemme bouchent le trou de l'image de couverture : ils suivent.
	for name, dz in pairs({ couverture_avant = -0.16, ["or"] = -0.16, gemme = -0.16, couverture_dos = 0.16 }) do
		local cover = book:FindFirstChild(name, true)
		if cover and cover:IsA("BasePart") then
			cover.CFrame = cover.CFrame * CFrame.new(0, 0, dz)
		end
	end

	local _, bounds = book:GetBoundingBox()
	local largest = math.max(bounds.X, bounds.Y, bounds.Z)
	if largest > 0 then
		book:ScaleTo(book:GetScale() * 1.6 / largest)
	end

	-- Orientation en main, mesurée dans Studio avec le livre équipé : la pose
	-- « livre en main » tient la poignée devant la poitrine, debout (+Y = haut),
	-- tournée de 33° vers la droite du personnage.
	-- Repère du livre : +Y = haut, -Z = couverture avant, +X = reliure.
	-- On veut le livre debout, couverture vers l'avant (légèrement tournée vers
	-- l'extérieur, 15°), reliure côté main droite :
	--   livre/poignée = (poignée/corps)⁻¹ × (livre/corps) = rotY(-33°) × rotY(-15°).
	local inHand = CFrame.Angles(0, math.rad(-48), 0)
	local boxCF = book:GetBoundingBox()
	local centerOffset = book:GetPivot():ToObjectSpace(boxCF)
	-- Centre du livre juste au-dessus de la main.
	book:PivotTo(handle.CFrame * CFrame.new(0, 0.25, 0) * inHand * CFrame.new(-centerOffset.Position))
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
