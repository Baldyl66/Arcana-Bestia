-- Panneaux modaux : Collection (bestiaire), Paramètres, Aide & crédits.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local CardView = require(script.Parent:WaitForChild("CardView"))
local CardDetail = require(script.Parent:WaitForChild("CardDetail"))

local Panels = {}

local GOLD = Color3.fromRGB(232, 197, 108)
local CREAM = Color3.fromRGB(255, 244, 220)
local MUTED = Color3.fromRGB(185, 172, 210)
local INK = Color3.fromRGB(16, 11, 28)
local CARD_BG = Color3.fromRGB(30, 20, 50)

-- Petits outils de mise en forme communs aux panneaux.
local function box(parent: Instance, props: { [string]: any }, radius: number?): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or CARD_BG
	props.BackgroundTransparency = props.BackgroundTransparency or 0.15
	props.BorderSizePixel = 0
	props.Parent = parent
	local f = UIKit.new("Frame", props)
	UIKit.corner(f, radius or 12)
	return f
end

local function text(parent: Instance, value: string, props: { [string]: any }, size: number): TextLabel
	props.Text = value
	props.RichText = true
	props.Font = props.Font or UIKit.Fonts.Bold
	props.TextColor3 = props.TextColor3 or CREAM
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.Parent = parent
	return UIKit.label(props, size)
end

local function diamond(parent: Instance, pos: UDim2, size: number, color: Color3): Frame
	local d = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(size, size), Rotation = 45,
		BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent })
	return d
end

-- Pastille arrondie cliquable (onglet, filtre). Renvoie le bouton et une fonction d'état.
local function pill(parent: Instance, label: string, color: Color3, width: number, order: number)
	local b = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(width, 40), LayoutOrder = order,
		BackgroundColor3 = INK, Selectable = true, Parent = parent })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = b })
	local stroke = UIKit.stroke(b, color, 1.5, 0.4)
	diamond(b, UDim2.new(0, 20, 0.5, 0), 9, color)
	local t = text(b, label, { Font = UIKit.Fonts.Black, Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -44, 1, 0) }, 15)
	local scale = UIKit.new("UIScale", { Parent = b })
	b.MouseEnter:Connect(function()
		UIKit.tween(scale, 0.12, { Scale = 1.05 }, Enum.EasingStyle.Back)
	end)
	b.MouseLeave:Connect(function()
		UIKit.tween(scale, 0.12, { Scale = 1 })
	end)
	local function setActive(on: boolean)
		UIKit.tween(b, 0.15, { BackgroundColor3 = on and color:Lerp(Color3.new(0, 0, 0), 0.45) or INK })
		stroke.Transparency = on and 0 or 0.4
		stroke.Color = on and GOLD or color
		t.TextColor3 = on and Color3.new(1, 1, 1) or MUTED
	end
	return b, setActive, t
end

