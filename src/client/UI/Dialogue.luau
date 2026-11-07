-- Boîte de dialogue des PNJ : portrait 3D du personnage, plaque de nom,
-- texte animé avec indicateur, choix en boutons et ornements dorés.
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local UIKit = require(script.Parent:WaitForChild("UIKit"))

local Dialogue = {}
Dialogue.__index = Dialogue

export type Choice = {
	Text: string,
	Style: string?,
	Dimmed: boolean?,
	Callback: () -> (),
}

local GOLD = Color3.fromRGB(255, 205, 110)

local function ornament(parent: Instance, position: UDim2, anchor: Vector2)
	local gem = UIKit.new("Frame", {
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(14, 14),
		Rotation = 45,
		BackgroundColor3 = GOLD,
		ZIndex = 4,
		Parent = parent,
	})
	UIKit.stroke(gem, Color3.fromRGB(120, 70, 20), 1.5, 0)
end

function Dialogue.new(parent: Instance)
	local self = setmetatable({}, Dialogue)
	self.IsOpen = false
	self.TypeToken = 0

	local root = UIKit.new("Frame", {
		Name = "Dialogue",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(980, 360),
		Visible = false,
		ZIndex = 15,
		Parent = parent,
	})
	self.Root = root
	UIKit.scaled(root)
	-- Le contenu glisse depuis le bas de l'écran (ClipsDescendants masque la sortie).
	root.ClipsDescendants = true
	self.Slide = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })

	-- Fenêtre principale (laisse 34 px en haut pour la plaque de nom).
	local window = UIKit.new("Frame", {
		Name = "Window",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(10, 34),
		Size = UDim2.new(1, -20, 1, -44),
		Parent = self.Slide,
	})
	UIKit.corner(window, 26)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 36, 82)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(26, 20, 48)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 10, 28)),
		}),
		Rotation = 90,
		Parent = window,
	})
	local border = UIKit.stroke(window, GOLD, 2.5, 0.15)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 150)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(190, 140, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 225, 150)),
		}),
		Rotation = 0,
		Parent = border,
	})
	-- Liseré lumineux en haut.
	local shine = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Position = UDim2.new(0.08, 0, 0, 2),
		Size = UDim2.new(0.84, 0, 0, 2),
		Parent = window,
	})
	UIKit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = shine,
	})
	ornament(window, UDim2.fromOffset(0, 0), Vector2.new(0.5, 0.5))
	ornament(window, UDim2.fromScale(1, 0), Vector2.new(0.5, 0.5))
	ornament(window, UDim2.fromScale(0, 1), Vector2.new(0.5, 0.5))
	ornament(window, UDim2.fromScale(1, 1), Vector2.new(0.5, 0.5))

	-- Portrait 3D.
	local portraitFrame = UIKit.new("Frame", {
		Position = UDim2.fromOffset(24, 22),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = window,
	})
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = portraitFrame })
	self.PortraitGradient = UIKit.new("UIGradient", { Rotation = 90, Parent = portraitFrame })
	UIKit.stroke(portraitFrame, GOLD, 4, 0)
	local viewport = UIKit.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(170, 160, 190),
		LightColor = Color3.fromRGB(255, 240, 220),
		LightDirection = Vector3.new(-0.5, -1, -0.8),
		Parent = portraitFrame,
	})
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = viewport })
	self.Viewport = viewport
	self.FallbackIcon = UIKit.label({
		Text = "",
		Font = UIKit.Fonts.Black,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.55, 0.55),
		Parent = portraitFrame,
	}, 70)

	-- Plaque de nom qui dépasse au-dessus de la fenêtre.
	local plate = UIKit.new("Frame", {
		Name = "NamePlate",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(190, 0),
		Size = UDim2.fromOffset(330, 58),
		ZIndex = 3,
		Parent = self.Slide,
	})
	UIKit.corner(plate, 16)
	UIKit.gradient(plate, Color3.fromRGB(255, 225, 150), Color3.fromRGB(220, 150, 50), 90)
	UIKit.stroke(plate, Color3.fromRGB(120, 70, 20), 2, 0)
	self.NameLabel = UIKit.label({
		Text = "",
		Font = UIKit.Fonts.Title,
		TextColor3 = Color3.fromRGB(60, 30, 5),
		Position = UDim2.fromOffset(18, 4),
		Size = UDim2.new(1, -36, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = plate,
	}, 32)
	self.RoleLabel = UIKit.label({
		Text = "",
		Font = UIKit.Fonts.Black,
		TextColor3 = Color3.fromRGB(110, 60, 15),
		Position = UDim2.fromOffset(19, 36),
		Size = UDim2.new(1, -36, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = plate,
	}, 14)

	-- Texte.
	self.TextLabel = UIKit.label({
		Text = "",
		Font = UIKit.Fonts.Body,
		TextColor3 = Color3.fromRGB(240, 235, 255),
		Position = UDim2.fromOffset(196, 34),
		Size = UDim2.new(1, -236, 0, 92),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.15,
		Parent = window,
	}, 21)
	-- Indicateur « suite » qui rebondit quand le texte est fini.
	self.Cursor = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -40, 0, 128),
		Size = UDim2.fromOffset(10, 10),
		Rotation = 45,
		BackgroundColor3 = GOLD,
		Visible = false,
		Parent = window,
	})

	self.CloseButton = UIKit.button({
		Text = "X",
		Style = "Danger",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(42, 42),
		TextSize = 18,
		Parent = window,
		Callback = function()
			self:Close()
		end,
	})

	-- Séparateur et choix.
	local divider = UIKit.new("Frame", {
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(196, 144),
		Size = UDim2.new(1, -220, 0, 1),
		Parent = window,
	})
	UIKit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = divider,
	})

	local choices = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 186),
		Size = UDim2.new(1, -40, 1, -200),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = GOLD,
		Selectable = false,
		Parent = window,
	})
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0, 46),
		CellPadding = UDim2.fromOffset(12, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = choices,
	})
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8), Parent = choices })
	self.Choices = choices

	-- Petite animation continue du curseur.
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		if self.IsOpen and self.Cursor.Visible then
			t += dt
			self.Cursor.Position = UDim2.new(1, -40, 0, 128 + math.sin(t * 6) * 3)
		end
	end)

	return self
