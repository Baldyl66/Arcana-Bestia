-- Rendu d'une carte au style « Arcana » du booster 3D (fichier Claude Design) :
-- fond sombre teinté de l'élément, double cadre or + couleur d'élément,
-- bandeau titre, fenêtre d'illustration rayonnante avec le symbole
-- alchimique de l'élément, gemmes de rareté et panneau d'informations.
-- CardView.back() dessine le dos (sceau ARCANA, constellations).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local CardView = {}

type Options = {
	Owned: boolean?,
	Count: number?,
	Detailed: boolean?,
	Size: UDim2?,
	Parent: Instance?,
}

local GOLD = Color3.fromRGB(217, 180, 90)
local GOLD_L = Color3.fromRGB(243, 217, 142)
local NIGHT = Color3.fromRGB(7, 10, 24)
local SERIF = Enum.Font.Merriweather

-- Couleurs « claires » des éléments pour le centre lumineux.
local LIGHT = {
	Feu = Color3.fromRGB(255, 213, 154),
	Eau = Color3.fromRGB(217, 243, 255),
	Nature = Color3.fromRGB(201, 245, 176),
	Foudre = Color3.fromRGB(255, 245, 190),
	Ombre = Color3.fromRGB(215, 190, 255),
	Lumiere = Color3.fromRGB(255, 252, 230),
}

local function frameIn(parent: Instance, props): Frame
	props.Parent = parent
	props.BorderSizePixel = 0
	return UIKit.new("Frame", props)
end

-- Trait (segment) entre deux points en coordonnées relatives.
local function segment(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, z: number, transparency: number?)
	local mid = (a + b) / 2
	local d = b - a
	return frameIn(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(mid.X, mid.Y),
		Size = UDim2.new(d.Magnitude, 0, 0, thickness),
		Rotation = math.deg(math.atan2(d.Y, d.X)),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		ZIndex = z,
	})
end

-- Cercle (anneau) centré, en fraction de la largeur du parent carré.
local function ringIn(parent: Instance, size: number, color: Color3, thickness: number, z: number, transparency: number?)
	local r = frameIn(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(size, size),
		BackgroundTransparency = 1,
		ZIndex = z,
	})
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = r })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = r })
	UIKit.stroke(r, color, thickness, transparency or 0)
	return r
end

-- Symbole alchimique de l'élément dans un cadre carré.
local function glyph(parent: Instance, elementId: string, color: Color3, z: number, thick: number)
	local box = frameIn(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62),
		BackgroundTransparency = 1, ZIndex = z })
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = box })
	ringIn(box, 1, color, math.max(1, thick * 0.4), z)
	local up = elementId == "Feu" or elementId == "Foudre" or elementId == "Lumiere"
	local top, left, right
	if up then
		top, left, right = Vector2.new(0.5, 0.18), Vector2.new(0.2, 0.71), Vector2.new(0.8, 0.71)
	else
		top, left, right = Vector2.new(0.5, 0.82), Vector2.new(0.2, 0.29), Vector2.new(0.8, 0.29)
	end
	for _, pair in ipairs({ { top, left }, { left, right }, { right, top } }) do
		segment(box, pair[1], pair[2], thick, color, z + 1)
	end
	if elementId == "Nature" or elementId == "Foudre" then
		segment(box, Vector2.new(0.3, up and 0.52 or 0.48), Vector2.new(0.7, up and 0.52 or 0.48), thick, color, z + 1)
	elseif elementId == "Eau" then
		for k = 0, 7 do
			local x0, x1 = 0.36 + k * 0.035, 0.36 + (k + 1) * 0.035
			segment(box, Vector2.new(x0, 0.4 + math.sin(k) * 0.025), Vector2.new(x1, 0.4 + math.sin(k + 1) * 0.025), math.max(1, thick * 0.6), color, z + 1)
		end
	elseif elementId == "Ombre" then
		local dot = frameIn(box, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.12, 0.12),
			BackgroundColor3 = color, ZIndex = z + 1 })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
	elseif elementId == "Lumiere" then
		ringIn(box, 0.22, color, math.max(1, thick * 0.6), z + 1).Position = UDim2.fromScale(0.5, 0.55)
	end
	return box
