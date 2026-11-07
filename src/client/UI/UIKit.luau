-- Boîte à outils UI partagée : thème, création d'instances, boutons animés,
-- panneaux modaux et mise à l'échelle selon la taille d'écran.
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local UIKit = {}

UIKit.Colors = {
	Background = Color3.fromRGB(12, 10, 22),
	Panel = Color3.fromRGB(24, 20, 40),
	PanelLight = Color3.fromRGB(40, 33, 66),
	Accent = Color3.fromRGB(165, 105, 255),
	AccentDark = Color3.fromRGB(78, 40, 140),
	Gold = Color3.fromRGB(255, 205, 110),
	GoldDark = Color3.fromRGB(170, 105, 30),
	Text = Color3.fromRGB(244, 240, 255),
	SubText = Color3.fromRGB(170, 162, 200),
	Danger = Color3.fromRGB(255, 95, 110),
	Success = Color3.fromRGB(110, 230, 150),
}

UIKit.Fonts = {
	Title = Enum.Font.Fantasy,
	Bold = Enum.Font.GothamBold,
	Black = Enum.Font.GothamBlack,
	Body = Enum.Font.GothamMedium,
}

UIKit.Settings = {
	Sound = true,
	Shake = true,
	Hints = true,
	UIScale = 1,
}

-------------------------------------------------------------------------------
-- Création
-------------------------------------------------------------------------------
function UIKit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			(inst :: any)[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	inst.Parent = parent
	return inst
end

function UIKit.corner(parent: Instance, radius: number?): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

function UIKit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color or UIKit.Colors.Accent,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UIKit.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

function UIKit.padding(parent: Instance, px: number)
	return UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function UIKit.tween(inst: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

function UIKit.label(props: { [string]: any }, maxTextSize: number?): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = UIKit.Fonts.Body,
		TextColor3 = UIKit.Colors.Text,
		TextScaled = true,
		TextWrapped = true,
	}
	for key, value in pairs(props) do
		defaults[key] = value
	end
	local label = UIKit.new("TextLabel", defaults)
	UIKit.new("UITextSizeConstraint", { MaxTextSize = maxTextSize or 32, MinTextSize = 8, Parent = label })
	return label
end

-------------------------------------------------------------------------------
-- Fondu d'un groupe d'éléments, sans CanvasGroup (qui rend en basse
-- résolution : dégradés en bandes et à-coups pendant l'animation).
-- Les éléments marqués de l'attribut NoFade (et leurs enfants) sont ignorés.
-------------------------------------------------------------------------------
local FADE_PROPS = {
	{ "GuiObject", "BackgroundTransparency" },
	{ "TextLabel", "TextTransparency" },
	{ "TextLabel", "TextStrokeTransparency" },
	{ "TextButton", "TextTransparency" },
	{ "TextBox", "TextTransparency" },
	{ "ImageLabel", "ImageTransparency" },
	{ "ImageButton", "ImageTransparency" },
	-- Vues 3D (portraits des PNJ du guide...) : sinon elles restent affichées
	-- pendant tout le fondu de fermeture.
	{ "ViewportFrame", "ImageTransparency" },
	{ "ScrollingFrame", "ScrollBarImageTransparency" },
	{ "UIStroke", "Transparency" },
}

local function isExcluded(inst: Instance, root: Instance): boolean
	local current: Instance? = inst
	while current and current ~= root do
		if current:GetAttribute("NoFade") then
			return true
		end
		current = current.Parent
	end
	return false
end

function UIKit.fade(root: Instance, visible: boolean, duration: number, style: Enum.EasingStyle?): Tween?
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local last: Tween? = nil
	local items = root:GetDescendants()
	table.insert(items, root)
	for _, inst in ipairs(items) do
		if not isExcluded(inst, root) then
			for _, entry in ipairs(FADE_PROPS) do
				if inst:IsA(entry[1]) then
					local prop = entry[2]
					local key = "FadeBase_" .. prop
					local base = inst:GetAttribute(key)
					if base == nil then
						base = (inst :: any)[prop]
						inst:SetAttribute(key, base)
					end
					if visible then
						(inst :: any)[prop] = 1
					end
					local tween = TweenService:Create(inst, info, { [prop] = visible and base or 1 })
					tween:Play()
					last = tween
				end
			end
		end
	end
	return last
end

-------------------------------------------------------------------------------
-- Sons : effets définis dans Configs/SoundData (Id vide = muet)
-------------------------------------------------------------------------------
local soundCache: { [string]: Sound } = {}
local SoundData = require(game:GetService("ReplicatedStorage"):WaitForChild("Configs"):WaitForChild("SoundData"))

function UIKit.playSound(name: string, volume: number?, pitch: number?)
	if not UIKit.Settings.Sound then
		return
	end
	local data = SoundData.Effects[name]
	if data == nil or data.Id == "" then
		return
	end
	local id = data.Id
	local sound = soundCache[name]
	if sound == nil then
		sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Parent = SoundService
		soundCache[name] = sound
	end
	sound.Volume = (volume or 0.5) * ((data.Volume or 0.5) / 0.5)
	sound.PlaybackSpeed = (pitch or 1) * (data.Pitch or 1)
	-- Plusieurs sons identiques peuvent se chevaucher (impacts en rafale).
	if sound.IsPlaying then
		local copy = sound:Clone()
		copy.Parent = SoundService
		copy.Ended:Once(function()
			copy:Destroy()
		end)
		copy:Play()
	else
		sound:Play()
	end
end

-------------------------------------------------------------------------------
-- Mise à l'échelle (PC, tablette, téléphone, TV)
-------------------------------------------------------------------------------
local scales: { UIScale } = {}
UIKit.CurrentScale = 1

local function computeScale(): number
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1366, 768)
	local base = math.min(viewport.X / 1366, viewport.Y / 768)
	-- Écran bas (téléphone en paysage) : on privilégie la hauteur, sinon tout
	-- devient minuscule.
	if viewport.Y < 500 then
		base = math.min(viewport.X / 1200, viewport.Y / 650)
	end
	-- Sur console, l'écran est loin : on grossit un peu.
	if GuiService:IsTenFootInterface() then
		base *= 1.15
	end
	return math.clamp(base, 0.5, 1.4) * UIKit.Settings.UIScale
end

function UIKit.refreshScale()
	UIKit.CurrentScale = computeScale()
	for _, scale in ipairs(scales) do
		scale.Scale = UIKit.CurrentScale
	end
end

function UIKit.scaled(inst: Instance): UIScale
	local scale = UIKit.new("UIScale", { Scale = UIKit.CurrentScale, Parent = inst })
	table.insert(scales, scale)
	return scale
end

local function watchCamera(camera: Camera?)
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(UIKit.refreshScale)
	end
	UIKit.refreshScale()
end
watchCamera(workspace.CurrentCamera)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	watchCamera(workspace.CurrentCamera)
end)