-------------------------------------------------------------------------------
-- Collection (bestiaire)
-------------------------------------------------------------------------------
function Panels.collection(parent: Instance)
	local panel = UIKit.panel(parent, "BESTIAIRE")
	local content = panel.Content
	local filter = "Tout"
	local profile = nil

	-- Progression : x / 30, barre dégradée, pourcentage, puis deux compteurs.
	local head = box(content, { Size = UDim2.new(1, 0, 0, 64) })
	UIKit.stroke(head, GOLD, 1, 0.6)
	local progressText = text(head, "", { Font = UIKit.Fonts.Black, Position = UDim2.fromOffset(18, 8), Size = UDim2.new(0.45, 0, 0, 24) }, 20)
	local track = UIKit.new("Frame", { Position = UDim2.fromOffset(18, 38), Size = UDim2.new(0.45, 0, 0, 12), BackgroundColor3 = Color3.fromRGB(45, 32, 70),
		BorderSizePixel = 0, Parent = head })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = track })
	local fill = UIKit.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = fill })
	UIKit.gradient(fill, Color3.fromRGB(255, 220, 130), Color3.fromRGB(220, 130, 60), 0)
	local percent = text(head, "", { Font = UIKit.Fonts.Black, TextColor3 = GOLD, Position = UDim2.new(0.45, 30, 0, 0), Size = UDim2.fromOffset(80, 64) }, 24)
	local counters = {}
	for i, def in ipairs({ { "CARTES POSSÉDÉES", Color3.fromRGB(130, 215, 255) }, { "BOOSTERS OUVERTS", GOLD } }) do
		local c = box(head, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12 - (2 - i) * 190, 0.5, 0), Size = UDim2.fromOffset(176, 46),
			BackgroundColor3 = INK, BackgroundTransparency = 0.2 }, 10)
		text(c, def[1], { TextColor3 = MUTED, Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -24, 0, 14) }, 11)
		counters[i] = text(c, "0", { Font = UIKit.Fonts.Black, TextColor3 = def[2], Position = UDim2.fromOffset(12, 19), Size = UDim2.new(1, -24, 0, 24) }, 22)
	end

	-- Filtres : une pastille par rareté, avec le compte découvert / total.
	-- Les filtres se partagent toute la largeur (ils tiennent quelle que soit la fenêtre).
	local tabs = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 46), Parent = content })
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center, Parent = tabs })

	local grid = UIKit.new("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 130), Size = UDim2.new(1, 0, 1, -130),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 6,
		ScrollBarImageColor3 = GOLD, Selectable = false, Parent = content })
	UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 219), CellPadding = UDim2.fromOffset(16, 16), HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 12), Parent = grid })

	local tabStates = {}
	local tabLabels = {}
	local lastTile: GuiObject? = nil

	local function render()
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local owned = profile and profile.Cards or {}
		local discovered, totalCopies = 0, 0
		local perRarity, totalRarity = {}, {}
		for _, card in ipairs(CardsData.Cards) do
			totalRarity[card.Rarity] = (totalRarity[card.Rarity] or 0) + 1
			if (owned[card.Id] or 0) > 0 then
				perRarity[card.Rarity] = (perRarity[card.Rarity] or 0) + 1
				discovered += 1
				totalCopies += owned[card.Id]
			end
		end
		local ratio = discovered / #CardsData.Cards
		progressText.Text = string.format('<font color="#FFD778">%d</font> / %d créatures découvertes', discovered, #CardsData.Cards)
		UIKit.tween(fill, 0.6, { Size = UDim2.fromScale(math.max(ratio, 0.01), 1) }, Enum.EasingStyle.Quint)
		percent.Text = string.format("%d %%", math.floor(ratio * 100 + 0.5))
		counters[1].Text = tostring(totalCopies)
		counters[2].Text = tostring(profile and profile.BoostersOpened or 0)
		for id, label in pairs(tabLabels) do
			if id == "Tout" then
				label.Text = string.format("TOUT  %d/%d", discovered, #CardsData.Cards)
			else
				label.Text = string.format("%s  %d/%d", string.upper(CardsData.RarityById[id].Label), perRarity[id] or 0, totalRarity[id] or 0)
			end
		end
		for id, setActive in pairs(tabStates) do
			setActive(id == filter)
		end

		local sorted = table.clone(CardsData.Cards)
		table.sort(sorted, function(a, b)
			local ra, rb = CardsData.RarityById[a.Rarity].Order, CardsData.RarityById[b.Rarity].Order
			if ra ~= rb then
				return ra < rb
			end
			return a.Name < b.Name
		end)
		local first = nil
		for index, card in ipairs(sorted) do
			if filter == "Tout" or card.Rarity == filter then
				local count = owned[card.Id] or 0
				local tile = UIKit.new("TextButton", { Name = card.Id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, LayoutOrder = index,
					Parent = grid })
				local selection = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
				UIKit.corner(selection, 12)
				UIKit.stroke(selection, GOLD, 3, 0)
				tile.SelectionImageObject = selection
				local view = CardView.create(card, { Owned = count > 0, Count = count, Detailed = true, Size = UDim2.fromScale(1, 1), Parent = tile })
				view.Active = false
				local scale = UIKit.new("UIScale", { Parent = tile })
				local function hover(on: boolean)
					UIKit.tween(scale, 0.15, { Scale = on and 1.05 or 1 }, Enum.EasingStyle.Back)
				end
				tile.MouseEnter:Connect(function()
					hover(true)
				end)
				tile.MouseLeave:Connect(function()
					hover(false)
				end)
				tile.SelectionGained:Connect(function()
					hover(true)
				end)
				tile.SelectionLost:Connect(function()
					hover(false)
				end)
				tile.Activated:Connect(function()
					lastTile = tile
					UIKit.playSound("Click", 0.4)
					CardDetail.show(card, count > 0, profile)
				end)
				first = first or tile
			end
		end
		return first
	end

	local tabList = { { Id = "Tout", Color = GOLD } }
	for _, rarity in ipairs(CardsData.Rarities) do
		table.insert(tabList, { Id = rarity.Id, Color = rarity.Color })
	end
	for index, tab in ipairs(tabList) do
		local b, setActive, label = pill(tabs, "", tab.Color, 100, index)
		b.Size = UDim2.new(1 / #tabList, -7, 0, 40)
		tabStates[tab.Id] = setActive
		tabLabels[tab.Id] = label
		b.Activated:Connect(function()
			filter = tab.Id
			UIKit.playSound("Click", 0.4, 1.2)
			render()
		end)
	end

	local baseOpen = panel.Open
	function panel:Open()
		CardDetail.close()
		baseOpen(self)
		local first = render()
		UIKit.focus(first)
	end
	local baseClose = panel.Close
	function panel:Close()
		CardDetail.close()
		baseClose(self)
	end

	function panel:SetProfile(newProfile)
		profile = newProfile
		if self.IsOpen then
			render()
		end
	end

	function panel:HandleBack(): boolean
		if CardDetail.isOpen() then
			CardDetail.close()
			if lastTile then
				UIKit.focus(lastTile)
			end
			return true
		end
		return false
	end

	return panel
end

-------------------------------------------------------------------------------
-- Paramètres
-------------------------------------------------------------------------------
-- Médaillon d'icône dessinée (pas de caractères spéciaux : la police ne les a pas tous).
local function medallion(parent: Instance, kind: string): Frame
	local m = UIKit.new("Frame", { Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = INK, BorderSizePixel = 0,
		Parent = parent })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = m })
	UIKit.stroke(m, GOLD, 2, 0)
	local function bar(x: number, y: number, w: number, h: number, rot: number?)
		local b = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Rotation = rot or 0,
			BackgroundColor3 = GOLD, BorderSizePixel = 0, Parent = m })
		UIKit.corner(b, 2)
	end
	if kind == "sound" then
		-- Égaliseur : barres de hauteurs différentes.
		for i, h in ipairs({ 12, 22, 30, 18, 26 }) do
			bar(14 + (i - 1) * 7, 40 - h / 2, 4, h)
		end
	elseif kind == "shake" then
		-- Ondes de secousse.
		for i = 1, 3 do
			local r = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(i * 14, i * 14),
				BackgroundTransparency = 1, Parent = m })
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = r })
			UIKit.stroke(r, GOLD, 2, (i - 1) * 0.3)
		end
	else
		-- Deux cadres emboîtés (taille).
		for i, s in ipairs({ 30, 18 }) do
			local f = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(s, s),
				BackgroundTransparency = i == 2 and 0.3 or 1, BackgroundColor3 = GOLD, BorderSizePixel = 0, Parent = m })
			UIKit.corner(f, 3)
			UIKit.stroke(f, GOLD, 2, 0)
		end
	end
	return m
