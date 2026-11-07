-- Fiche détaillée d'une créature : grande carte, niveau et expérience, stats,
-- capacité, description, évolutions. Partagée par le carnet et le bestiaire
-- du menu.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local CardView = require(script.Parent:WaitForChild("CardView"))

local CardDetail = {}

-------------------------------------------------------------------------------
-- Fiche détaillée d'une créature (clic sur une carte du bestiaire).
-------------------------------------------------------------------------------
local detailGui: ScreenGui? = nil
local profile: any = nil
local closeCardDetail: () -> ()

closeCardDetail = function()
	if detailGui then
		detailGui:Destroy()
		detailGui = nil
	end
end

local function showCardDetail(card, known: boolean)
	closeCardDetail()
	UIKit.playSound("Click", 0.6, 1.1)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CardDetail"
	gui.DisplayOrder = 60
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	detailGui = gui

	-- Voile : un clic en dehors ferme la fiche.
	local veil = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), Selectable = false, Parent = gui })
	UIKit.tween(veil, 0.25, { BackgroundTransparency = 0.35 })
	veil.Activated:Connect(closeCardDetail)

	local panel = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(900, 560),
		BackgroundColor3 = Color3.fromRGB(236, 214, 165), Active = true, Parent = gui })
	UIKit.scaled(panel)
	UIKit.corner(panel, 14)
	UIKit.stroke(panel, Color3.fromRGB(140, 30, 30), 4, 0)
	panel.Position = UDim2.fromScale(0.5, 0.56)
	UIKit.tween(panel, 0.3, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)

	-- La carte en grand (immobile).
	local holder = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(36, 30), Size = UDim2.fromOffset(340, 497), Parent = panel })
	CardView.create(card, { Owned = known, Detailed = true, Size = UDim2.fromScale(1, 1), Parent = holder })

	local INK_DARK = Color3.fromRGB(60, 20, 15)
	local RED_DARK = Color3.fromRGB(140, 30, 30)
	local MUTED = Color3.fromRGB(125, 95, 65)
	local PARCH_DARK = Color3.fromRGB(214, 186, 132)
	local GOLD_D = Color3.fromRGB(196, 150, 60)
	local x, w = 410, 440

	local function label(parent: Instance, text: string, props: { [string]: any }, size: number): TextLabel
		props.Text = text
		props.RichText = true
		props.Font = props.Font or Enum.Font.Merriweather
		props.TextColor3 = props.TextColor3 or INK_DARK
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
		props.ZIndex = props.ZIndex or 4
		props.Parent = parent
		return UIKit.label(props, size)
	end
	local function tile(px: number, py: number, tw: number, th: number, color: Color3, transparency: number?): Frame
		local t = UIKit.new("Frame", { Position = UDim2.fromOffset(px, py), Size = UDim2.fromOffset(tw, th), BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0, ZIndex = 3, Parent = panel })
		UIKit.corner(t, 10)
		return t
	end
	-- Pastille arrondie (élément, rareté, exemplaires). Renvoie sa largeur.
	local function chip(px: number, py: number, text: string, bg: Color3, fg: Color3, width: number): Frame
		local c = tile(px, py, width, 28, bg)
		UIKit.corner(c, 14)
		label(c, text, { Font = UIKit.Fonts.Bold, TextColor3 = fg, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) }, 15)
		return c
	end
	local function gem(parent: Instance, pos: UDim2, sizePx: number, color: Color3, filled: boolean)
		local d = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(sizePx, sizePx), Rotation = 45,
			BackgroundColor3 = color, BackgroundTransparency = filled and 0 or 1, ZIndex = 5, Parent = parent })
		UIKit.stroke(d, filled and Color3.new(1, 1, 1) or color, 1.5, filled and 0.4 or 0)
		return d
	end
	-- Filet décoratif avec losange central.
	local function divider(py: number)
		for _, sx in ipairs({ -1, 1 }) do
			local l = UIKit.new("Frame", { AnchorPoint = Vector2.new(sx < 0 and 1 or 0, 0.5), Position = UDim2.fromOffset(x + w / 2 + sx * 10, py),
				Size = UDim2.fromOffset(w / 2 - 14, 2), BackgroundColor3 = GOLD_D, BorderSizePixel = 0, ZIndex = 3, Parent = panel })
			UIKit.new("UIGradient", { Transparency = NumberSequence.new(sx < 0 and 1 or 0, sx < 0 and 0 or 1), Parent = l })
		end
		gem(panel, UDim2.fromOffset(x + w / 2, py), 9, GOLD_D, true)
	end

	local element = CardsData.Elements[card.Element]
	local rarity = CardsData.RarityById[card.Rarity]
	local rarityDark = rarity.Color:Lerp(Color3.new(0, 0, 0), 0.55)

	-- Pastille de rareté : libellé + un losange par niveau de rareté.
	local function rarityChip(px: number, py: number): Frame
		local c = tile(px, py, 170, 28, rarityDark)
		UIKit.corner(c, 14)
		label(c, rarity.Label, { Font = UIKit.Fonts.Bold, TextColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -80, 1, 0) }, 15)
		for k = 1, 5 do
			gem(c, UDim2.new(1, -14 - (5 - k) * 13, 0.5, 0), 8, rarity.Color, k <= rarity.Order)
		end
		return c
	end

	if not known then
		label(panel, "CRÉATURE INCONNUE", { TextColor3 = RED_DARK, Position = UDim2.fromOffset(x, 40), Size = UDim2.fromOffset(w - 50, 44) }, 34)
		rarityChip(x, 96)
		divider(146)
		label(panel, "Cette créature n'a pas encore été découverte.\n\nOuvre des boosters à l'autel ou dans les boutiques de la ville pour l'ajouter à ton bestiaire !",
			{ TextWrapped = true, TextColor3 = MUTED, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(x, 170), Size = UDim2.fromOffset(w, 160) }, 19)
	else
		local xp = profile and profile.XP and profile.XP[card.Id] or 0
		local level = CardsData.levelFromXP(xp)
		local stageIndex = CardsData.stageOf(level)
		local hp, atk = CardsData.statsAt(card, level)
		local count = profile and profile.Cards and profile.Cards[card.Id] or 1

		-- En-tête : nom + pastilles.
		label(panel, string.upper(CardsData.displayName(card, level)), { TextColor3 = RED_DARK, Position = UDim2.fromOffset(x, 22),
			Size = UDim2.fromOffset(w - 50, 44) }, 36)
		chip(x, 74, element.Label, element.Color:Lerp(Color3.new(0, 0, 0), 0.25), Color3.new(1, 1, 1), 96)
		rarityChip(x + 104, 74)
		chip(x + 282, 74, "×" .. count .. (count > 1 and " exemplaires" or " exemplaire"), PARCH_DARK, INK_DARK, 158)
		divider(118)

		-- Niveau : médaillon + barre d'expérience.
		local medal = tile(x, 132, 58, 58, RED_DARK)
		UIKit.corner(medal, 29)
		UIKit.stroke(medal, GOLD_D, 3, 0)
		label(medal, "NIV.", { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(255, 225, 170), TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 12) }, 11)
		label(medal, tostring(level), { Font = UIKit.Fonts.Black, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 30) }, 26)
		local maxLevel = CardsData.Progression.MaxLevel
		local from, to = CardsData.xpForLevel(level), CardsData.xpForLevel(level + 1)
		label(panel, "<b>Expérience</b>", { Position = UDim2.fromOffset(x + 72, 138), Size = UDim2.fromOffset(160, 20) }, 16)
		label(panel, level >= maxLevel and "niveau max" or string.format("%d / %d XP", xp - from, to - from), { TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromOffset(x + w - 200, 138), Size = UDim2.fromOffset(200, 20) }, 15)
		local track = tile(x + 72, 164, w - 72, 16, Color3.fromRGB(120, 90, 55), 0.55)
		UIKit.corner(track, 8)
		local fill = UIKit.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 4, Parent = track })
		UIKit.corner(fill, 8)
		UIKit.gradient(fill, Color3.fromRGB(120, 220, 255), Color3.fromRGB(40, 110, 220), 0)
		local ratio = level >= maxLevel and 1 or math.clamp((xp - from) / math.max(1, to - from), 0, 1)
		UIKit.tween(fill, 0.9, { Size = UDim2.fromScale(math.max(ratio, 0.02), 1) }, Enum.EasingStyle.Quint)

		-- Statistiques : deux tuiles.
		local half = (w - 12) / 2
		for i, stat in ipairs({ { "POINTS DE VIE", hp, card.HP, Color3.fromRGB(190, 55, 60) }, { "ATTAQUE", atk, card.Attack, Color3.fromRGB(215, 120, 40) } }) do
			local t = tile(x + (i - 1) * (half + 12), 198, half, 62, stat[4])
			UIKit.gradient(t, stat[4], stat[4]:Lerp(Color3.new(0, 0, 0), 0.35), 90)
			label(t, stat[1], { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(255, 225, 200), Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 14) }, 12)
			label(t, tostring(stat[2]), { Font = UIKit.Fonts.Black, TextColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(14, 24), Size = UDim2.fromOffset(90, 32) }, 28)
			if stat[2] > stat[3] then
				label(t, "+" .. (stat[2] - stat[3]), { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(190, 255, 190), TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(1, -74, 0, 30), Size = UDim2.fromOffset(60, 22) }, 16)
			end
		end

		-- Capacité : encadré sombre, liseré de l'élément, coût en losanges d'énergie.
		local ability = card.Ability
		local box = tile(x, 272, w, 92, Color3.fromRGB(45, 22, 18))
		UIKit.stroke(box, GOLD_D, 1.5, 0.3)
		local accent = UIKit.new("Frame", { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(0, 5, 1, -20), BackgroundColor3 = element.Color, BorderSizePixel = 0,
			ZIndex = 4, Parent = box })
		UIKit.corner(accent, 3)
		label(box, "CAPACITÉ", { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(200, 170, 120), Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(120, 14) }, 12)
		label(box, ability.Name, { TextColor3 = Color3.fromRGB(255, 220, 140), Position = UDim2.fromOffset(18, 26), Size = UDim2.new(1, -140, 0, 28) }, 22)
		for k = 1, ability.Cost do
			gem(box, UDim2.new(1, -18 - (ability.Cost - k) * 18, 0, 22), 10, Color3.fromRGB(110, 205, 255), true)
		end
		label(box, "énergie", { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(150, 200, 230), TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(1, -110, 0, 34), Size = UDim2.fromOffset(100, 14) }, 12)
		label(box, CardsData.abilityText(ability), { Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(235, 220, 200), TextWrapped = true,
			Position = UDim2.fromOffset(18, 58), Size = UDim2.new(1, -36, 0, 26) }, 15)

		-- Description.
		label(panel, "« " .. (card.Description or "") .. " »", { TextColor3 = MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(x, 372), Size = UDim2.fromOffset(w, 40) }, 16)

		-- Évolutions : frise de trois médaillons reliés.
		divider(420)
		local stages = CardsData.Progression.Stages
		local col = w / #stages
		local link = UIKit.new("Frame", { Position = UDim2.fromOffset(x + col / 2, 451), Size = UDim2.fromOffset(col * (#stages - 1), 3),
			BackgroundColor3 = PARCH_DARK, BorderSizePixel = 0, ZIndex = 3, Parent = panel })
		local reachedTo = (stageIndex - 1) / math.max(1, #stages - 1)
		UIKit.new("Frame", { Size = UDim2.fromScale(reachedTo, 1), BackgroundColor3 = GOLD_D, BorderSizePixel = 0, ZIndex = 4, Parent = link })
		local numerals = { "I", "II", "III" }
		for i, st in ipairs(stages) do
			local reached = level >= st.Level
			local cx = x + col * (i - 0.5)
			local node = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, 452), Size = UDim2.fromOffset(36, 36),
				BackgroundColor3 = reached and RED_DARK or Color3.fromRGB(236, 214, 165), ZIndex = 5, Parent = panel })
			UIKit.corner(node, 18)
			UIKit.stroke(node, reached and GOLD_D or PARCH_DARK, 3, 0)
			label(node, numerals[i] or tostring(i), { Font = UIKit.Fonts.Black, TextColor3 = reached and Color3.new(1, 1, 1) or MUTED,
				TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 6 }, 15)
			local name = st.Label ~= "" and st.Label or "Forme de base"
			label(panel, "<b>" .. name .. "</b>", { TextColor3 = reached and INK_DARK or MUTED, TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(cx - col / 2, 476), Size = UDim2.fromOffset(col, 20) }, 15)
			label(panel, st.Bonus > 0 and string.format("niv. %d · +%d %%", st.Level, st.Bonus * 100) or "niv. 1", { Font = UIKit.Fonts.Bold,
				TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(cx - col / 2, 498), Size = UDim2.fromOffset(col, 16) }, 13)
		end
	end

	-- Bouton fermer : rond rouge avec une croix dessinée.
	local close = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(40, 40), BackgroundColor3 = RED_DARK, ZIndex = 6, Parent = panel })
	UIKit.corner(close, 20)
	UIKit.stroke(close, GOLD_D, 2, 0)
	for _, r in ipairs({ 45, -45 }) do
		local bar = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 3), Rotation = r,
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 7, Parent = close })
		UIKit.corner(bar, 2)
	end
	close.MouseEnter:Connect(function()
		UIKit.tween(close, 0.15, { BackgroundColor3 = Color3.fromRGB(190, 45, 45) })
	end)
	close.MouseLeave:Connect(function()
		UIKit.tween(close, 0.15, { BackgroundColor3 = RED_DARK })
	end)
	close.Activated:Connect(closeCardDetail)
	UIKit.select(close)
end

-- Ouvre la fiche (profile : instantané du joueur, pour le niveau et les exemplaires).
function CardDetail.show(card, known: boolean, playerProfile: any)
	profile = playerProfile
	showCardDetail(card, known)
end

function CardDetail.close()
	closeCardDetail()
end

function CardDetail.isOpen(): boolean
	return detailGui ~= nil
end

return CardDetail
