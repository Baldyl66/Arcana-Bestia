-- Récompenses de connexion quotidienne : calendrier de 7 cartes ornées
-- (bronze, argent, booster violet, grand final du jour 7). Le jour du jour
-- brille et se récupère d'un clic.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local DailyRewards = {}

local CREAM = Color3.fromRGB(255, 244, 220)
local GOLD = Color3.fromRGB(235, 190, 100)

-- Habillage de chaque carte : { haut, bas, bordure }.
local THEMES = {
	Bronze = { Color3.fromRGB(125, 80, 38), Color3.fromRGB(62, 36, 16), GOLD },
	Silver = { Color3.fromRGB(42, 52, 105), Color3.fromRGB(14, 16, 42), Color3.fromRGB(205, 210, 225) },
	Booster = { Color3.fromRGB(95, 50, 150), Color3.fromRGB(38, 16, 70), GOLD },
	Final = { Color3.fromRGB(110, 55, 175), Color3.fromRGB(40, 15, 80), Color3.fromRGB(255, 215, 120) },
}

-- Gemme taillée : losange, facette claire et reflet.
local function drawGem(parent: Instance, size: number, top: Color3, bottom: Color3)
	local gem = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(size, size),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = parent,
	})
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = gem })
	UIKit.corner(gem, 6)
	UIKit.gradient(gem, top, bottom, 45)
	UIKit.stroke(gem, Color3.fromRGB(235, 248, 255), 2, 0.15)
	local inner = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.55, 0.55),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.6,
		ZIndex = 4,
		Parent = gem,
	})
	UIKit.corner(inner, 4)
	UIKit.new("UIGradient", { Rotation = 45, Transparency = NumberSequence.new(0.1, 0.9), Parent = inner })
	local shine = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.3,
		Position = UDim2.fromScale(0.12, 0.12),
		Size = UDim2.fromScale(0.22, 0.22),
		ZIndex = 5,
		Parent = gem,
	})
	UIKit.corner(shine, 3)
	return gem
end

-- Deux cartes de booster superposées avec un sceau doré.
local function drawBooster(parent: Instance)
	local holder = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.62, 0.42),
		ZIndex = 3,
		Parent = parent,
	})
	for i, rotation in ipairs({ 10, -6 }) do
		local c = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + (i == 1 and 0.12 or -0.04), 0.5),
			Size = UDim2.fromScale(1, 1),
			Rotation = rotation,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 2 + i,
			Parent = holder,
		})
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = 0.72, Parent = c })
		UIKit.corner(c, 6)
		UIKit.gradient(c, Color3.fromRGB(140, 80, 210), Color3.fromRGB(50, 20, 95), 90)
		UIKit.stroke(c, GOLD, 2, 0)
		if i == 2 then
			local seal = UIKit.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.55, 0.55),
				BackgroundTransparency = 1,
				ZIndex = 6,
				Parent = c,
			})
			UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = seal })
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = seal })
			UIKit.stroke(seal, GOLD, 2, 0)
			local dot = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.35, 0.35),
				Rotation = 45, BackgroundColor3 = GOLD, ZIndex = 7, Parent = seal })
			UIKit.corner(dot, 2)
		end
	end
	return holder
end