end

function Dialogue:SetPortrait(npc)
	local viewport = self.Viewport
	for _, child in ipairs(viewport:GetChildren()) do
		if not child:IsA("UICorner") then
			child:Destroy()
		end
	end
	local shirt = npc.Shirt or UIKit.Colors.Accent
	self.PortraitGradient.Color = ColorSequence.new(shirt:Lerp(Color3.new(1, 1, 1), 0.45), shirt:Lerp(Color3.new(0, 0, 0), 0.35))
	self.FallbackIcon.Text = string.sub(npc.Name or "?", 1, 1)

	local world = workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild("NPCs")
	local source = folder and npc.Id and folder:FindFirstChild(npc.Id)
	if not source then
		return
	end
	local ok, clone = pcall(function()
		return source:Clone()
	end)
	if not ok or not clone then
		return
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BillboardGui") or d:IsA("ProximityPrompt") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	clone:PivotTo(CFrame.new())
	clone.Parent = viewport
	local head = clone:FindFirstChild("Head") :: BasePart?
	if head then
		self.FallbackIcon.Text = ""
		-- Caméra calée sur le repère de la tête (l'avant d'une tête Roblox est -Z) :
		-- le visage est toujours de face, quelle que soit l'orientation du PNJ.
		local headCf = head.CFrame
		local focus = headCf.Position - headCf.UpVector * 0.35
		local camera = Instance.new("Camera")
		camera.FieldOfView = 32
		camera.CFrame = CFrame.lookAt((headCf * CFrame.new(0.6, 0.3, -5.5)).Position, focus, headCf.UpVector)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end
end

function Dialogue:SetText(text: string)
	self.TypeToken += 1
	local token = self.TypeToken
	local label = self.TextLabel
	label.Text = text
	label.MaxVisibleGraphemes = 0
	self.Cursor.Visible = false
	task.spawn(function()
		local length = utf8.len(text) or #text
		local shown = 0
		while shown < length and token == self.TypeToken do
			shown = math.min(length, shown + 2)
			label.MaxVisibleGraphemes = shown
			task.wait(0.014)
		end
		if token == self.TypeToken then
			label.MaxVisibleGraphemes = -1
			self.Cursor.Visible = true
		end
	end)
end

function Dialogue:SetChoices(list: { Choice })
	for _, child in ipairs(self.Choices:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local first = nil
	for index, choice in ipairs(list) do
		local button = UIKit.button({
			Text = choice.Text,
			Style = choice.Style or "Ghost",
			Align = "Left",
			LayoutOrder = index,
			TextSize = 17,
			Parent = self.Choices,
			Callback = choice.Callback,
		})
		if choice.Dimmed then
			UIKit.setDimmed(button, true)
		end
		-- Apparition en cascade.
		local scale = button:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 0.85
			task.delay(index * 0.03, function()
				UIKit.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
		end
		first = first or button
	end
	self.Choices.CanvasPosition = Vector2.zero
	UIKit.focus(first)
end

function Dialogue:Open(npc, text: string, choices: { Choice })
	local newNpc = self.CurrentNpc ~= npc
	self.CurrentNpc = npc
	self.NameLabel.Text = npc.Name
	self.RoleLabel.Text = string.upper(npc.Role)
	if newNpc or not self.IsOpen then
		self:SetPortrait(npc)
	end
	self:SetText(text)
	self:SetChoices(choices)
	if not self.IsOpen then
		self.IsOpen = true
		self.Root.Visible = true
		self.Slide.Position = UDim2.fromOffset(0, 420)
		UIKit.tween(self.Slide, 0.45, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	end
end

function Dialogue:Close()
	if not self.IsOpen then
		return
	end
	self.IsOpen = false
	self.CurrentNpc = nil
	self.TypeToken += 1
	UIKit.tween(self.Slide, 0.25, { Position = UDim2.fromOffset(0, 420) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
		if not self.IsOpen then
			self.Root.Visible = false
		end
	end)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.Root) then
		GuiService.SelectedObject = nil
	end
	if self.OnClose then
		self.OnClose()
	end
end

return Dialogue