end

local function diamond(parent: Instance, pos: UDim2, size: UDim2, color: Color3, z: number)
	local d = frameIn(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = size, Rotation = 45, BackgroundColor3 = color, ZIndex = z })
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = d })
	UIKit.stroke(d, GOLD_L, 1, 0)
	return d
end

local function base(options: Options?): (Frame, boolean)
	local opts = options or {}
	local detailed = opts.Detailed == true
	local frame = UIKit.new("Frame", {
		Size = opts.Size or UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = false,
		Parent = opts.Parent,
	})
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 512 / 748, Parent = frame })
	UIKit.corner(frame, detailed and 10 or 6)
	return frame, detailed
end

function CardView.create(card, options: Options?): Frame
	local opts = options or {}
	local owned = opts.Owned ~= false
	local element = CardsData.Elements[card.Element] or CardsData.Elements.Feu
	local rarity = CardsData.RarityById[card.Rarity] or CardsData.Rarities[1]
	local frame, detailed = base(opts)
	frame.Name = card.Id
	local main = owned and element.Color or Color3.fromRGB(70, 68, 85)
	local dark = owned and element.Dark or Color3.fromRGB(22, 20, 30)
	local light = owned and (LIGHT[card.Element] or Color3.new(1, 1, 1)) or Color3.fromRGB(120, 116, 140)
	local thick = detailed and 3 or 1.5

	UIKit.gradient(frame, dark, NIGHT, 90)
	UIKit.stroke(frame, GOLD, detailed and 6 or 3, 0)
	local inner = frameIn(frame, { Position = UDim2.fromScale(0.035, 0.025), Size = UDim2.fromScale(0.93, 0.95), BackgroundTransparency = 1, ZIndex = 1 })
	UIKit.corner(inner, detailed and 6 or 4)
	UIKit.stroke(inner, main, detailed and 2 or 1, 0)

	-- Bandeau titre.
	local title = frameIn(frame, { Position = UDim2.fromScale(0.086, 0.059), Size = UDim2.fromScale(0.828, 0.086), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55, ZIndex = 2 })
	UIKit.stroke(title, GOLD, 1, 0)
	UIKit.label({ Name = "CardName", Text = owned and string.upper(card.Name) or "???", Font = SERIF, TextColor3 = GOLD_L,
		Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), ZIndex = 3, Parent = title }, detailed and 34 or 16)

	-- Fenêtre d'illustration : centre lumineux, rayons, étoiles, symbole.
	local art = frameIn(frame, { Name = "Art", Position = UDim2.fromScale(0.086, 0.163), Size = UDim2.fromScale(0.828, 0.535),
		BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true, ZIndex = 2 })
	UIKit.gradient(art, dark, main:Lerp(dark, 0.3), 90)
	UIKit.stroke(art, GOLD, detailed and 3 or 1.5, 0)
	for k, s in ipairs({ 1.3, 0.85, 0.5 }) do
		local glow = frameIn(art, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(s, s),
			BackgroundColor3 = k == 3 and light or main, BackgroundTransparency = 0.55 + k * 0.05, ZIndex = 2 })
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = glow })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
	end
	for i = 0, 12 do
		frameIn(art, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, detailed and 5 or 2, 2.2, 0),
			Rotation = i * 180 / 13, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88, ZIndex = 3 })
	end
	local seed = 11
	local function rnd()
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	for _ = 1, detailed and 30 or 12 do
		local sz = detailed and (2 + math.floor(rnd() * 3)) or 1 + math.floor(rnd() * 2)
		frameIn(art, { Position = UDim2.fromScale(rnd(), rnd()), Size = UDim2.fromOffset(sz, sz), BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.2 + rnd() * 0.6, ZIndex = 3 })
	end
	if owned then
		glyph(art, card.Element, Color3.fromRGB(255, 248, 230), 4, detailed and 5 or 2)
	else
		UIKit.label({ Text = "?", Font = SERIF, TextColor3 = Color3.fromRGB(160, 155, 180), Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = art }, 80)
	end

	-- Panneau du bas : gemmes de rareté, élément, statistiques.
	local panel = frameIn(frame, { Position = UDim2.fromScale(0.086, 0.722), Size = UDim2.fromScale(0.828, 0.2), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6, ZIndex = 2 })
	UIKit.stroke(panel, GOLD, 1, 0)
	for k = 1, rarity.Order do
		diamond(panel, UDim2.fromScale(0.5 + (k - (rarity.Order + 1) / 2) * 0.09, 0.2), UDim2.fromScale(0.06, 0.06), owned and rarity.Color or main, 3)
	end
	UIKit.label({ Name = "Rarity", Text = owned and ("Arcana · " .. rarity.Label .. " · " .. element.Label) or "Non découverte", Font = Enum.Font.Merriweather,
		TextColor3 = GOLD_L, Position = UDim2.fromScale(0.04, 0.36), Size = UDim2.fromScale(0.92, 0.26), ZIndex = 3, Parent = panel }, detailed and 20 or 11)
	segment(panel, Vector2.new(0.22, 0.68), Vector2.new(0.78, 0.68), 1, main, 3)
	if owned then
		UIKit.label({ Name = "Stats", Text = string.format("PV %d   ·   ATQ %d", card.HP, card.Attack), Font = UIKit.Fonts.Bold, TextColor3 = Color3.fromRGB(255, 244, 220),
			Position = UDim2.fromScale(0.04, 0.72), Size = UDim2.fromScale(0.92, 0.24), ZIndex = 3, Parent = panel }, detailed and 20 or 11)
	end
	if detailed and owned and card.Description then
		UIKit.label({ Name = "Description", Text = card.Description, Font = Enum.Font.Merriweather, TextColor3 = Color3.fromRGB(225, 215, 195),
			Position = UDim2.fromScale(0.08, 0.93), Size = UDim2.fromScale(0.84, 0.055), ZIndex = 3, Parent = frame }, 13)
	end

	if owned and (opts.Count or 0) > 1 then
		local badge = frameIn(frame, { Name = "CountBadge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 4, 0, -4), Size = UDim2.fromScale(0.3, 0.12),
			BackgroundColor3 = GOLD, ZIndex = 6 })
		UIKit.corner(badge, 20)
		UIKit.label({ Text = "x" .. opts.Count, Font = UIKit.Fonts.Black, TextColor3 = Color3.fromRGB(45, 25, 5), Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = badge }, 16)
	end

	-- Reflet qui balaie les cartes Épiques et Légendaires.
	if owned and rarity.Order >= 4 then
		local shine = frameIn(frame, { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
		UIKit.corner(shine, detailed and 10 or 6)
		local gradient = UIKit.new("UIGradient", {
			Rotation = 25,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(0.5, 0.7),
				NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1) }),
			Offset = Vector2.new(-1, 0),
			Parent = shine,
		})
		task.spawn(function()
			while frame.Parent do
				gradient.Offset = Vector2.new(-1, 0)
				UIKit.tween(gradient, 1.4, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
				task.wait(1.6)
			end
		end)
	end
	return frame
end

-- Dos de carte : nuit étoilée, double cadre, ARCANA, sceau, ELEMENTA.
function CardView.back(options: Options?): Frame
	local frame, detailed = base(options)
	frame.Name = "CardBack"
	UIKit.gradient(frame, Color3.fromRGB(42, 74, 160), NIGHT, 90)
	UIKit.stroke(frame, GOLD, detailed and 6 or 3, 0)
	for _, inset in ipairs({ 0.023, 0.039 }) do
		local f = frameIn(frame, { Position = UDim2.fromScale(inset * 1.46, inset), Size = UDim2.fromScale(1 - inset * 2.92, 1 - inset * 2), BackgroundTransparency = 1, ZIndex = 1 })
		UIKit.stroke(f, GOLD, 1, 0)
	end
	local seed = 7
	local function rnd()
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	for _ = 1, detailed and 60 or 24 do
		local sz = 1 + math.floor(rnd() * 2)
		frameIn(frame, { Position = UDim2.fromScale(rnd(), rnd()), Size = UDim2.fromOffset(sz, sz), BackgroundColor3 = Color3.fromRGB(220, 230, 255),
			BackgroundTransparency = 0.3 + rnd() * 0.5, ZIndex = 1 })
	end
	UIKit.label({ Text = "ARCANA", Font = SERIF, TextColor3 = Color3.fromRGB(232, 197, 108), Position = UDim2.fromScale(0.1, 0.11), Size = UDim2.fromScale(0.8, 0.09),
		ZIndex = 3, Parent = frame }, detailed and 54 or 22)
	segment(frame, Vector2.new(0.23, 0.2), Vector2.new(0.77, 0.2), 1, GOLD, 3)
	-- Sceau : anneaux, étoile et orbite.
	local seal = frameIn(frame, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62), BackgroundTransparency = 1, ZIndex = 2 })
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = seal })
	for _, data in ipairs({ { 1, 2.5 }, { 0.91, 1 }, { 0.7, 1.5 }, { 0.47, 1 } }) do
		ringIn(seal, data[1], GOLD, detailed and data[2] or math.max(1, data[2] * 0.5), 3)
	end
	local glow = frameIn(seal, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.44, 0.44),
		BackgroundColor3 = Color3.fromRGB(255, 200, 110), BackgroundTransparency = 0.45, ZIndex = 3 })
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = glow })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
	for k = 0, 3 do
		frameIn(seal, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(k % 2 == 0 and 0.36 or 0.22, 0.05),
			Rotation = k * 45, BackgroundColor3 = GOLD_L, ZIndex = 4 })
	end
	local orbit = frameIn(seal, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.2, 0.33), Rotation = -23,
		BackgroundTransparency = 1, ZIndex = 4 })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = orbit })
	UIKit.stroke(orbit, GOLD_L, 1, 0.2)
	-- Symboles des éléments autour du sceau.
	for _, data in ipairs({ { "Feu", 0.5, 0.06 }, { "Eau", 0.94, 0.5 }, { "Nature", 0.06, 0.5 }, { "Foudre", 0.5, 0.94 } }) do
		local el = CardsData.Elements[data[1]]
		local medal = frameIn(seal, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(data[2], data[3]), Size = UDim2.fromScale(0.17, 0.17),
			BackgroundColor3 = Color3.fromRGB(11, 21, 61), ZIndex = 5 })
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = medal })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = medal })
		UIKit.stroke(medal, GOLD, 1.5, 0)
		local dot = frameIn(medal, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.45, 0.45), Rotation = 45,
			BackgroundColor3 = el.Color, ZIndex = 6 })
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = dot })
	end
	segment(frame, Vector2.new(0.23, 0.8), Vector2.new(0.77, 0.8), 1, GOLD, 3)
	UIKit.label({ Text = "✦  ELEMENTA  ✦", Font = Enum.Font.Merriweather, TextColor3 = Color3.fromRGB(232, 197, 108), Position = UDim2.fromScale(0.1, 0.82),
		Size = UDim2.fromScale(0.8, 0.05), ZIndex = 3, Parent = frame }, detailed and 20 or 10)
	segment(frame, Vector2.new(0.29, 0.877), Vector2.new(0.71, 0.877), 1, GOLD, 3)
	for _, p in ipairs({ { 0.5, 0.048 }, { 0.5, 0.952 }, { 0.07, 0.5 }, { 0.93, 0.5 } }) do
		diamond(frame, UDim2.fromScale(p[1], p[2]), UDim2.fromScale(0.03, 0.03), GOLD_L, 3)
	end
	return frame
end

return CardView