end

-- Interrupteur : rail arrondi et curseur qui glisse (doré quand activé).
local function toggle(parent: Instance, getValue: () -> boolean, onFlip: () -> ()): TextButton
	local b = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.fromOffset(110, 46), BackgroundColor3 = Color3.new(1, 1, 1), Selectable = true, Parent = parent })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = b })
	local gradient = UIKit.gradient(b, GOLD, GOLD, 90)
	UIKit.stroke(b, GOLD, 2, 0.2)
	local knob = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = CREAM, BorderSizePixel = 0,
		Parent = b })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = knob })
	local label = text(b, "", { Font = UIKit.Fonts.Black, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(0, 60, 1, 0) }, 15)
	local function refresh(animate: boolean)
		local on = getValue()
		local pos = on and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 23, 0.5, 0)
		if animate then
			UIKit.tween(knob, 0.2, { Position = pos }, Enum.EasingStyle.Back)
		else
			knob.Position = pos
		end
		gradient.Color = on and ColorSequence.new(Color3.fromRGB(255, 220, 130), Color3.fromRGB(200, 120, 40))
			or ColorSequence.new(Color3.fromRGB(70, 55, 95), Color3.fromRGB(35, 25, 55))
		label.Text = on and "OUI" or "NON"
		label.TextColor3 = on and Color3.fromRGB(70, 32, 8) or MUTED
		label.Position = on and UDim2.fromOffset(8, 0) or UDim2.new(1, -68, 0, 0)
	end
	b.Activated:Connect(function()
		onFlip()
		UIKit.playSound("Click", 0.4, 1.1)
		refresh(true)
	end)
	refresh(false)
	return b
