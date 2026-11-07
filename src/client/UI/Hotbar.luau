-- Barre d'objets en bas de l'écran (remplace le sac à dos Roblox) : une case
-- carrée au contour doré par outil, avec l'objet en 3D à l'intérieur.
-- Clic, toucher ou touche du numéro pour équiper / ranger.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent:WaitForChild("UIKit"))

local Hotbar = {}

local player = Players.LocalPlayer
local SLOT = 74
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }

local gui: ScreenGui
local row: Frame
local slots: { [Tool]: { Frame: Frame, Stroke: UIStroke, Model: Model? } } = {}
local order: { Tool } = {}

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function toggle(tool: Tool)
	local h = humanoid()
	if not h then
		return
	end
	if tool.Parent == player.Character then
		h:UnequipTools()
	else
		h:EquipTool(tool)
	end
end

-- Visuel 3D de l'outil (son modèle, sinon sa poignée) cadré dans la case.
local function preview(tool: Tool, viewport: ViewportFrame): Model?
	local source = tool:FindFirstChildWhichIsA("Model")
	local clone: Model
	if source then
		clone = source:Clone()
	else
		clone = Instance.new("Model")
		for _, child in ipairs(tool:GetChildren()) do
			if child:IsA("BasePart") then
				child:Clone().Parent = clone
			end
		end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("LuaSourceContainer") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
	-- Les pièces invisibles (poignée) décaleraient le cadrage : on les retire.
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency >= 0.99 then
			d:Destroy()
		end
	end
	clone:PivotTo(CFrame.new())
	clone.Parent = viewport
	local cf, size = clone:GetBoundingBox()
	clone:PivotTo(CFrame.new() * cf:Inverse() * clone:GetPivot())
	-- Face la plus large tournée vers la caméra (couverture du carnet).
	if size.X <= size.Y and size.X <= size.Z then
		clone:PivotTo(CFrame.Angles(0, math.pi / 2, 0) * clone:GetPivot())
		size = Vector3.new(size.Z, size.Y, size.X)
	elseif size.Y <= size.X and size.Y <= size.Z then
		clone:PivotTo(CFrame.Angles(math.pi / 2, 0, 0) * clone:GetPivot())
		size = Vector3.new(size.X, size.Z, size.Y)
	end
	clone.WorldPivot = CFrame.new()
	clone:SetAttribute("BasePivot", clone:GetPivot())
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = math.max(size.X, size.Y) / (2 * math.tan(math.rad(15))) * 0.95 + size.Z
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, -distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return clone
end

local function refresh()
	for index, tool in ipairs(order) do
		local slot = slots[tool]
		slot.Frame.LayoutOrder = index
		local equipped = tool.Parent == player.Character and player.Character ~= nil
		TweenService:Create(slot.Stroke, TweenInfo.new(0.15), {
			Thickness = equipped and 4 or 2.5,
			Color = equipped and Color3.fromRGB(255, 236, 170) or UIKit.Colors.Gold,
		}):Play()
		TweenService:Create(slot.Frame, TweenInfo.new(0.15), {
			BackgroundColor3 = equipped and UIKit.Colors.PanelLight or UIKit.Colors.Panel,
		}):Play()
	end
end

local function addTool(tool: Instance)
	if not tool:IsA("Tool") or slots[tool] then
		return
	end
	local frame = UIKit.new("TextButton", {
		Name = tool.Name,
		Size = UDim2.fromOffset(SLOT, SLOT),
		BackgroundColor3 = UIKit.Colors.Panel,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	}) :: TextButton
	UIKit.new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = frame })
	local stroke = UIKit.new("UIStroke", { Color = UIKit.Colors.Gold, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame }) :: UIStroke
	local viewport = UIKit.new("ViewportFrame", {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 160, 190),
		LightColor = Color3.fromRGB(255, 245, 225),
		LightDirection = Vector3.new(-0.5, -1, 0.6),
		Parent = frame,
	}) :: ViewportFrame
	local m = preview(tool, viewport)
	slots[tool] = { Frame = frame, Stroke = stroke, Model = m }
	table.insert(order, tool)
	frame.Activated:Connect(function()
		toggle(tool)
	end)
	frame.MouseEnter:Connect(function()
		TweenService:Create(frame, TweenInfo.new(0.12), { Size = UDim2.fromOffset(SLOT + 6, SLOT + 6) }):Play()
	end)
	frame.MouseLeave:Connect(function()
		TweenService:Create(frame, TweenInfo.new(0.12), { Size = UDim2.fromOffset(SLOT, SLOT) }):Play()
	end)
	tool.AncestryChanged:Connect(function()
		local parent = tool.Parent
		if parent == nil or not (parent:IsA("Backpack") or parent == player.Character) then
			frame:Destroy()
			slots[tool] = nil
			local index = table.find(order, tool)
			if index then
				table.remove(order, index)
			end
		end
		refresh()
	end)
	refresh()
end

local function watch(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		addTool(child)
	end
	container.ChildAdded:Connect(addTool)
end

function Hotbar.Init()
	gui = UIKit.new("ScreenGui", {
		Name = "ArcanaHotbar",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		-- Sous l'interface principale : les panneaux ouverts passent par-dessus.
		DisplayOrder = -1,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	row = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(SLOT * 5, SLOT + 8),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})

	local function bindCharacter(character: Model)
		-- Nouveau personnage : le sac à dos est recréé, on repart de zéro.
		for tool, slot in pairs(slots) do
			slot.Frame:Destroy()
			slots[tool] = nil
		end
		table.clear(order)
		watch(player:WaitForChild("Backpack"))
		watch(character)
	end
	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not gui.Enabled then
			return
		end
		local index = table.find(KEYS, input.KeyCode)
		if index and order[index] then
			toggle(order[index])
		end
	end)

	-- Le carnet se balance doucement dans sa case.
	RunService.RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		local t = os.clock()
		for _, slot in pairs(slots) do
			local m = slot.Model
			local base = m and m:GetAttribute("BasePivot")
			if m and base then
				m:PivotTo(CFrame.Angles(math.sin(t * 0.8) * 0.06, math.sin(t * 1.1) * 0.2, 0) * base)
			end
		end
	end)
end

function Hotbar.SetVisible(visible: boolean)
	if gui then
		gui.Enabled = visible
	end
end

return Hotbar
