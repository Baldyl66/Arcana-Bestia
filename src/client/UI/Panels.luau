-- Panneaux modaux : Collection (bestiaire), Paramètres, Aide & crédits.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local CardView = require(script.Parent:WaitForChild("CardView"))

local Panels = {}

-------------------------------------------------------------------------------
-- Collection
-------------------------------------------------------------------------------
function Panels.collection(parent: Instance)
	local panel = UIKit.panel(parent, "BESTIAIRE")
	local content = panel.Content
	local filter = "Tout"
	local profile = nil

	local summary = UIKit.label({
		Text = "",
		Font = UIKit.Fonts.Bold,
		TextColor3 = UIKit.Colors.SubText,
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	}, 18)

	local tabs = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 46),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		Parent = content,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = tabs,
	})

	local grid = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 1, -86),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UIKit.Colors.Accent,
		Selectable = false,
		Parent = content,
	})
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 208),
		CellPadding = UDim2.fromOffset(16, 16),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 12),
		Parent = grid,
	})

	-- Aperçu détaillé d'une carte.
	local detail = UIKit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 5,
		Selectable = false,
		Parent = panel.Window,
	})
	UIKit.corner(detail, 18)
	local detailHolder = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.85),
		ZIndex = 5,
		Parent = detail,
	})
	local lastTile: GuiObject? = nil
	local function closeDetail()
		detail.Visible = false
		if lastTile then
			UIKit.focus(lastTile)
		end
	end
	detail.Activated:Connect(closeDetail)

	local function showDetail(card, count)
		for _, child in ipairs(detailHolder:GetChildren()) do
			child:Destroy()
		end
		local view = CardView.create(card, { Detailed = true, Count = count, Parent = detailHolder })
		view.AnchorPoint = Vector2.new(0.5, 0.5)
		view.Position = UDim2.fromScale(0.5, 0.5)
		for _, d in ipairs(view:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex += 5
			end
		end
		view.ZIndex = 6
		detail.Visible = true
		UIKit.focus(nil)
	end

	local tabButtons = {}
	local function render()
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local owned = profile and profile.Cards or {}

		local discovered, totalCopies = 0, 0
		for _, count in pairs(owned) do
			discovered += 1
			totalCopies += count
		end
		summary.Text = string.format("Créatures découvertes : %d / %d   •   Cartes possédées : %d   •   Boosters ouverts : %d",
			discovered, #CardsData.Cards, totalCopies, profile and profile.BoostersOpened or 0)

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
				local tile = UIKit.new("TextButton", {
					Name = card.Id,
					Text = "",
					AutoButtonColor = false,
					BackgroundTransparency = 1,
					LayoutOrder = index,
					Parent = grid,
				})
				local selection = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
				UIKit.corner(selection, 12)
				UIKit.stroke(selection, UIKit.Colors.Gold, 3, 0)
				tile.SelectionImageObject = selection
				local view = CardView.create(card, { Owned = count > 0, Count = count, Parent = tile })
				view.Active = false
				local scale = UIKit.new("UIScale", { Parent = tile })
				local function hover(on)
					UIKit.tween(scale, 0.15, { Scale = on and 1.06 or 1 }, Enum.EasingStyle.Back)
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
					if count > 0 then
						lastTile = tile
						UIKit.playSound("Click", 0.4)
						showDetail(card, count)
					end
				end)
				first = first or tile
			end
		end

		for id, button in pairs(tabButtons) do
			local active = id == filter
			UIKit.setDimmed(button, not active)
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = active and UIKit.Colors.Gold or UIKit.Colors.Accent
			end
		end
		return first
	end

	local tabList = { { Id = "Tout", Label = "TOUT" } }
	for _, rarity in ipairs(CardsData.Rarities) do
		table.insert(tabList, { Id = rarity.Id, Label = string.upper(rarity.Label) })
	end
	for index, tab in ipairs(tabList) do
		tabButtons[tab.Id] = UIKit.button({
			Text = tab.Label,
			Style = index == 1 and "Primary" or "Ghost",
			Size = UDim2.fromOffset(index == 1 and 90 or 140, 40),
			TextSize = 16,
			LayoutOrder = index,
			Parent = tabs,
			Callback = function()
				filter = tab.Id
				render()
			end,
		})
	end

	local baseOpen = panel.Open
	function panel:Open()
		detail.Visible = false
		baseOpen(self)
		local first = render()
		UIKit.focus(first)
	end

	function panel:SetProfile(newProfile)
		profile = newProfile
		if self.IsOpen then
			render()
		end
	end

	function panel:HandleBack(): boolean
		if detail.Visible then
			closeDetail()
			return true
		end
		return false
	end

	return panel
end

-------------------------------------------------------------------------------
-- Paramètres
-------------------------------------------------------------------------------
function Panels.settings(parent: Instance, onChanged: () -> ())
	local panel = UIKit.panel(parent, "PARAMÈTRES")
	local list = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UIKit.Colors.Accent,
		Selectable = false,
		Parent = panel.Content,
	})
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	local first = nil
	local function row(order: number, title: string, description: string, getText: () -> string, cycle: () -> ())
		local frame = UIKit.new("Frame", {
			BackgroundColor3 = UIKit.Colors.Panel,
			BackgroundTransparency = 0.2,
			Size = UDim2.new(1, -12, 0, 76),
			LayoutOrder = order,
			Parent = list,
		})
		UIKit.corner(frame, 12)
		UIKit.label({ Text = title, Font = UIKit.Fonts.Bold, Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -260, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left, Parent = frame }, 22)
		UIKit.label({ Text = description, Font = UIKit.Fonts.Body, TextColor3 = UIKit.Colors.SubText,
			Position = UDim2.fromOffset(18, 42), Size = UDim2.new(1, -260, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left, Parent = frame }, 16)
		local button
		button = UIKit.button({
			Text = getText(),
			Style = "Primary",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(200, 48),
			TextSize = 20,
			Parent = frame,
			Callback = function()
				cycle()
				button.Text = getText()
				onChanged()
			end,
		})
		first = first or button
	end

	local settings = UIKit.Settings
	local function onOff(value: boolean): string
		return value and "ACTIVÉ" or "DÉSACTIVÉ"
	end

	row(1, "Musique et sons", "Musique de fond et effets sonores.", function()
		return onOff(settings.Sound)
	end, function()
		settings.Sound = not settings.Sound
		require(script.Parent:WaitForChild("Music")).refresh()
	end)
	row(2, "Secousses d'écran", "Tremblement de caméra pour les cartes Épiques et Légendaires.", function()
		return onOff(settings.Shake)
	end, function()
		settings.Shake = not settings.Shake
	end)
	local scales = { 0.85, 1, 1.15, 1.3 }
	row(4, "Taille de l'interface", "Agrandis l'interface sur TV ou réduis-la sur petit écran.", function()
		return string.format("%d %%", math.floor(settings.UIScale * 100 + 0.5))
	end, function()
		local index = table.find(scales, settings.UIScale) or 2
		settings.UIScale = scales[index % #scales + 1]
	end)

	local baseOpen = panel.Open
	function panel:Open()
		baseOpen(self)
		UIKit.focus(first)
	end

	return panel
end

-------------------------------------------------------------------------------
-- Aide & crédits
-------------------------------------------------------------------------------
function Panels.help(parent: Instance)
	local panel = UIKit.panel(parent, "AIDE & CRÉDITS")
	local scroll = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UIKit.Colors.Accent,
		Parent = panel.Content,
	})
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

	local economy = CardsData.Economy
	local sections = {
		{ "COMMENT JOUER", string.format(
			"Chaque booster coûte %d ◆ et contient une créature. Les doublons te remboursent des gemmes selon leur rareté. "
				.. "Tu gagnes %d ◆ toutes les minutes passées en jeu, et une récompense chaque jour de connexion (série de 7 jours).",
			economy.BoosterPrice, economy.PassiveIncome) },
		{ "RARETÉS", "Commun 55 %   •   Peu commun 26 %   •   Rare 12 %   •   Épique 5,5 %   •   Légendaire 1,5 %" },
		{ "CONTRÔLES PC", "ZQSD / WASD pour se déplacer  •  Maj : courir  •  B : booster  •  E : utiliser l'autel" },
		{ "CONTRÔLES MANETTE", "Stick gauche pour se déplacer  •  L3 : courir  •  R1 : booster  •  X : autel  •  B : retour" },
		{ "MOBILE & TABLETTE", "Joystick virtuel à gauche, saut et « Courir » à droite. Touche les invites pour parler ou ouvrir un booster à l'autel." },
		{ "LE MONDE", "L'arène est au cœur de la cité fortifiée de Brumeval. Au sud, la Grand-Place (boutique d'Elya, taverne, fontaine) ; à l'ouest, le quartier des Artisans et la forge de Borin ; "
			.. "au nord, le quartier des Mages avec la tour d'Orin et le sanctuaire de Sélène ; à l'est, l'Arène des Champions. Des escaliers mènent au chemin de ronde des remparts. "
			.. "Le soleil se couche toutes les 24 minutes : les braseros et les lanternes s'allument dans la nuit." },
		{ "CRÉDITS", "Arcana Bestia — conception et développement par Baldyl66. Construit avec Roblox et Rojo." },
	}
	for index, section in ipairs(sections) do
		local frame = UIKit.new("Frame", {
			BackgroundColor3 = UIKit.Colors.Panel,
			BackgroundTransparency = 0.2,
			Size = UDim2.new(1, -12, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = index,
			Parent = scroll,
		})
		UIKit.corner(frame, 12)
		UIKit.padding(frame, 14)
		UIKit.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
		UIKit.new("TextLabel", {
			Text = section[1],
			Font = UIKit.Fonts.Black,
			TextColor3 = UIKit.Colors.Gold,
			TextSize = 18,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
			Parent = frame,
		})
		UIKit.new("TextLabel", {
			Text = section[2],
			Font = UIKit.Fonts.Body,
			TextColor3 = UIKit.Colors.Text,
			TextSize = 16,
			TextWrapped = true,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
			Parent = frame,
		})
	end

	return panel
end

return Panels