end

function Panels.settings(parent: Instance, onChanged: () -> ())
	local panel = UIKit.panel(parent, "PARAMÈTRES")
	local list = UIKit.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = GOLD, Selectable = false, Parent = panel.Content })
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 10), Parent = list })

	local settings = UIKit.Settings
	local first = nil
	local function card(order: number, icon: string, title: string, description: string): Frame
		local f = box(list, { Size = UDim2.new(1, 0, 0, 88), LayoutOrder = order })
		UIKit.stroke(f, GOLD, 1, 0.65)
		medallion(f, icon)
		text(f, title, { Font = UIKit.Fonts.Black, Position = UDim2.fromOffset(90, 16), Size = UDim2.new(1, -460, 0, 28) }, 22)
		text(f, description, { Font = UIKit.Fonts.Body, TextColor3 = MUTED, TextWrapped = true, Position = UDim2.fromOffset(90, 46),
			Size = UDim2.new(1, -460, 0, 34), TextYAlignment = Enum.TextYAlignment.Top }, 15)
		return f
	end

	local sound = card(1, "sound", "Musique et sons", "Musique de fond et effets sonores.")
	first = toggle(sound, function()
		return settings.Sound
	end, function()
		settings.Sound = not settings.Sound
		require(script.Parent:WaitForChild("Music")).refresh()
		onChanged()
	end)
	local shake = card(2, "shake", "Secousses d'écran", "Tremblement de caméra lors des coups puissants et des cartes rares.")
	toggle(shake, function()
		return settings.Shake
	end, function()
		settings.Shake = not settings.Shake
		onChanged()
	end)

	-- Taille de l'interface : sélecteur à 4 choix.
	local sizeCard = card(3, "size", "Taille de l'interface", "Agrandis l'interface sur TV, réduis-la sur petit écran.")
	local group = UIKit.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0), Size = UDim2.fromOffset(340, 46),
		BackgroundColor3 = INK, BorderSizePixel = 0, Parent = sizeCard })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = group })
	UIKit.stroke(group, GOLD, 1.5, 0.3)
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), Parent = group })
	local scales = { 0.85, 1, 1.15, 1.3 }
	local options = {}
	local function refreshScales()
		for _, o in ipairs(options) do
			local on = math.abs(settings.UIScale - o.Value) < 0.01
			UIKit.tween(o.Button, 0.15, { BackgroundTransparency = on and 0 or 1 })
			o.Label.TextColor3 = on and Color3.fromRGB(70, 32, 8) or MUTED
		end
	end
	for i, value in ipairs(scales) do
		local b = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(78, 38), LayoutOrder = i, BackgroundColor3 = GOLD,
			BackgroundTransparency = 1, Selectable = true, Parent = group })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = b })
		local label = text(b, string.format("%d %%", math.floor(value * 100 + 0.5)), { Font = UIKit.Fonts.Black, TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1) }, 16)
		b.Activated:Connect(function()
			settings.UIScale = value
			UIKit.playSound("Click", 0.4, 1.1)
			refreshScales()
			onChanged()
		end)
		table.insert(options, { Button = b, Label = label, Value = value })
	end
	refreshScales()

	local baseOpen = panel.Open
	function panel:Open()
		baseOpen(self)
		refreshScales()
		UIKit.focus(first)
	end

	return panel
end

