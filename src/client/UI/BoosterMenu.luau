-- Ouverture d'un booster (depuis l'autel) : l'écran s'assombrit, le booster
-- 3D est au centre et se tourne à la souris ou au doigt. « Ouvrir » joue
-- l'animation du fichier Claude Design ; une fois les cartes en éventail,
-- on clique sur chacune pour la retourner (comme dans le HTML) et la
-- créature obtenue s'affiche au-dessus de la carte.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local BoosterFX = require(script.Parent:WaitForChild("BoosterFX"))

local BoosterMenu = {}

local OPEN_DUR, T_TEAR, T_FAN, FLIP_DUR = 5.6, 1.05, 4.2, 1.1
local GOLD = Color3.fromRGB(232, 197, 108)
-- Couleurs des cartes du modèle : 1 = Nature, 2 = Feu, 3 = Glace.
local CARD_COLORS = { Color3.fromRGB(111, 211, 106), Color3.fromRGB(255, 138, 52), Color3.fromRGB(127, 211, 255) }

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

	-- Bas d'écran : invitation à toucher le booster (cliquable aussi), prix inclus.
	local hint = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1), Visible = false, Parent = root })
	local openButton = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -44),
		Size = UDim2.fromOffset(380, 48), BackgroundColor3 = INK, BackgroundTransparency = 0.2, ZIndex = 35, Parent = root })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = openButton })
	UIKit.stroke(openButton, GOLD, 1.5, 0.2)
	UIKit.label({ Text = 'TOUCHE LE BOOSTER POUR L\'OUVRIR   <font color="#82D7FF">' .. CardsData.Economy.BoosterPrice .. ' ◆</font>', RichText = true,
		Font = UIKit.Fonts.Black, TextColor3 = CREAM, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), ZIndex = 36, Parent = openButton }, 16)
	local cueScale = UIKit.new("UIScale", { Parent = openButton })
	local endRow = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(600, 60), Visible = false, ZIndex = 34, Parent = root })
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 16),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = endRow })
	local again = UIKit.button({ Text = "ENCORE UN  ·  " .. CardsData.Economy.BoosterPrice .. " ◆", Style = "Gold", Size = UDim2.fromOffset(280, 58), TextSize = 20,
		LayoutOrder = 1, Parent = endRow, Callback = function() end })
	UIKit.button({ Text = "TERMINER", Style = "Ghost", Size = UDim2.fromOffset(200, 58), TextSize = 20, LayoutOrder = 2, Parent = endRow, Callback = function()
		menu:Close()
	end })
	for _, inst in ipairs({ header, closeButton, oddsPanel, wallet, openButton, endRow }) do
		UIKit.scaled(inst)
	end
	-- Panneaux latéraux et halo visibles seulement avant l'ouverture.
	local function setIdleChrome(visible: boolean)
		for _, inst in ipairs({ oddsPanel, wallet, hint }) do
			inst.Visible = visible
		end
		UIKit.tween(halo, 0.4, { BackgroundTransparency = visible and 0 or 1 })
	end
	RunService.RenderStepped:Connect(function()
		if menu.IsOpen then
			haloScale.Scale = 1 + math.sin(os.clock() * 1.4) * 0.03
			cueScale.Scale = 1 + math.sin(os.clock() * 3) * 0.025
		end
	end)

	function menu:SetProfile(profile)
		if profile then
			coinsLabel.Text = tostring(profile.Coins or 0) .. " ◆"
		end
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
		local dist = h * (3.4 + pullBack * 1.1) * zoom
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

	---------------------------------------------------------------------------
	-- Retournement des cartes 3D (comme dans le HTML)
	---------------------------------------------------------------------------
	local results, flipped, labels = {}, {}, {}
	local canFlip = false
	local function cardPoint(i: number): Vector3?
		local p = rig and rig:bonePosition("carte_" .. i .. "_mesh")
		if not p then
			return nil
		end
		-- Centre de la carte : les os sont à sa base.
		return p + Vector3.new(0, size.Y * 0.32, 0)
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
	local function flipCard(i: number)
		if not canFlip or flipped[i] or not results[i] then
			return
		end
		flipped[i] = true
		local result = results[i]
		local card = result.card
		local rarity = CardsData.RarityById[card.Rarity] or CardsData.Rarities[1]
		local start = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local p = math.min((os.clock() - start) / FLIP_DUR, 1)
			if rig then
				rig:flip(i, p)
			end
			if p >= 1 then
				conn:Disconnect()
			end
		end)
		UIKit.playSound("Click", 0.5, 1.2)
		task.delay(FLIP_DUR * 0.55, function()
			local point = cardPoint(i)
			local pos = point and project(point) or viewport.AbsoluteSize / 2
			local color = CARD_COLORS[i] or GOLD
			flashAt(pos, color, 260)
			ring(pos, color, 320)
			sparks(pos, { color, Color3.new(1, 1, 1), rarity.Color }, 40, 180)
			UIKit.playSound("Reveal", 0.6, 0.8 + rarity.Order * 0.1)
			if rarity.Order >= 4 then
				callbacks.Shake(rarity.Order == 5 and 0.7 or 0.4, 0.4)
			end
			-- Étiquette de la créature obtenue, au-dessus de la carte.
			local tag = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(220, 74), BackgroundColor3 = Color3.fromRGB(14, 10, 26),
				BackgroundTransparency = 0.1, ZIndex = 37, Parent = fxLayer })
			UIKit.corner(tag, 10)
			UIKit.stroke(tag, rarity.Color, 2, 0)
			UIKit.label({ Text = string.upper(card.Name), Font = Enum.Font.Merriweather, TextColor3 = Color3.fromRGB(255, 244, 220), Position = UDim2.fromOffset(8, 4),
				Size = UDim2.new(1, -16, 0, 28), ZIndex = 38, Parent = tag }, 22)
			UIKit.label({ Text = rarity.Label .. "  ·  " .. ((CardsData.Elements[card.Element] or {}).Label or card.Element), Font = UIKit.Fonts.Bold,
				TextColor3 = rarity.Color, Position = UDim2.fromOffset(8, 32), Size = UDim2.new(1, -16, 0, 18), ZIndex = 38, Parent = tag }, 15)
			UIKit.label({ Text = result.isNew and "NOUVELLE CRÉATURE !" or string.format("Doublon  ·  +%d ◆", result.refund or 0), Font = UIKit.Fonts.Black,
				TextColor3 = result.isNew and GOLD or Color3.fromRGB(180, 170, 200), Position = UDim2.fromOffset(8, 52), Size = UDim2.new(1, -16, 0, 16), ZIndex = 38,
				Parent = tag }, 13)
			local scale = UIKit.new("UIScale", { Scale = 0.3, Parent = tag })
			UIKit.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			labels[i] = tag
			if remaining() == 0 then
				endRow.Visible = true
				UIKit.focus(again)
			end
		end)
	end
	-- Les étiquettes suivent les cartes à l'écran.
	RunService.RenderStepped:Connect(function()
		if not menu.IsOpen then
			return
		end
		for i, tag in pairs(labels) do
			local point = cardPoint(i)
			local pos = point and project(point + Vector3.new(0, size.Y * 0.45, 0))
			if pos then
				tag.Position = UDim2.fromOffset(pos.X, pos.Y)
			end
		end
	end)

	-- Souris / doigt : glisser pour tourner, clic sur une carte pour la retourner.
	local last, downAt = nil, nil
	viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, last, downAt = false, input.Position, input.Position
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
			-- Clic sur le booster encore fermé : on l'ouvre.
			if menu.IsOpen and not busy and not canFlip and #results == 0 and downAt then
				task.spawn(menu.OpenPack)
				downAt = nil
				return
			end
			-- Un clic bref (sans glisser) sur une carte la retourne.
			if canFlip and downAt and (Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(downAt.X, downAt.Y)).Magnitude < 8 then
				-- Position de la souris (sous la barre Roblox) ramenée au repère de l'interface plein écran.
				local click = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset() - viewport.AbsolutePosition
				local best, bestDist = nil, viewport.AbsoluteSize.Y * 0.14
				for i = 1, #results do
					local point = cardPoint(i)
					local pos = point and project(point)
					if pos and not flipped[i] and (pos - click).Magnitude < bestDist then
						best, bestDist = i, (pos - click).Magnitude
					end
				end
				if best then
					flipCard(best)
				end
			end
			downAt = nil
		end
	end)
	-- Manette / clavier : le bouton d'action retourne la carte suivante.
	UserInputService.InputBegan:Connect(function(input, processed)
		if not menu.IsOpen or processed then
			return
		end
		if not canFlip then
			if not busy and #results == 0 and (input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return) then
				task.spawn(menu.OpenPack)
			end
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return then
			for i = 1, #results do
				if not flipped[i] then
					flipCard(i)
					break
				end
			end
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
		for _, tag in pairs(labels) do
			tag:Destroy()
		end
		labels, results, flipped = {}, {}, {}
		canFlip = false
		endRow.Visible = false
		openButton.Visible = true
		closeButton.Visible = true
		setIdleChrome(true)
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
		openButton.Visible = false
		-- Plus de croix une fois le booster ouvert : « TERMINER » prend le relais.
		closeButton.Visible = false
		setIdleChrome(false)
		if not (buildModel() and rig) then
			busy = false
			return
		end
		-- Retour de face, puis animation « Ouverture » du fichier.
		local startYaw = yaw
		local targetYaw = FRONT + math.round((startYaw - FRONT) / (math.pi * 2)) * math.pi * 2
		local turnStart = os.clock()
		while os.clock() - turnStart < 0.4 do
			yaw = startYaw + (targetYaw - startYaw) * ((os.clock() - turnStart) / 0.4)
			task.wait()
		end
		yaw, pitch = targetYaw, 0.06
		setCardsVisible(true)
		local start = os.clock()
		local tore, fanned = false, false
		while menu.IsOpen do
			local t = os.clock() - start
			rig:pose(math.min(t, OPEN_DUR))
			local k = math.clamp((t - 0.9) / 1.0, 0, 1)
			pullBack = k * k * (3 - 2 * k)
			if not tore and t >= T_TEAR then
				tore = true
				local top = rig:bonePosition("haut")
				local pos = top and project(top) or viewport.AbsoluteSize / 2
				flashAt(pos, Color3.fromRGB(255, 225, 160), 300)
				sparks(pos, { Color3.fromRGB(255, 217, 115), Color3.fromRGB(255, 153, 64), Color3.fromRGB(128, 217, 255), Color3.fromRGB(217, 179, 255) }, 50, 220)
				UIKit.playSound("Reveal", 0.5, 1.4)
			end
			if not fanned and t >= T_FAN - 0.25 then
				fanned = true
				local point = cardPoint(1)
				local pos = point and project(point) or viewport.AbsoluteSize / 2
				flashAt(pos, Color3.fromRGB(255, 240, 200), 520)
				sparks(pos, { Color3.fromRGB(255, 217, 115), Color3.fromRGB(128, 217, 255), Color3.fromRGB(217, 179, 255) }, 60, 360)
				callbacks.Shake(0.3, 0.3)
			end
			if t >= OPEN_DUR then
				break
			end
			task.wait()
		end
		canFlip = true
		busy = false
	end
	menu.OpenPack = open
	openButton.Activated:Connect(function()
		task.spawn(open)
	end)
	again.Activated:Connect(function()
		resetView()
		task.spawn(open)
	end)

	function menu:Open()
		if self.IsOpen then
			return
		end
		self.IsOpen = true
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
		-- Les cartes déjà tirées sont acquises : on révèle tout si on ferme tôt.
		UIKit.tween(root, 0.25, { BackgroundTransparency = 1 })
		UIKit.tween(vignette, 0.25, { BackgroundTransparency = 1 })
		UIKit.tween(halo, 0.25, { BackgroundTransparency = 1 })
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
