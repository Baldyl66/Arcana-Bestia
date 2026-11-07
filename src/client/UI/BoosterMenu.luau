-- Ouverture d'un booster (depuis l'autel) : le booster 3D est au centre et
-- se tourne à la souris ou au doigt. « Ouvrir » : le sachet tremble et se
-- déchire, puis les vraies cartes en jaillissent, face cachée. Un clic les
-- retourne une à une (suspense et éclat selon la rareté), « Tout révéler »
-- les retourne toutes ; à la fin, résumé et « Ouvrir un autre ».
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local BoosterFX = require(script.Parent:WaitForChild("BoosterFX"))
local CardView = require(script.Parent:WaitForChild("CardView"))

local BoosterMenu = {}

local T_TEAR = 1.05 -- instant où le sachet se déchire (animation du modèle)
local GOLD = Color3.fromRGB(232, 197, 108)

type Callbacks = {
	Open: () -> any?,
	Shake: (number, number) -> (),
}

function BoosterMenu.new(parent: Instance, callbacks: Callbacks)
	local menu = { IsOpen = false } :: any
	local busy = false

	local root = UIKit.new("Frame", {
		Name = "BoosterMenu",
		BackgroundColor3 = Color3.fromRGB(4, 3, 10),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Active = true,
		ZIndex = 30,
		Parent = parent,
	})
	menu.Root = root

	local viewport = UIKit.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(150, 145, 180),
		LightColor = Color3.fromRGB(255, 245, 230),
		LightDirection = Vector3.new(-0.4, -0.7, -1),
		Active = true,
		ZIndex = 31,
		Parent = root,
	})
	local world = UIKit.new("WorldModel", { Parent = viewport })
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	-- Couche des effets 2D (éclairs, éclats, étiquettes) au-dessus de la 3D.
	local fxLayer = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 33, Parent = root })

	local INK = Color3.fromRGB(14, 10, 24)
	local CREAM = Color3.fromRGB(255, 244, 220)
	local MUTED = Color3.fromRGB(175, 165, 200)

	-- Halo lumineux derrière le booster (respire doucement) et vignette.
	local halo = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromScale(0.62, 0.62),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 30, Parent = root })
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = halo })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = halo })
	UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 215, 130), Color3.fromRGB(120, 70, 220)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.78), NumberSequenceKeypoint.new(0.5, 0.93), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = 90, Parent = halo })
	local haloScale = UIKit.new("UIScale", { Parent = halo })
	local vignette = UIKit.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30, Parent = root })
	UIKit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.25, 1), NumberSequenceKeypoint.new(0.75, 1),
		NumberSequenceKeypoint.new(1, 0.2) }), Rotation = 90, Parent = vignette })

	-- En-tête : surtitre, titre doré, filet avec losange.
	local header = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(640, 124), ZIndex = 34, Parent = root })
	UIKit.label({ Text = "A U T E L   A R C A N I Q U E", Font = UIKit.Fonts.Bold, TextColor3 = MUTED, Size = UDim2.new(1, 0, 0, 18), ZIndex = 34, Parent = header }, 14)
	local title = UIKit.label({ Text = "BOOSTER ARCANA", Font = Enum.Font.Merriweather, TextColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 56), ZIndex = 34, Parent = header }, 50)
	UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 240, 190), Color3.fromRGB(225, 165, 70)), Rotation = 90, Parent = title })
	UIKit.new("UIStroke", { Color = Color3.fromRGB(40, 15, 5), Thickness = 2, Parent = title })
	for _, sx in ipairs({ -1, 1 }) do
		local line = UIKit.new("Frame", { AnchorPoint = Vector2.new(sx < 0 and 1 or 0, 0.5), Position = UDim2.new(0.5, sx * 12, 0, 90), Size = UDim2.fromOffset(150, 2),
			BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 34, Parent = header })
		UIKit.new("UIGradient", { Transparency = NumberSequence.new(sx < 0 and 1 or 0, sx < 0 and 0 or 1), Parent = line })
	end
	UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(10, 10), Rotation = 45,
		BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 34, Parent = header })
	UIKit.label({ Text = "3 créatures par booster", Font = UIKit.Fonts.Bold, TextColor3 = MUTED, Position = UDim2.fromOffset(0, 102),
		Size = UDim2.new(1, 0, 0, 20), ZIndex = 34, Parent = header }, 16)

	-- Bouton fermer : rond, discret.
	local closeButton = UIKit.new("TextButton", { Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -28, 0, 44), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = INK, BackgroundTransparency = 0.2,
		ZIndex = 35, Parent = root })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = closeButton })
	UIKit.stroke(closeButton, GOLD, 1.5, 0.3)
	for _, r in ipairs({ 45, -45 }) do
		local bar = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 3), Rotation = r,
			BackgroundColor3 = CREAM, BorderSizePixel = 0, ZIndex = 36, Parent = closeButton })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = bar })
	end
	closeButton.MouseEnter:Connect(function()
		UIKit.tween(closeButton, 0.15, { BackgroundColor3 = Color3.fromRGB(120, 30, 40) })
	end)
	closeButton.MouseLeave:Connect(function()
		UIKit.tween(closeButton, 0.15, { BackgroundColor3 = INK })
	end)
	closeButton.Activated:Connect(function()
		menu:Close()
	end)

	-- Panneau des chances (droite) : une ligne par rareté, avec sa barre.
	local oddsPanel = UIKit.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0.5, 0), Size = UDim2.fromOffset(250, 236),
		BackgroundColor3 = INK, BackgroundTransparency = 0.25, ZIndex = 34, Parent = root })
	UIKit.corner(oddsPanel, 14)
	UIKit.stroke(oddsPanel, GOLD, 1.5, 0.45)
	UIKit.label({ Text = "CHANCES DE TIRAGE", Font = UIKit.Fonts.Black, TextColor3 = GOLD, Position = UDim2.fromOffset(18, 14), Size = UDim2.new(1, -36, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35, Parent = oddsPanel }, 14)
	local maxWeight = 0
	for _, rarity in ipairs(CardsData.Rarities) do
		maxWeight = math.max(maxWeight, rarity.Weight)
	end
	for i, rarity in ipairs(CardsData.Rarities) do
		local y = 44 + (i - 1) * 37
		UIKit.new("Frame", { Position = UDim2.fromOffset(18, y + 4), Size = UDim2.fromOffset(10, 10), Rotation = 45, BackgroundColor3 = rarity.Color,
			BorderSizePixel = 0, ZIndex = 35, Parent = oddsPanel })
		UIKit.label({ Text = rarity.Label, Font = UIKit.Fonts.Bold, TextColor3 = CREAM, Position = UDim2.fromOffset(36, y), Size = UDim2.fromOffset(130, 18),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35, Parent = oddsPanel }, 15)
		UIKit.label({ Text = string.format("%g %%", rarity.Weight), Font = UIKit.Fonts.Black, TextColor3 = rarity.Color, AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, y), Size = UDim2.fromOffset(70, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 35, Parent = oddsPanel }, 15)
		local track = UIKit.new("Frame", { Position = UDim2.fromOffset(36, y + 22), Size = UDim2.new(1, -54, 0, 4), BackgroundColor3 = Color3.fromRGB(45, 38, 66),
			BorderSizePixel = 0, ZIndex = 35, Parent = oddsPanel })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = track })
		local fill = UIKit.new("Frame", { Size = UDim2.fromScale(math.max(rarity.Weight / maxWeight, 0.03), 1), BackgroundColor3 = rarity.Color, BorderSizePixel = 0,
			ZIndex = 36, Parent = track })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = fill })
	end

	-- Solde (gauche) : pastille avec une gemme taillée et le montant en grand.
	local wallet = UIKit.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 40, 0.5, 0), Size = UDim2.fromOffset(230, 72),
		BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 34, Parent = root })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = wallet })
	UIKit.gradient(wallet, Color3.fromRGB(40, 30, 70), INK, 90)
	UIKit.stroke(wallet, GOLD, 2, 0.2)
	local gemIcon = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 38, 0.5, 0), Size = UDim2.fromOffset(34, 34), Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 35, Parent = wallet })
	UIKit.corner(gemIcon, 6)
	UIKit.gradient(gemIcon, Color3.fromRGB(190, 240, 255), Color3.fromRGB(40, 110, 230), 45)
	UIKit.stroke(gemIcon, Color3.fromRGB(235, 248, 255), 2, 0.1)
	local shine = UIKit.new("Frame", { Position = UDim2.fromScale(0.15, 0.15), Size = UDim2.fromScale(0.3, 0.3), BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35, ZIndex = 36, Parent = gemIcon })
	UIKit.corner(shine, 3)
	UIKit.label({ Text = "GEMMES", Font = UIKit.Fonts.Black, TextColor3 = MUTED, Position = UDim2.fromOffset(72, 12), Size = UDim2.new(1, -90, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35, Parent = wallet }, 12)
	local coinsLabel = UIKit.label({ Text = "—", Font = UIKit.Fonts.Black, TextColor3 = CREAM, Position = UDim2.fromOffset(72, 26), Size = UDim2.new(1, -90, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35, Parent = wallet }, 32)
	UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 250, 235), Color3.fromRGB(190, 225, 255)), Rotation = 90, Parent = coinsLabel })



	-- Bouton « pilule » : doré lumineux (action principale) ou sombre (secondaire),
	-- avec pastille de prix facultative. Garde les enfants « Label » et
	-- « Background » pour que UIKit.setDimmed fonctionne.
	local function fancyButton(o): TextButton
		local gold = o.Style == "Gold"
		local button = UIKit.new("TextButton", { Name = o.Name or "Fancy", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Selectable = true,
			Size = o.Size, Position = o.Position or UDim2.new(), AnchorPoint = o.AnchorPoint or Vector2.zero, LayoutOrder = o.LayoutOrder or 0, ZIndex = 36,
			Parent = o.Parent })
		local scale = UIKit.new("UIScale", { Parent = button })
		-- Halo qui respire derrière le bouton doré.
		local glow
		if gold then
			glow = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 26, 1, 26),
				BackgroundColor3 = Color3.fromRGB(255, 200, 90), BackgroundTransparency = 0.8, ZIndex = 35, Parent = button })
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
		end
		local bg = UIKit.new("Frame", { Name = "Background", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true,
			ZIndex = 36, Parent = button })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = bg })
		if gold then
			UIKit.gradient(bg, Color3.fromRGB(255, 222, 140), Color3.fromRGB(190, 112, 34), 90)
			UIKit.stroke(bg, Color3.fromRGB(255, 240, 200), 2, 0.1)
		else
			UIKit.gradient(bg, Color3.fromRGB(46, 34, 72), Color3.fromRGB(16, 11, 28), 90)
			UIKit.stroke(bg, GOLD, 1.5, 0.25)
		end
		-- Reflet supérieur.
		local gloss = UIKit.new("Frame", { Position = UDim2.fromScale(0.04, 0.06), Size = UDim2.fromScale(0.92, 0.42), BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = gold and 0.55 or 0.88, ZIndex = 37, Parent = bg })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = gloss })
		UIKit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.2, 1), Parent = gloss })
		-- Éclat qui traverse le bouton.
		local sweep = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.2, 0.5), Size = UDim2.new(0, 46, 2, 0), Rotation = 20,
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = gold and 0.45 or 0.8, BorderSizePixel = 0, ZIndex = 38, Parent = bg })
		UIKit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }),
			Parent = sweep })
		local priceWidth = o.Price and 96 or 0
		local text = UIKit.label({ Name = "Label", Text = o.Text, Font = UIKit.Fonts.Black, TextColor3 = gold and Color3.fromRGB(70, 32, 8) or CREAM,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 22, 0.5, 1), Size = UDim2.new(1, -44 - priceWidth, 0.5, 0), ZIndex = 39, Parent = button },
			o.TextSize or 22)
		if not gold then
			UIKit.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.5, Parent = text })
		end
		-- Pastille de prix : gemme dessinée + montant.
		if o.Price then
			local pill = UIKit.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, priceWidth, 1, -16),
				BackgroundColor3 = Color3.fromRGB(40, 20, 8), BackgroundTransparency = 0.15, ZIndex = 39, Parent = button })
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = pill })
			local gemIcon = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 20, 0.5, 0), Size = UDim2.fromOffset(14, 14), Rotation = 45,
				BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 40, Parent = pill })
			UIKit.gradient(gemIcon, Color3.fromRGB(190, 240, 255), Color3.fromRGB(40, 120, 235), 45)
			UIKit.stroke(gemIcon, Color3.fromRGB(230, 248, 255), 1, 0.2)
			UIKit.label({ Text = tostring(o.Price), Font = UIKit.Fonts.Black, TextColor3 = Color3.fromRGB(200, 235, 255), TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -40, 1, 0), ZIndex = 40, Parent = pill }, 20)
		end
		local hovered = false
		local function hover(on: boolean)
			hovered = on
			UIKit.tween(scale, 0.18, { Scale = on and 1.05 or 1 }, Enum.EasingStyle.Back)
			if on then
				sweep.Position = UDim2.fromScale(-0.2, 0.5)
				UIKit.tween(sweep, 0.5, { Position = UDim2.fromScale(1.2, 0.5) }, Enum.EasingStyle.Quad)
			end
		end
		button.MouseEnter:Connect(function() hover(true) end)
		button.MouseLeave:Connect(function() hover(false) end)
		button.SelectionGained:Connect(function() hover(true) end)
		button.SelectionLost:Connect(function() hover(false) end)
		button.MouseButton1Down:Connect(function()
			UIKit.tween(scale, 0.08, { Scale = 0.95 })
		end)
		button.Activated:Connect(function()
			UIKit.tween(scale, 0.2, { Scale = hovered and 1.05 or 1 }, Enum.EasingStyle.Back)
			UIKit.playSound("Click", 0.4)
		end)
		-- Le bouton doré respire et son éclat passe régulièrement.
		if gold then
			task.spawn(function()
				while button.Parent do
					if button.Visible and not hovered then
						sweep.Position = UDim2.fromScale(-0.2, 0.5)
						UIKit.tween(sweep, 0.7, { Position = UDim2.fromScale(1.2, 0.5) }, Enum.EasingStyle.Quad)
					end
					for _ = 1, 30 do
						glow.BackgroundTransparency = 0.78 + math.sin(os.clock() * 3) * 0.08
						task.wait(0.08)
					end
				end
			end)
		end
		return button
	end

	-- Bas d'écran : un seul bandeau (mis à l'échelle) qui porte les boutons.
	local PRICE = CardsData.Economy.BoosterPrice
	local bottom = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(900, 130), ZIndex = 35, Parent = root })
	-- Avant l'ouverture : gros bouton doré + rappel qu'on peut toucher le booster.
	local hint = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 35, Parent = bottom })
	local openButton = fancyButton({ Text = "OUVRIR LE BOOSTER", Style = "Gold", Price = PRICE, Size = UDim2.fromOffset(400, 66), TextSize = 24,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20), Parent = hint })
	local hintLabel = UIKit.label({ Text = "", Font = UIKit.Fonts.Bold, TextColor3 = MUTED, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 94), Size = UDim2.fromOffset(400, 20), ZIndex = 35, Parent = hint }, 15)
	-- Pendant la révélation : « tout révéler ».
	local revealRow = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 35, Parent = bottom })
	UIKit.label({ Text = "Clique sur une carte pour la retourner", Font = UIKit.Fonts.Bold, TextColor3 = CREAM, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(600, 24), ZIndex = 35, Parent = revealRow }, 20)
	local revealAll = fancyButton({ Text = "TOUT RÉVÉLER", Style = "Ghost", Size = UDim2.fromOffset(260, 58), TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Parent = revealRow })
	-- À la fin : résumé + « ouvrir un autre » / « terminer ».
	local endRow = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 35, Parent = bottom })
	local summary = UIKit.label({ Text = "", RichText = true, Font = UIKit.Fonts.Bold, TextColor3 = CREAM, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(700, 24), ZIndex = 35, Parent = endRow }, 20)
	local buttons = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(720, 64), ZIndex = 35, Parent = endRow })
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 18),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = buttons })
	local again = fancyButton({ Text = "OUVRIR UN AUTRE", Style = "Gold", Price = PRICE, Size = UDim2.fromOffset(380, 64), TextSize = 22,
		LayoutOrder = 1, Parent = buttons })
	local done = fancyButton({ Text = "TERMINER", Style = "Ghost", Size = UDim2.fromOffset(210, 64), TextSize = 21, LayoutOrder = 2, Parent = buttons })
	local poorLabel = UIKit.label({ Text = "", Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(255, 120, 120), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.fromOffset(600, 20), ZIndex = 35, Parent = endRow }, 16)
	for _, inst in ipairs({ header, closeButton, oddsPanel, wallet, bottom }) do
		UIKit.scaled(inst)
	end

	-- Scène des cartes révélées (2D, au-dessus du booster 3D).
	local cardStage = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(960, 520), ZIndex = 36, Parent = root })
	UIKit.scaled(cardStage)
	local screenFlash = UIKit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 45, Parent = root })
	-- Panneaux latéraux et halo visibles seulement avant l'ouverture.
	local function setIdleChrome(visible: boolean)
		for _, inst in ipairs({ oddsPanel, wallet, hint }) do
			inst.Visible = visible
		end
		UIKit.tween(halo, 0.4, { BackgroundTransparency = visible and 0 or 1 })
	end
	---------------------------------------------------------------------------
	-- Modèle 3D et caméra
	---------------------------------------------------------------------------
	local model, rig, center, size, cardParts = nil, nil, Vector3.zero, Vector3.one, {}
	local dragging = false
	local FRONT = math.pi -- face avant du sachet vers la caméra
	local yaw, pitch, zoom, pullBack = FRONT, 0.06, 1, 0
	local function buildModel(): boolean
		if model then
			return true
		end
		local template = BoosterFX.template()
		if not template then
			return false
		end
		model = BoosterFX.prepare(template)
		model:PivotTo(CFrame.new())
		model.Parent = world
		rig = BoosterFX.Rig and BoosterFX.Rig.new(model)
		FRONT = (rig and rig.SZ == 1) and 0 or math.pi
		yaw = FRONT
		center, size = BoosterFX.visibleBounds(model, true)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and string.sub(string.lower(d.Name), 1, 5) == "carte" then
				cardParts[d] = d.Transparency
			end
		end
		return true
	end
	local function setCardsVisible(visible: boolean)
		for part, transparency in pairs(cardParts) do
			part.Transparency = visible and transparency or 1
		end
	end
	RunService.RenderStepped:Connect(function(dt)
		if not (menu.IsOpen and model) then
			return
		end
		-- Relâché, le booster revient doucement de face.
		if not dragging then
			local target = FRONT + math.round((yaw - FRONT) / (math.pi * 2)) * math.pi * 2
			yaw += (target - yaw) * math.clamp(dt * 7, 0, 1)
			pitch += (0.06 - pitch) * math.clamp(dt * 7, 0, 1)
		end
		model:PivotTo(CFrame.Angles(0, yaw, 0))
		local h = math.max(size.Y, 1)
		-- 4.3 : le booster reste bien entre le titre et le bouton.
		local dist = h * (4.3 + pullBack * 1.1) * zoom
		-- Visée légèrement au-dessus du centre : le booster est bien placé
		-- entre le titre et le bouton.
		local target = center + Vector3.new(0, h * (0.1 + 0.4 * pullBack), 0)
		cam.CFrame = CFrame.lookAt(target + Vector3.new(0, math.sin(pitch) * dist, math.cos(pitch) * dist), target)
	end)

	-- Projection d'un point 3D sur l'écran de la vue (pour les clics et étiquettes).
	local function project(point: Vector3): Vector2?
		local p = cam.CFrame:PointToObjectSpace(point)
		if p.Z >= 0 then
			return nil
		end
		local sizePx = viewport.AbsoluteSize
		local tanY = math.tan(math.rad(cam.FieldOfView / 2))
		local aspect = sizePx.X / math.max(sizePx.Y, 1)
		local x = p.X / (-p.Z * tanY * aspect)
		local y = -p.Y / (-p.Z * tanY)
		return Vector2.new((x + 1) / 2 * sizePx.X, (y + 1) / 2 * sizePx.Y)
	end

	---------------------------------------------------------------------------
	-- Effets 2D
	---------------------------------------------------------------------------
	local function flashAt(pos: Vector2, color: Color3, sizePx: number)
		local f = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(pos.X, pos.Y), Size = UDim2.fromOffset(sizePx * 0.4, sizePx * 0.4),
			BackgroundColor3 = color, BackgroundTransparency = 0.05, ZIndex = 35, Parent = fxLayer })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = f })
		UIKit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.6), NumberSequenceKeypoint.new(1, 1) }),
			Parent = f })
		UIKit.tween(f, 0.5, { Size = UDim2.fromOffset(sizePx, sizePx), BackgroundTransparency = 1 })
		task.delay(0.55, function()
			f:Destroy()
		end)
	end
	local function sparks(pos: Vector2, colors: { Color3 }, count: number, spread: number)
		for i = 1, count do
			local a = math.random() * math.pi * 2
			local d = (0.4 + math.random() * 0.6) * spread
			local s = math.random(4, 9)
			local spark = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(pos.X, pos.Y), Size = UDim2.fromOffset(s, s), Rotation = 45,
				BackgroundColor3 = colors[(i % #colors) + 1], BorderSizePixel = 0, ZIndex = 36, Parent = fxLayer })
			UIKit.tween(spark, 0.7 + math.random() * 0.5, { Position = UDim2.fromOffset(pos.X + math.cos(a) * d, pos.Y + math.sin(a) * d - spread * 0.3),
				BackgroundTransparency = 1, Rotation = 45 + math.random(-90, 90) }, Enum.EasingStyle.Quad)
			task.delay(1.3, function()
				spark:Destroy()
			end)
		end
	end
	local function ring(pos: Vector2, color: Color3, sizePx: number)
		local r = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(pos.X, pos.Y), Size = UDim2.fromOffset(sizePx * 0.15, sizePx * 0.15),
			BackgroundTransparency = 1, ZIndex = 35, Parent = fxLayer })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = r })
		local stroke = UIKit.stroke(r, color, 5, 0)
		UIKit.tween(r, 0.6, { Size = UDim2.fromOffset(sizePx, sizePx) }, Enum.EasingStyle.Quad)
		UIKit.tween(stroke, 0.6, { Transparency = 1 })
		task.delay(0.65, function()
			r:Destroy()
		end)
	end

	local coins = 0
	function menu:SetProfile(profile)
		if profile then
			coins = profile.Coins or 0
			coinsLabel.Text = tostring(coins) .. " ◆"
		end
	end

	RunService.RenderStepped:Connect(function()
		if menu.IsOpen then
			haloScale.Scale = 1 + math.sin(os.clock() * 1.4) * 0.03
		end
	end)

	---------------------------------------------------------------------------
	-- Cartes révélées : elles jaillissent du booster, dos visible, et se
	-- retournent au clic avec un effet selon la rareté.
	---------------------------------------------------------------------------
	local results, flipped, slots = {}, {}, {}
	local canFlip = false
	local CARD_W, CARD_H, GAP = 230, 336, 300

	-- Sans contrainte de ratio, la carte peut s'aplatir pendant le retournement.
	local function freeRatio(view: Instance)
		local c = view:FindFirstChildOfClass("UIAspectRatioConstraint")
		if c then
			c:Destroy()
		end
	end
	local function remaining(): number
		local n = 0
		for i = 1, #results do
			if not flipped[i] then
				n += 1
			end
		end
		return n
	end
	local function centerOf(gui: GuiObject): Vector2
		return gui.AbsolutePosition + gui.AbsoluteSize / 2 - fxLayer.AbsolutePosition
	end

	-- Rayons tournants derrière les cartes Rares et mieux.
	RunService.RenderStepped:Connect(function(dt)
		for _, s in pairs(slots) do
			if s.Rays.Visible then
				s.Rays.Rotation += dt * s.RaySpeed
			end
		end
	end)

	local showEnd
	local function makeSlot(i: number, count: number)
		local x = CARD_W * 0 + 480 + (i - (count + 1) / 2) * GAP
		local slot = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(480, 300),
			Size = UDim2.fromOffset(CARD_W, CARD_H), ZIndex = 37, Parent = cardStage })
		local pop = UIKit.new("UIScale", { Scale = 0.15, Parent = slot })
		-- Halo de rareté (désactivé : plus d'aura derrière les cartes).
		local glow = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.9, 1.5),
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 37, Parent = slot })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
		UIKit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(0.7, 0.55), NumberSequenceKeypoint.new(1, 1) }), Parent = glow })
		local rays = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1, Visible = false, ZIndex = 37, Parent = slot })
		for k = 1, 10 do
			local ray = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(34, 640),
				Rotation = k * 18, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 37, Parent = rays })
			UIKit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.5),
				NumberSequenceKeypoint.new(1, 1) }), Parent = ray })
		end
		-- Support du retournement (sa largeur passe à 0 puis revient).
		local flip = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1, ZIndex = 38, Parent = slot })
		local back = CardView.back({ Detailed = true, Size = UDim2.fromScale(1, 1), Parent = flip })
		freeRatio(back)
		-- Liseré qui pulse sur les cartes encore cachées.
		local pulse = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.04, 1.03),
			BackgroundTransparency = 1, ZIndex = 39, Parent = slot })
		UIKit.corner(pulse, 12)
		local pulseStroke = UIKit.stroke(pulse, GOLD, 3, 0.4)
		-- Zone cliquable.
		local hit = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50,
			Selectable = true, Parent = slot })
		local hover = UIKit.new("UIScale", { Parent = flip })
		hit.MouseEnter:Connect(function()
			if not flipped[i] then
				UIKit.tween(hover, 0.15, { Scale = 1.05 }, Enum.EasingStyle.Back)
			end
		end)
		hit.MouseLeave:Connect(function()
			UIKit.tween(hover, 0.15, { Scale = 1 })
		end)
		-- Étiquette sous la carte.
		local tag = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 14), Size = UDim2.fromOffset(270, 66),
			BackgroundColor3 = Color3.fromRGB(14, 10, 26), BackgroundTransparency = 0.1, Visible = false, ZIndex = 40, Parent = slot })
		UIKit.corner(tag, 10)
		local tagStroke = UIKit.stroke(tag, GOLD, 2, 0)
		local tagName = UIKit.label({ Text = "", Font = Enum.Font.Merriweather, TextColor3 = CREAM, Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 26),
			ZIndex = 41, Parent = tag }, 22)
		local tagInfo = UIKit.label({ Text = "", RichText = true, Font = UIKit.Fonts.Bold, TextColor3 = CREAM, Position = UDim2.fromOffset(8, 34),
			Size = UDim2.new(1, -16, 0, 24), ZIndex = 41, Parent = tag }, 16)
		local s = { Slot = slot, Pop = pop, Glow = glow, Rays = rays, RaySpeed = 20, Flip = flip, Back = back, Pulse = pulse, PulseStroke = pulseStroke,
			Hit = hit, Tag = tag, TagStroke = tagStroke, TagName = tagName, TagInfo = tagInfo, X = x }
		slots[i] = s
		return s
	end

	local function flipCard(i: number)
		local s = slots[i]
		local result = results[i]
		if not canFlip or flipped[i] or not (s and result) then
			return
		end
		flipped[i] = true
		local card = result.card
		local rarity = CardsData.RarityById[card.Rarity] or CardsData.Rarities[1]
		local element = CardsData.Elements[card.Element] or CardsData.Elements.Feu
		s.Pulse.Visible = false
		-- Suspense : plus la carte est rare, plus elle tremble et s'illumine avant.
		if rarity.Order >= 3 then
			s.Glow.BackgroundColor3 = rarity.Color
			UIKit.tween(s.Glow, 0.4, { BackgroundTransparency = 0.5 })
			UIKit.playSound("Charge", 0.5, 0.9 + rarity.Order * 0.1)
			for k = 1, 4 + rarity.Order * 2 do
				s.Flip.Rotation = (k % 2 == 0 and 1 or -1) * (1 + k * 0.4)
				task.wait(0.045)
			end
			s.Flip.Rotation = 0
		end
		UIKit.playSound("Swoosh", 0.5, 1.2)
		UIKit.tween(s.Flip, 0.14, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
		if not menu.IsOpen then
			return
		end
		s.Back:Destroy()
		local front = CardView.create(card, { Detailed = true, Count = result.count, Size = UDim2.fromScale(1, 1), Parent = s.Flip })
		freeRatio(front)
		UIKit.tween(s.Flip, 0.26, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)
		-- Éclat à la couleur de la rareté.
		local pos = centerOf(s.Slot)
		s.Glow.BackgroundColor3 = rarity.Color
		s.Glow.BackgroundTransparency = 0.05
		UIKit.tween(s.Glow, 0.8, { BackgroundTransparency = rarity.Order >= 2 and 0.4 or 0.75 })
		flashAt(pos, rarity.Color:Lerp(Color3.new(1, 1, 1), 0.4), 300 + rarity.Order * 60)
		ring(pos, rarity.Color, 320 + rarity.Order * 80)
		sparks(pos, { rarity.Color, element.Color, Color3.new(1, 1, 1) }, 20 + rarity.Order * 15, 160 + rarity.Order * 30)
		if rarity.Order >= 3 then
			for _, ray in ipairs(s.Rays:GetChildren()) do
				if ray:IsA("Frame") then
					ray.BackgroundColor3 = rarity.Color
				end
			end
			-- Rayons et halo derrière les cartes retirés (demande du joueur).
			s.RaySpeed = 15 + rarity.Order * 10
		end
		if rarity.Order >= 4 then
			screenFlash.BackgroundColor3 = rarity.Color
			screenFlash.BackgroundTransparency = rarity.Order == 5 and 0.1 or 0.4
			UIKit.tween(screenFlash, 0.8, { BackgroundTransparency = 1 })
			callbacks.Shake(rarity.Order == 5 and 0.9 or 0.5, 0.5)
		end
		UIKit.playSound("Reveal", 0.6, 0.8 + rarity.Order * 0.1)
		s.Pop.Scale = 1.12
		UIKit.tween(s.Pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		-- Étiquette : nom, rareté, nouveau ou doublon.
		s.TagStroke.Color = rarity.Color
		s.TagName.Text = string.upper(card.Name)
		s.TagInfo.Text = string.format('<font color="#%s">%s</font> · <font color="#%s">%s</font>   %s', rarity.Color:ToHex(), rarity.Label, element.Color:ToHex(),
			element.Label, result.isNew and '<font color="#FFD778">★ NOUVEAU !</font>' or string.format('<font color="#B4AAC8">doublon +%d ◆</font>', result.refund or 0))
		-- (Étiquette sous la carte désactivée : la carte suffit, le résumé dit le reste.)
		if remaining() == 0 then
			task.delay(0.4, showEnd)
		end
	end

	showEnd = function()
		if not menu.IsOpen or remaining() > 0 then
			return
		end
		local newCount, best = 0, CardsData.Rarities[1]
		for _, r in ipairs(results) do
			if r.isNew then
				newCount += 1
			end
			local rar = CardsData.RarityById[r.card.Rarity]
			if rar and rar.Order > best.Order then
				best = rar
			end
		end
		summary.Text = string.format('%d créatures · <font color="#FFD778">%d nouvelle%s</font> · meilleure : <font color="#%s">%s</font>', #results, newCount,
			newCount > 1 and "s" or "", best.Color:ToHex(), best.Label)
		revealRow.Visible = false
		endRow.Visible = true
		local poor = coins < PRICE
		UIKit.setDimmed(again, poor)
		poorLabel.Text = poor and string.format("Il te faut %d ◆ (tu en as %d)", PRICE, coins) or ""
		UIKit.focus(poor and done or again)
	end

	local function revealEverything()
		for i = 1, #results do
			if not flipped[i] and menu.IsOpen then
				task.spawn(flipCard, i)
				task.wait(0.3)
			end
		end
	end

	local function clearSlots()
		for _, s in pairs(slots) do
			s.Slot:Destroy()
		end
		slots, results, flipped = {}, {}, {}
		canFlip = false
	end

	-- Les cartes sortent du booster et se placent en éventail.
	local function dealCards()
		local count = #results
		for i = 1, count do
			local s = makeSlot(i, count)
			s.Hit.Activated:Connect(function()
				task.spawn(flipCard, i)
			end)
			s.Slot.Rotation = 0
			UIKit.tween(s.Slot, 0.55, { Position = UDim2.fromOffset(s.X, 250) }, Enum.EasingStyle.Back)
			UIKit.tween(s.Pop, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
			UIKit.playSound("Swoosh", 0.4, 1 + i * 0.1)
			task.wait(0.14)
		end
		task.wait(0.4)
		canFlip = true
		revealRow.Visible = true
		if slots[1] then
			UIKit.focus(slots[1].Hit)
		end
	end

	-- Liseré des cartes cachées qui respire.
	RunService.RenderStepped:Connect(function()
		if not canFlip then
			return
		end
		local t = os.clock()
		for i, s in pairs(slots) do
			if not flipped[i] then
				s.PulseStroke.Transparency = 0.35 + math.sin(t * 4 + i) * 0.3
			end
		end
	end)

	---------------------------------------------------------------------------
	-- Souris / doigt : glisser pour tourner le booster, toucher pour l'ouvrir.
	---------------------------------------------------------------------------
	local last, downAt = nil, nil
	viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, last, downAt = true, input.Position, input.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) and last then
			local delta = input.Position - last
			last = input.Position
			yaw += delta.X * 0.012
			pitch = math.clamp(pitch + delta.Y * 0.006, -0.6, 0.8)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and menu.IsOpen then
			zoom = math.clamp(zoom - input.Position.Z * 0.08, 0.6, 1.6)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 and menu.IsOpen and not busy then
			yaw += input.Position.X * 0.05
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			-- Un toucher bref (sans glisser) sur le booster fermé l'ouvre.
			if menu.IsOpen and not busy and #results == 0 and downAt
				and (Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(downAt.X, downAt.Y)).Magnitude < 8 then
				task.spawn(menu.OpenPack)
			end
			downAt = nil
		end
	end)
	-- Manette / clavier : A / Espace ouvre puis retourne la carte suivante ; X révèle tout.
	UserInputService.InputBegan:Connect(function(input, processed)
		if not menu.IsOpen or processed then
			return
		end
		local action = input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return
		if action and not busy and #results == 0 then
			task.spawn(menu.OpenPack)
		elseif action and canFlip then
			for i = 1, #results do
				if not flipped[i] then
					task.spawn(flipCard, i)
					break
				end
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonX and canFlip then
			task.spawn(revealEverything)
		end
	end)

	---------------------------------------------------------------------------
	-- Ouverture
	---------------------------------------------------------------------------
	local function resetView()
		pullBack, zoom = 0, 1
		yaw, pitch = FRONT, 0.06
		if rig then
			rig:rest(0)
		end
		setCardsVisible(false)
		clearSlots()
		viewport.ImageTransparency = 0
		hint.Visible = true
		revealRow.Visible = false
		endRow.Visible = false
		poorLabel.Text = ""
		closeButton.Visible = true
		setIdleChrome(true)
		hintLabel.Text = coins < PRICE and string.format("Il te faut %d ◆ (tu en as %d)", PRICE, coins) or ""
		UIKit.setDimmed(openButton, coins < PRICE)
	end

	local function open()
		if busy then
			return
		end
		busy = true
		local result = callbacks.Open()
		if not result then
			busy = false
			return
		end
		results = result.results or {}
		hint.Visible = false
		-- Plus de croix une fois le booster ouvert : « TERMINER » prend le relais.
		closeButton.Visible = false
		setIdleChrome(false)
		if buildModel() and rig then
			-- Retour de face, puis le sachet se déchire.
			local startYaw = yaw
			local targetYaw = FRONT + math.round((startYaw - FRONT) / (math.pi * 2)) * math.pi * 2
			local turnStart = os.clock()
			while os.clock() - turnStart < 0.3 do
				yaw = startYaw + (targetYaw - startYaw) * ((os.clock() - turnStart) / 0.3)
				task.wait()
			end
			yaw, pitch = targetYaw, 0.06
			UIKit.playSound("Charge", 0.5, 1)
			local start = os.clock()
			local tore = false
			local stop = T_TEAR + 0.45
			while menu.IsOpen do
				local t = os.clock() - start
				rig:pose(math.min(t, stop))
				-- Le sachet tremble de plus en plus avant de se déchirer.
				if t < T_TEAR then
					yaw = targetYaw + math.sin(t * 60) * 0.04 * (t / T_TEAR)
				else
					yaw = targetYaw
				end
				if not tore and t >= T_TEAR then
					tore = true
					local top = rig:bonePosition("haut")
					local pos = top and project(top) or viewport.AbsoluteSize / 2
					flashAt(pos, Color3.fromRGB(255, 225, 160), 360)
					sparks(pos, { Color3.fromRGB(255, 217, 115), Color3.fromRGB(255, 153, 64), Color3.fromRGB(128, 217, 255), Color3.fromRGB(217, 179, 255) }, 60, 260)
					UIKit.playSound("Reveal", 0.5, 1.4)
					callbacks.Shake(0.3, 0.3)
				end
				if t >= stop then
					break
				end
				task.wait()
			end
			-- Le booster s'efface, les cartes prennent le relais.
			UIKit.tween(viewport, 0.3, { ImageTransparency = 1 })
			flashAt(viewport.AbsoluteSize / 2, Color3.fromRGB(255, 240, 200), 600)
		end
		if menu.IsOpen then
			dealCards()
		end
		busy = false
	end
	menu.OpenPack = open
	openButton.Activated:Connect(function()
		if coins < PRICE then
			callbacks.Shake(0.1, 0.15)
			return
		end
		task.spawn(open)
	end)
	revealAll.Activated:Connect(function()
		if canFlip then
			task.spawn(revealEverything)
		end
	end)
	again.Activated:Connect(function()
		if busy then
			return
		end
		if coins < PRICE then
			poorLabel.Text = string.format("Pas assez de gemmes : il te faut %d ◆ (tu en as %d)", PRICE, coins)
			callbacks.Shake(0.1, 0.15)
			return
		end
		resetView()
		task.spawn(open)
	end)
	done.Activated:Connect(function()
		menu:Close()
	end)

	-- Personnage immobile pendant l'ouverture (rétabli à la fermeture).
	local Freeze = require(script.Parent:WaitForChild("Freeze"))
	local function freezePlayer(on: boolean)
		if on then
			Freeze.hold("Booster")
		else
			Freeze.release("Booster")
		end
	end

	function menu:Open()
		if self.IsOpen then
			return
		end
		self.IsOpen = true
		freezePlayer(true)
		buildModel()
		resetView()
		root.Visible = true
		root.BackgroundTransparency = 1
		UIKit.tween(root, 0.3, { BackgroundTransparency = 0.2 })
		UIKit.tween(vignette, 0.3, { BackgroundTransparency = 0 })
		viewport.ImageTransparency = 1
		UIKit.tween(viewport, 0.4, { ImageTransparency = 0 })
		UIKit.focus(openButton)
	end

	function menu:Close()
		if not self.IsOpen then
			return
		end
		self.IsOpen = false
		freezePlayer(false)
		UIKit.tween(root, 0.25, { BackgroundTransparency = 1 })
		UIKit.tween(vignette, 0.25, { BackgroundTransparency = 1 })
		UIKit.tween(halo, 0.25, { BackgroundTransparency = 1 })
		for _, s in pairs(slots) do
			s.Slot.Visible = false
		end
		UIKit.tween(viewport, 0.2, { ImageTransparency = 1 }).Completed:Once(function()
			if not self.IsOpen then
				root.Visible = false
				resetView()
			end
		end)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
		if self.OnClose then
			self.OnClose()
		end
	end
	return menu
end

return BoosterMenu