-------------------------------------------------------------------------------
-- Aide & crédits : onglets à gauche, page illustrée à droite.
-------------------------------------------------------------------------------
-- Touche de clavier / manette dessinée.
local function keycap(parent: Instance, label: string, order: number): Frame
	local width = math.max(34, #label * 10 + 18)
	local k = UIKit.new("Frame", { Size = UDim2.fromOffset(width, 32), LayoutOrder = order, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
		Parent = parent })
	UIKit.corner(k, 7)
	UIKit.gradient(k, Color3.fromRGB(250, 238, 210), Color3.fromRGB(200, 180, 140), 90)
	UIKit.stroke(k, Color3.fromRGB(90, 60, 30), 1.5, 0)
	text(k, label, { Font = UIKit.Fonts.Black, TextColor3 = Color3.fromRGB(50, 30, 15), TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1) }, 15)
	return k
end

function Panels.help(parent: Instance)
	local panel = UIKit.panel(parent, "AIDE & CRÉDITS")
	local content = panel.Content
	local economy = CardsData.Economy

	local nav = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 220, 1, 0), Parent = content })
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav })
	local page = box(content, { Position = UDim2.fromOffset(236, 0), Size = UDim2.new(1, -236, 1, 0) }, 14)
	UIKit.stroke(page, GOLD, 1, 0.6)
	local body = UIKit.new("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(22, 18), Size = UDim2.new(1, -40, 1, -32),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5, ScrollBarImageColor3 = GOLD, Selectable = false,
		Parent = page })

	local function clear()
		for _, c in ipairs(body:GetChildren()) do
			c:Destroy()
		end
		UIKit.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	end
	local function heading(value: string, order: number)
		text(body, value, { Font = UIKit.Fonts.Title, TextColor3 = GOLD, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order }, 28)
	end
	local function paragraph(value: string, order: number)
		local l = text(body, value, { Font = UIKit.Fonts.Body, TextColor3 = CREAM, TextWrapped = true, Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order }, 17)
		l.TextScaled = false
		l.TextSize = 17
	end

	local pages = {}
	-- Comment jouer : quatre étapes numérotées.
	pages[1] = function()
		heading("Comment jouer", 1)
		local steps = {
			{ "Ouvre des boosters", string.format("À l'autel ou chez les marchands. Chaque booster coûte %d gemmes et contient 3 créatures.", economy.BoosterPrice) },
			{ "Complète ton bestiaire", "30 créatures à découvrir. Les doublons te remboursent des gemmes selon leur rareté." },
			{ "Combats aux Arènes des Champions", "Choisis 3 créatures et affronte d'autres joueurs ou le mannequin de Varek, au tour par tour." },
			{ "Fais progresser tes Anima", "Chaque combat donne de l'expérience : tes créatures montent de niveau et évoluent aux niveaux 10 et 20." },
		}
		for i, s in ipairs(steps) do
			local row = box(body, { Size = UDim2.new(1, -8, 0, 74), LayoutOrder = 1 + i, BackgroundColor3 = INK, BackgroundTransparency = 0.3 }, 10)
			local n = UIKit.new("Frame", { Position = UDim2.fromOffset(14, 13), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = Color3.fromRGB(140, 30, 40),
				BorderSizePixel = 0, Parent = row })
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = n })
			UIKit.stroke(n, GOLD, 2, 0)
			text(n, tostring(i), { Font = UIKit.Fonts.Black, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) }, 22)
			text(row, s[1], { Font = UIKit.Fonts.Black, TextColor3 = GOLD, Position = UDim2.fromOffset(78, 10), Size = UDim2.new(1, -90, 0, 22) }, 18)
			text(row, s[2], { Font = UIKit.Fonts.Body, TextWrapped = true, Position = UDim2.fromOffset(78, 34), Size = UDim2.new(1, -92, 0, 36),
				TextYAlignment = Enum.TextYAlignment.Top }, 15)
		end
		paragraph("Les gemmes se gagnent en jouant : quêtes des villageois, duels, défi du jour de Rhéa et récompense de connexion (série de 7 jours).", 10)
	end
	-- Raretés : chances de tirage et remboursement des doublons.
	pages[2] = function()
		heading("Les raretés", 1)
		paragraph("Chances d'obtenir chaque rareté dans un booster, et gemmes rendues pour un doublon.", 2)
		local maxW = 0
		for _, r in ipairs(CardsData.Rarities) do
			maxW = math.max(maxW, r.Weight)
		end
		for i, r in ipairs(CardsData.Rarities) do
			local row = box(body, { Size = UDim2.new(1, -8, 0, 56), LayoutOrder = 2 + i, BackgroundColor3 = INK, BackgroundTransparency = 0.3 }, 10)
			local chip = UIKit.new("Frame", { Position = UDim2.fromOffset(14, 13), Size = UDim2.fromOffset(150, 30), BackgroundColor3 = r.Color:Lerp(Color3.new(0, 0, 0), 0.55),
				BorderSizePixel = 0, Parent = row })
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = chip })
			UIKit.stroke(chip, r.Color, 1.5, 0)
			text(chip, string.upper(r.Label), { Font = UIKit.Fonts.Black, TextColor3 = r.Color:Lerp(Color3.new(1, 1, 1), 0.5),
				TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) }, 14)
			local tr = UIKit.new("Frame", { Position = UDim2.fromOffset(180, 24), Size = UDim2.new(1, -420, 0, 8), BackgroundColor3 = Color3.fromRGB(45, 32, 70),
				BorderSizePixel = 0, Parent = row })
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = tr })
			local f = UIKit.new("Frame", { Size = UDim2.fromScale(math.max(r.Weight / maxW, 0.03), 1), BackgroundColor3 = r.Color, BorderSizePixel = 0, Parent = tr })
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = f })
			text(row, string.format("%g %%", r.Weight), { Font = UIKit.Fonts.Black, TextColor3 = r.Color, AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -150, 0, 0), Size = UDim2.fromOffset(80, 56), TextXAlignment = Enum.TextXAlignment.Right }, 18)
			text(row, string.format("doublon +%d", economy.DuplicateRefund[r.Id] or 0), { TextColor3 = Color3.fromRGB(150, 210, 255), AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -14, 0, 0), Size = UDim2.fromOffset(120, 56), TextXAlignment = Enum.TextXAlignment.Right }, 15)
		end
	end
	-- Contrôles : trois colonnes (PC, manette, mobile) avec touches dessinées.
	pages[3] = function()
		heading("Contrôles", 1)
		local columns = {
			{ "PC", { { { "Z", "Q", "S", "D" }, "Se déplacer" }, { { "Maj" }, "Courir" }, { { "E" }, "Interagir, livre" }, { { "B" }, "Booster" }, { { "Espace" }, "Sauter" } } },
			{ "MANETTE", { { { "Stick G" }, "Se déplacer" }, { { "L3" }, "Courir" }, { { "X" }, "Interagir" }, { { "Y" }, "Livre" }, { { "R1" }, "Booster" }, { { "B" }, "Retour" } } },
			{ "MOBILE", { { { "Joystick" }, "Se déplacer" }, { { "Courir" }, "Bouton à droite" }, { { "Toucher" }, "Invites et menus" }, { { "Livre" }, "Bouton en bas" } } },
		}
		for c, col in ipairs(columns) do
			local f = box(body, { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 + c, BackgroundColor3 = INK,
				BackgroundTransparency = 0.3 }, 10)
			UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
				Parent = f })
			UIKit.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
			text(f, col[1], { Font = UIKit.Fonts.Black, TextColor3 = GOLD, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 0 }, 17)
			for i, entry in ipairs(col[2]) do
				local row = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = i, Parent = f })
				local keys = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 260, 1, 0), Parent = row })
				UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
					Parent = keys })
				for k, key in ipairs(entry[1]) do
					keycap(keys, key, k)
				end
				text(row, entry[2], { Font = UIKit.Fonts.Body, Position = UDim2.fromOffset(272, 0), Size = UDim2.new(1, -272, 1, 0) }, 16)
			end
		end
	end
	-- Le monde : les quartiers de Brumeval.
	pages[4] = function()
		heading("La cité de Brumeval", 1)
		local places = {
			{ "Les Arènes des Champions", "Six arènes de duel, trois à l'est et trois à l'ouest, tenues par Varek. Au centre : l'autel des boosters.", Color3.fromRGB(150, 110, 255) },
			{ "La Grand-Place (sud)", "La boutique d'Elya, la taverne du Griffon Doré et la fontaine.", Color3.fromRGB(255, 200, 90) },
			{ "Le quartier des Artisans (ouest)", "La forge de Borin : vente et fusion de doublons.", Color3.fromRGB(255, 120, 60) },
			{ "Le quartier des Mages (nord)", "La tour de Maître Orin et le sanctuaire des cristaux de Sélène.", Color3.fromRGB(120, 180, 255) },
			{ "Le Jardin du Prieuré (sud-est)", "Le seul vrai coin de verdure de la ville.", Color3.fromRGB(95, 205, 110) },
			{ "Les remparts", "Des escaliers mènent au chemin de ronde. La nuit tombe toutes les 24 minutes : les braseros s'allument.", Color3.fromRGB(200, 190, 220) },
		}
		for i, p in ipairs(places) do
			local row = box(body, { Size = UDim2.new(1, -8, 0, 62), LayoutOrder = 1 + i, BackgroundColor3 = INK, BackgroundTransparency = 0.3 }, 10)
			UIKit.new("Frame", { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(0, 5, 1, -20), BackgroundColor3 = p[3], BorderSizePixel = 0, Parent = row })
			text(row, p[1], { Font = UIKit.Fonts.Black, TextColor3 = p[3]:Lerp(Color3.new(1, 1, 1), 0.3), Position = UDim2.fromOffset(18, 8), Size = UDim2.new(1, -30, 0, 22) }, 17)
			text(row, p[2], { Font = UIKit.Fonts.Body, TextWrapped = true, Position = UDim2.fromOffset(18, 32), Size = UDim2.new(1, -30, 0, 26),
				TextYAlignment = Enum.TextYAlignment.Top }, 15)
		end
	end
	-- Crédits.
	pages[5] = function()
		local titleL = text(body, "ARCANA BESTIA", { Font = UIKit.Fonts.Title, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 60),
			LayoutOrder = 1 }, 52)
		UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 240, 190), Color3.fromRGB(225, 165, 70)), Rotation = 90, Parent = titleL })
		text(body, "Le sanctuaire des bêtes", { TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 2 }, 17)
		for i, line in ipairs({
			{ "Conception et développement", "Baldyl66" },
			{ "Musiques", "APM Music, catalogue sous licence Roblox" },
			{ "Outils", "Roblox Studio et Rojo" },
		}) do
			local row = box(body, { Size = UDim2.new(1, -8, 0, 64), LayoutOrder = 2 + i, BackgroundColor3 = INK, BackgroundTransparency = 0.3 }, 10)
			text(row, string.upper(line[1]), { TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 10),
				Size = UDim2.new(1, 0, 0, 16) }, 13)
			text(row, line[2], { Font = UIKit.Fonts.Black, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 28),
				Size = UDim2.new(1, 0, 0, 26) }, 20)
		end
		text(body, "Merci de jouer !", { Font = UIKit.Fonts.Title, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = 10 }, 26)
	end

	local tabs = { "COMMENT JOUER", "RARETÉS", "CONTRÔLES", "LE MONDE", "CRÉDITS" }
	local colors = { GOLD, Color3.fromRGB(195, 95, 255), Color3.fromRGB(110, 150, 255), Color3.fromRGB(95, 205, 110), Color3.fromRGB(255, 120, 90) }
	local states = {}
	local buttons = {}
	local current = 1
	local function show(i: number)
		current = i
		for k, setActive in ipairs(states) do
			setActive(k == i)
		end
		clear()
		body.CanvasPosition = Vector2.zero
		pages[i]()
	end
	for i, label in ipairs(tabs) do
		local b, setActive = pill(nav, label, colors[i], 220, i)
		b.Size = UDim2.new(1, 0, 0, 48)
		states[i] = setActive
		buttons[i] = b
		b.Activated:Connect(function()
			UIKit.playSound("Click", 0.4, 1.2)
			show(i)
		end)
	end

	local baseOpen = panel.Open
	function panel:Open()
		baseOpen(self)
		show(current)
		UIKit.focus(buttons[current])
	end
	show(1)

	return panel
end

return Panels