-------------------------------------------------------------------------------
-- Plateforme
-------------------------------------------------------------------------------
function UIKit.inputMode(): string
	local last = UserInputService:GetLastInputType()
	if last.Name:match("^Gamepad") then
		return "Gamepad"
	elseif last == Enum.UserInputType.Touch then
		return "Touch"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Keyboard"
end

-- Vrai si l'objet peut recevoir le focus : affiché (lui et tous ses parents)
-- dans une interface active du joueur. Sinon Roblox avertit « Setting
-- GuiService.SelectedObject to invalid GuiObject ».
function UIKit.canSelect(obj: Instance?): boolean
	if not (obj and obj:IsA("GuiObject") and obj.Selectable) then
		return false
	end
	local node: Instance? = obj
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		elseif node:IsA("LayerCollector") then
			-- Écran du joueur, ou interface posée dans le monde (livre 3D).
			return node.Enabled and (node:IsDescendantOf(game:GetService("Players").LocalPlayer) or node:IsDescendantOf(workspace))
		end
		node = node.Parent
	end
	return false
end

-- Donne le focus manette si c'est possible ; sinon réessaie brièvement
-- (le bouton est souvent rendu visible juste après l'appel).
function UIKit.select(obj: GuiObject?)
	if obj == nil then
		GuiService.SelectedObject = nil
		return
	end
	if UIKit.canSelect(obj) then
		GuiService.SelectedObject = obj
		return
	end
	task.delay(0.15, function()
		if UIKit.canSelect(obj) then
			GuiService.SelectedObject = obj
		end
	end)
end

function UIKit.focus(button: GuiObject?)
	if UIKit.inputMode() == "Gamepad" then
		UIKit.select(button)
	end
end

-------------------------------------------------------------------------------
-- Bouton moderne (effet verre, barre d'accent, icône, reflet animé)
-------------------------------------------------------------------------------
type ButtonOptions = {
	Text: string,
	Icon: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Style: string?, -- "Primary" | "Gold" | "Ghost" | "Danger"
	Align: string?, -- "Center" | "Left"
	Parent: Instance?,
	LayoutOrder: number?,
	TextSize: number?,
	Callback: (() -> ())?,
}

-- { haut, bas, contour, texte, accent, transparence du fond }
local STYLES = {
	Primary = { Color3.fromRGB(88, 52, 150), Color3.fromRGB(36, 18, 72), Color3.fromRGB(232, 190, 105), Color3.fromRGB(255, 244, 220), Color3.fromRGB(232, 190, 105), 0 },
	Gold = { Color3.fromRGB(150, 92, 40), Color3.fromRGB(78, 42, 16), Color3.fromRGB(240, 200, 115), Color3.fromRGB(255, 244, 220), Color3.fromRGB(240, 200, 115), 0 },
	Ghost = { Color3.fromRGB(52, 48, 58), Color3.fromRGB(20, 18, 24), Color3.fromRGB(225, 185, 100), Color3.fromRGB(255, 244, 220), Color3.fromRGB(225, 185, 100), 0.03 },
	Danger = { Color3.fromRGB(150, 42, 38), Color3.fromRGB(70, 16, 16), Color3.fromRGB(240, 195, 110), Color3.fromRGB(255, 240, 220), Color3.fromRGB(240, 195, 110), 0 },
}

function UIKit.button(options: ButtonOptions): TextButton
	local style = STYLES[options.Style or "Ghost"] or STYLES.Ghost
	local left = options.Align == "Left"

	-- Le TextButton reste transparent : son texte est recopié dans un label
	-- séparé pour ne pas être teinté par le dégradé du fond.
	local button = UIKit.new("TextButton", {
		Name = options.Text:gsub("%W", ""),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = options.Size or UDim2.fromOffset(300, 56),
		Position = options.Position or UDim2.new(),
		AnchorPoint = options.AnchorPoint or Vector2.zero,
		LayoutOrder = options.LayoutOrder or 0,
		Text = options.Text,
		TextTransparency = 1,
		Selectable = true,
		ClipsDescendants = false,
		Parent = options.Parent,
	})

	local bg = UIKit.new("Frame", {
		Name = "Background",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = style[6],
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Parent = button,
	})
	UIKit.corner(bg, 8)
	local gradient = UIKit.gradient(bg, style[1], style[2], 90)
	local stroke = UIKit.stroke(bg, style[3], 2.5, 0.1)

	-- Liseré intérieur doré, comme un cadre ouvragé.
	local inset = UIKit.new("Frame", {
		Name = "Inset",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		Parent = bg,
	})
	UIKit.corner(inset, 5)
	UIKit.stroke(inset, style[5], 1, 0.55)
	-- Équerres dorées dans les coins, comme des renforts de métal.
	for _, corner in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		local holder = UIKit.new("Frame", {
			Name = "Ornament",
			BackgroundTransparency = 1,
			AnchorPoint = corner,
			Position = UDim2.new(corner.X, corner.X == 0 and 2 or -2, corner.Y, corner.Y == 0 and 2 or -2),
			Size = UDim2.fromOffset(7, 7),
			ZIndex = 3,
			Parent = button,
		})
		UIKit.new("Frame", { BackgroundColor3 = style[3], BorderSizePixel = 0, AnchorPoint = Vector2.new(corner.X, corner.Y),
			Position = UDim2.fromScale(corner.X, corner.Y), Size = UDim2.new(1, 0, 0, 2), ZIndex = 3, Parent = holder })
		UIKit.new("Frame", { BackgroundColor3 = style[3], BorderSizePixel = 0, AnchorPoint = Vector2.new(corner.X, corner.Y),
			Position = UDim2.fromScale(corner.X, corner.Y), Size = UDim2.new(0, 2, 1, 0), ZIndex = 3, Parent = holder })
	end

	-- Reflet supérieur (effet verre).
	local gloss = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.9,
		Size = UDim2.fromScale(1, 0.48),
		BorderSizePixel = 0,
		Parent = bg,
	})
	UIKit.corner(gloss, 14)
	UIKit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.2, 1), Parent = gloss })

	-- Balayage lumineux au survol.
	local sweep = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.75,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.3, 0.5),
		Size = UDim2.new(0, 40, 2, 0),
		Rotation = 20,
		BorderSizePixel = 0,
		Parent = bg,
	})
	UIKit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = sweep,
	})

	local textOffset = 0
	if options.Icon then
		local iconSize = math.min(36, (options.TextSize or 24) + 8)
		UIKit.new("TextLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 16, 0.5, 0),
			Size = UDim2.fromOffset(iconSize, iconSize),
			Text = options.Icon,
			TextScaled = true,
			Font = UIKit.Fonts.Black,
			TextColor3 = style[4],
			ZIndex = 2,
			Parent = button,
		})
		textOffset = iconSize + 12
	end

	local label = UIKit.new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, (left and 18 or 12) + textOffset, 0.5, 0),
		Size = UDim2.new(1, -(left and 30 or 24) - textOffset, 0.56, 0),
		Text = options.Text,
		TextColor3 = style[4],
		Font = UIKit.Fonts.Black,
		TextScaled = true,
		TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center,
		ZIndex = 2,
		Parent = button,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = options.TextSize or 22, Parent = label })
	UIKit.new("UIStroke", { Color = Color3.fromRGB(35, 18, 8), Thickness = 1.5, Transparency = 0.25, Parent = label })
	button:GetPropertyChangedSignal("Text"):Connect(function()
		label.Text = button.Text
	end)

	local scale = UIKit.new("UIScale", { Parent = button })

	-- Cadre de sélection manette.
	local selection = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	UIKit.corner(selection, 8)
	UIKit.stroke(selection, UIKit.Colors.Gold, 3, 0)
	button.SelectionImageObject = selection

	local hovered = false
	local function highlight(on: boolean)
		if hovered == on then
			return
		end
		hovered = on
		UIKit.tween(scale, 0.18, { Scale = on and 1.04 or 1 }, Enum.EasingStyle.Back)
		UIKit.tween(stroke, 0.18, { Transparency = on and 0 or 0.1, Thickness = on and 3 or 2.5 })
		UIKit.tween(gradient, 0.25, { Offset = on and Vector2.new(0, -0.15) or Vector2.zero })
		if on then
			sweep.Position = UDim2.fromScale(-0.3, 0.5)
			UIKit.tween(sweep, 0.55, { Position = UDim2.fromScale(1.3, 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		end
	end
	button.MouseEnter:Connect(function()
		highlight(true)
	end)
	button.MouseLeave:Connect(function()
		highlight(false)
	end)
	button.SelectionGained:Connect(function()
		highlight(true)
	end)
	button.SelectionLost:Connect(function()
		highlight(false)
	end)
	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, 0.08, { Scale = 0.96 })
	end)
	button.Activated:Connect(function()
		UIKit.tween(scale, 0.2, { Scale = hovered and 1.04 or 1 }, Enum.EasingStyle.Back)
		UIKit.playSound("Click", 0.4)
		if options.Callback then
			options.Callback()
		end
	end)

	return button
end

-- Grise un bouton (ex. pas assez de gemmes, onglet inactif).
function UIKit.setDimmed(button: GuiObject, dimmed: boolean)
	local label = button:FindFirstChild("Label")
	local bg = button:FindFirstChild("Background")
	if label then
		label.TextTransparency = dimmed and 0.45 or 0
	end
	if bg then
		local base = bg:GetAttribute("BaseTransparency")
		if base == nil then
			base = bg.BackgroundTransparency
			bg:SetAttribute("BaseTransparency", base)
		end
		bg.BackgroundTransparency = dimmed and math.max(base, 0.45) or base
	end
end

-------------------------------------------------------------------------------
-- Panneau modal
-------------------------------------------------------------------------------
export type Panel = {
	Root: Frame,
	Window: Frame,
	Content: Frame,
	CloseButton: TextButton,
	IsOpen: boolean,
	Open: (self: Panel) -> (),
	Close: (self: Panel) -> (),
	OnClose: (() -> ())?,
}

function UIKit.panel(parent: Instance, title: string): Panel
	local root = UIKit.new("Frame", {
		Name = title:gsub("%W", "") .. "Panel",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 10,
		Active = true,
		Parent = parent,
	})

	local window = UIKit.new("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1100, 720),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = root,
	})
	UIKit.corner(window, 10)
	UIKit.gradient(window, Color3.fromRGB(52, 32, 82), Color3.fromRGB(16, 10, 30), 90)
	UIKit.stroke(window, Color3.fromRGB(225, 180, 95), 3, 0)
	local windowScale = UIKit.new("UIScale", { Parent = window })
	-- Mise en page adaptative : la fenêtre garde une taille « virtuelle » d'au
	-- moins 900 × 560 (le contenu est pensé pour ça) et elle est réduite pour
	-- tenir à l'écran. Sur téléphone, tout reste lisible et proportionné.
	local fit = 1
	local function layout()
		local camera = workspace.CurrentCamera
		local v = camera and camera.ViewportSize or Vector2.new(1366, 768)
		if v.X < 2 or v.Y < 2 then
			return
		end
		fit = math.clamp(math.min(v.X * 0.94 / 900, v.Y * 0.92 / 560), 0.45, 1)
		window.Size = UDim2.fromOffset(math.min(1100, v.X * 0.94 / fit), math.min(720, v.Y * 0.92 / fit))
		windowScale.Scale = fit
	end
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
	-- Liseré intérieur doré.
	local inset = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), Parent = window })
	UIKit.corner(inset, 6)
	UIKit.stroke(inset, Color3.fromRGB(225, 180, 95), 1.2, 0.5)
	-- Joyaux rouges aux quatre coins.
	for _, c in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		local jewel = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(c.X, c.X == 0 and 6 or -6, c.Y, c.Y == 0 and 6 or -6),
			Size = UDim2.fromOffset(14, 14),
			Rotation = 45,
			BackgroundColor3 = Color3.fromRGB(200, 35, 60),
			ZIndex = 4,
			Parent = window,
		})
		UIKit.stroke(jewel, Color3.fromRGB(240, 200, 115), 2, 0)
	end
	-- Ciel étoilé et constellations discrètes.
	local starRandom = Random.new(#title)
	for _ = 1, 40 do
		local s = starRandom:NextInteger(1, 3)
		UIKit.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 235, 200),
			BackgroundTransparency = starRandom:NextNumber(0.3, 0.8),
			BorderSizePixel = 0,
			Position = UDim2.fromScale(starRandom:NextNumber(0.02, 0.98), starRandom:NextNumber(0.03, 0.97)),
			Size = UDim2.fromOffset(s, s),
			Parent = window,
		})
	end
	for _, corner in ipairs({ Vector2.new(0.06, 0.85), Vector2.new(0.92, 0.2) }) do
		local last = corner
		for _ = 1, 4 do
			local nextPoint = last + Vector2.new(starRandom:NextNumber(-0.05, 0.05), starRandom:NextNumber(-0.08, 0.08))
			local mid = (last + nextPoint) / 2
			local delta = nextPoint - last
			UIKit.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.fromRGB(230, 200, 140),
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(mid.X, mid.Y),
				Size = UDim2.new(0, math.max(8, delta.Magnitude * 900), 0, 1),
				Rotation = math.deg(math.atan2(delta.Y * 0.6, delta.X)),
				Parent = window,
			})
			last = nextPoint
		end
	end

	UIKit.label({
		Name = "Title",
		Text = title,
		Font = UIKit.Fonts.Title,
		TextColor3 = Color3.fromRGB(255, 220, 140),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(1, -180, 0, 50),
		Position = UDim2.new(0.5, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = window,
	}, 44)
	UIKit.new("UIStroke", { Color = Color3.fromRGB(60, 25, 10), Thickness = 2, Parent = window:FindFirstChild("Title") })

	local content = UIKit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 72),
		Size = UDim2.new(1, -40, 1, -90),
		Parent = window,
	})

	local panel = {
		Root = root,
		Window = window,
		Content = content,
		IsOpen = false,
	} :: any
	layout()

	panel.CloseButton = UIKit.button({
		Text = "X",
		Style = "Danger",
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		TextSize = 22,
		Parent = window,
		Callback = function()
			panel:Close()
		end,
	})

	function panel:Open()
		if self.IsOpen then
			return
		end
		self.IsOpen = true
		root.Visible = true
		layout()
		windowScale.Scale = fit * 0.85
		UIKit.tween(root, 0.2, { BackgroundTransparency = 0.45 })
		UIKit.tween(windowScale, 0.3, { Scale = fit }, Enum.EasingStyle.Back)
		UIKit.focus(self.CloseButton)
	end

	function panel:Close()
		if not self.IsOpen then
			return
		end
		self.IsOpen = false
		UIKit.tween(root, 0.15, { BackgroundTransparency = 1 })
		local tween = UIKit.tween(windowScale, 0.15, { Scale = fit * 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween.Completed:Once(function()
			if not self.IsOpen then
				root.Visible = false
			end
		end)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
		if self.OnClose then
			self.OnClose()
		end
	end

	return panel
end

return UIKit