function DailyRewards.new(parent: Instance, claim: () -> ())
	local panel = UIKit.panel(parent, "RÉCOMPENSES QUOTIDIENNES")
	local content = panel.Content
	local rewards = CardsData.Economy.DailyRewards
	local profile = nil

	local subtitle = UIKit.label({
		Text = "",
		Font = UIKit.Fonts.Bold,
		TextColor3 = Color3.fromRGB(225, 215, 195),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = content,
	}, 18)

	-- Zone des cartes : une rangée de 7 sur grand écran, deux rangées (4 + 3)
	-- sur téléphone ou écran étroit.
	local area = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -120),
		Parent = content,
	})
	local function makeRow(order: number)
		local r = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), LayoutOrder = order, Parent = area })
		UIKit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0.014, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = r,
		})
		return r
	end
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0.03, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = area,
	})
	local rowA, rowB = makeRow(1), makeRow(2)
	local row = rowA

	local tiles = {}
	for day, reward in ipairs(rewards) do
		local final = day == #rewards
		local theme = final and THEMES.Final or (reward.Booster and THEMES.Booster) or (day % 2 == 1 and THEMES.Bronze or THEMES.Silver)
		local tile = UIKit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			LayoutOrder = day,
			Parent = row,
		})
		UIKit.corner(tile, 10)
		UIKit.gradient(tile, theme[1], theme[2], 90)
		local stroke = UIKit.stroke(tile, theme[3], final and 3 or 2.5, 0)
		local inset = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), Parent = tile })
		UIKit.corner(inset, 7)
		UIKit.stroke(inset, theme[3], 1, 0.55)
		local scale = UIKit.new("UIScale", { Parent = tile })

		-- Petites étoiles dans le fond des cartes.
		for _ = 1, 6 do
			local s = math.random(2, 3)
			UIKit.new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = math.random() * 0.4 + 0.4,
				BorderSizePixel = 0,
				Position = UDim2.new(math.random() * 0.85 + 0.05, 0, math.random() * 0.8 + 0.1, 0),
				Size = UDim2.fromOffset(s, s),
				Parent = tile,
			})
		end

		-- Halo derrière l'illustration.
		local glow = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromScale(1.05, 1.05),
			BackgroundColor3 = final and Color3.fromRGB(210, 150, 255) or Color3.fromRGB(150, 220, 255),
			ZIndex = 2,
			Parent = tile,
		})
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = glow })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
		UIKit.new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 1) }),
			Parent = glow,
		})

		-- Bandeau « JOUR N » en haut de la carte.
		local plate = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, final and 18 or 16),
			Size = UDim2.new(0.8, 0, 0, 24),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = tile,
		})
		UIKit.corner(plate, 5)
		UIKit.gradient(plate, Color3.fromRGB(60, 50, 45), Color3.fromRGB(25, 20, 18), 90)
		UIKit.stroke(plate, theme[3], 1.5, 0)
		UIKit.label({ Text = "JOUR " .. day, Font = UIKit.Fonts.Black, TextColor3 = CREAM, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = plate }, 14)
		if final then
			-- Joyaux de couronne au-dessus et en dessous de la grande carte.
			for _, y in ipairs({ 0, 1 }) do
				local jewel = UIKit.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, y),
					Size = UDim2.fromOffset(16, 16),
					Rotation = 45,
					BackgroundColor3 = Color3.fromRGB(220, 40, 70),
					ZIndex = 7,
					Parent = tile,
				})
				UIKit.stroke(jewel, Color3.fromRGB(255, 215, 120), 2, 0)
			end
		end

		local medal
		if reward.Booster then
			medal = drawBooster(tile)
		elseif final then
			medal = drawGem(tile, 0.62, Color3.fromRGB(215, 160, 255), Color3.fromRGB(95, 30, 170))
		else
			medal = drawGem(tile, 0.5, Color3.fromRGB(160, 235, 255), Color3.fromRGB(35, 105, 225))
		end

		UIKit.label({
			Text = reward.Label,
			Font = UIKit.Fonts.Black,
			TextColor3 = CREAM,
			Position = UDim2.new(0.05, 0, 0.72, 0),
			Size = UDim2.new(0.9, 0, 0.11, 0),
			ZIndex = 5,
			Parent = tile,
		}, final and 20 or 18)
		local state = UIKit.label({
			Text = "",
			Font = UIKit.Fonts.Black,
			TextColor3 = UIKit.Colors.SubText,
			Position = UDim2.new(0.05, 0, 0.85, 0),
			Size = UDim2.new(0.9, 0, 0.08, 0),
			ZIndex = 5,
			Parent = tile,
		}, 12)

		-- Voile sombre sur les jours déjà récupérés.
		local done = UIKit.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(8, 8, 14),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
			Parent = tile,
		})
		UIKit.corner(done, 10)
		state.ZIndex = 9
		tiles[day] = { Frame = tile, Stroke = stroke, Theme = theme, Final = final, State = state, Scale = scale, Done = done, Glow = glow, Medal = medal }
	end

	local claimButton = UIKit.button({
		Text = "RÉCUPÉRER",
		Style = "Gold",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(0.6, 0, 0, 60),
		TextSize = 24,
		Parent = content,
		Callback = function()
			claim()
		end,
	})

	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(300, 60), Parent = claimButton })

	-- Mise en page selon la place disponible (PC, tablette, téléphone, console).
	local compact: boolean? = nil
	local windowScale = panel.Window:FindFirstChildOfClass("UIScale")
	local function layout()
		-- Taille « virtuelle » de la zone : la fenêtre est déjà réduite par son
		-- UIScale pour tenir à l'écran ; sans cette correction, les cartes étaient
		-- réduites deux fois (minuscules sur téléphone).
		local s = windowScale and windowScale.Scale or 1
		local size = area.AbsoluteSize / math.max(s, 0.01)
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		-- Même disposition sur toutes les plateformes : une rangée de 7 jours.
		local wantCompact = false
		if wantCompact ~= compact then
			compact = wantCompact
			rowB.Visible = compact
			for day, tile in pairs(tiles) do
				tile.Frame.Parent = (compact and day > 4) and rowB or rowA
			end
		end
		-- Hauteur des rangées et taille des cartes (proportion 0,62 largeur/hauteur).
		local rows = compact and 2 or 1
		local perRow = compact and 4 or 7
		local rowH = (size.Y - (rows - 1) * size.Y * 0.03) / rows
		rowA.Size = UDim2.new(1, 0, 0, rowH)
		rowB.Size = UDim2.new(1, 0, 0, rowH)
		local maxW = size.X * (1 - 0.014 * (perRow - 1)) / (perRow + 0.4)
		for _, tile in pairs(tiles) do
			local h = rowH * (tile.Final and 0.98 or 0.84)
			local w = math.min(h * (tile.Final and 0.7 or 0.62), maxW * (tile.Final and 1.35 or 1))
			tile.Frame.Size = UDim2.fromOffset(w, math.min(h, w / (tile.Final and 0.7 or 0.62)))
		end
	end
	area:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	if windowScale then
		windowScale:GetPropertyChangedSignal("Scale"):Connect(layout)
	end
	task.defer(layout)

	panel.ClaimButton = claimButton
	local pulseToken = 0
	local function refresh()
		if profile == nil then
			return
		end
		local streak = profile.DailyStreak or 0
		local nextDay = profile.DailyNext or 1
		local available = profile.DailyAvailable == true
		subtitle.Text = available
			and string.format("Série actuelle : %d jour%s. Connecte-toi chaque jour : un jour manqué et la série recommence.", streak, streak > 1 and "s" or "")
			or string.format("Série actuelle : %d jour%s. Reviens demain pour le jour %d !", streak, streak > 1 and "s" or "", nextDay)

		pulseToken += 1
		local token = pulseToken
		for day, tile in pairs(tiles) do
			local claimed = (available and day < nextDay) or (not available and day <= streak)
			local isToday = available and day == nextDay
			tile.Stroke.Color = isToday and Color3.fromRGB(255, 225, 130) or tile.Theme[3]
			tile.Stroke.Thickness = isToday and 4 or (tile.Final and 3 or 2.5)
			tile.State.Text = claimed and "RÉCUPÉRÉ" or (isToday and "AUJOURD'HUI" or (not available and day == nextDay and "DEMAIN" or ""))
			tile.State.TextColor3 = claimed and UIKit.Colors.Success or (isToday and Color3.fromRGB(255, 225, 130) or UIKit.Colors.SubText)
			tile.Scale.Scale = 1
			tile.Done.BackgroundTransparency = claimed and 0.45 or 1
			tile.Glow.Visible = not claimed
			if isToday then
				task.spawn(function()
					while token == pulseToken and panel.IsOpen do
						UIKit.tween(tile.Scale, 0.6, { Scale = 1.06 }, Enum.EasingStyle.Sine).Completed:Wait()
						UIKit.tween(tile.Scale, 0.6, { Scale = 1 }, Enum.EasingStyle.Sine).Completed:Wait()
					end
				end)
				task.spawn(function()
					local base = tile.Medal.Rotation
					while token == pulseToken and panel.IsOpen do
						UIKit.tween(tile.Medal, 0.9, { Rotation = base + 8 }, Enum.EasingStyle.Sine).Completed:Wait()
						UIKit.tween(tile.Medal, 0.9, { Rotation = base - 8 }, Enum.EasingStyle.Sine).Completed:Wait()
					end
					tile.Medal.Rotation = base
				end)
			end
		end
		claimButton.Visible = available
	end

	function panel:SetProfile(newProfile)
		profile = newProfile
		if self.IsOpen then
			refresh()
		end
	end

	local baseOpen = panel.Open
	function panel:Open()
		baseOpen(self)
		layout()
		refresh()
		if claimButton.Visible then
			UIKit.focus(claimButton)
		end
	end

	return panel
end

return DailyRewards
