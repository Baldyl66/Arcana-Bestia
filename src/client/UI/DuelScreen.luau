-- Écran de duel du Colisée :
--   • sélection : le joueur choisit ses 3 créatures dans sa collection ;
--   • intro « X VS Y » : avatars et pseudos qui glissent de chaque côté,
--     VS qui s'écrase au centre, éclair, puis compte à rebours ;
--   • arène au tour par tour : bandeaux des joueurs et réserves, créatures
--     actives avec aura, vie et garde, médaillon du tour et minuteur,
--     journal du combat, trois actions avec estimation des dégâts ;
--   • résolution animée (charge, impact, dégâts, soins, K.O.) et écran de fin.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local CardView = require(script.Parent:WaitForChild("CardView"))
local DuelCinematic = require(script.Parent:WaitForChild("DuelCinematic"))
local Arena3D = require(script.Parent:WaitForChild("Arena3D"))

local DuelScreen = {}
DuelScreen.__index = DuelScreen

local BLUE = Color3.fromRGB(70, 140, 255)
local RED = Color3.fromRGB(235, 70, 80)
local GOLD = Color3.fromRGB(255, 215, 120)
local CREAM = Color3.fromRGB(255, 244, 220)

type Callbacks = { Act: (action: string) -> (), Pick: (ids: { string }) -> boolean, Shake: (number, number) -> () }

local function headshot(userId: number): string
	local ok, url = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	return ok and url or ""
end

function DuelScreen.new(parent: Instance, callbacks: Callbacks)
	local self = setmetatable({}, DuelScreen)
	self.Callbacks = callbacks
	self.Token = 0

	local root = UIKit.new("Frame", {
		Name = "DuelScreen",
		BackgroundColor3 = Color3.fromRGB(6, 4, 14),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Active = true,
		ZIndex = 60,
		Parent = parent,
	})
	self.Root = root
	return self
end

function DuelScreen:Clear()
	for _, child in ipairs(self.Root:GetChildren()) do
		child:Destroy()
	end
end

-------------------------------------------------------------------------------
-- Intro VS
-------------------------------------------------------------------------------
local function bodyshot(userId: number): string
	local ok, url = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.AvatarThumbnail, Enum.ThumbnailSize.Size420x420)
	return ok and url or ""
end

local SLANT = 14 -- inclinaison de la coupe centrale, en degrés

-- Un camp de l'écran VS : grand panneau incliné, lignes de vitesse,
-- avatar en pied, pseudo et équipe de créatures.
local function side(slab: Instance, parent: Instance, info, isLeft: boolean, color: Color3): (Frame, Frame)
	local dir = isLeft and -1 or 1
	-- Panneau incliné très large : son bord intérieur forme la diagonale.
	-- Le cadre `slab` est incliné et centré sur l'écran : la jonction des
	-- deux panneaux passe exactement par le centre.
	local panel = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(isLeft and 1 or 0, 0),
		Position = UDim2.fromScale(isLeft and -0.5 or 1.5, 0),
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 61,
		Parent = slab,
	})
	UIKit.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(0, 0, 0), 0.82)),
			ColorSequenceKeypoint.new(0.75, color:Lerp(Color3.new(0, 0, 0), 0.35)),
			ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(1, 1, 1), 0.1)),
		}),
		Rotation = isLeft and 0 or 180,
		Parent = panel,
	})
	-- Lignes de vitesse qui défilent vers le centre.
	local lines = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = 62, Parent = panel })
	for i = 1, 14 do
		local line = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(math.random(), (i - 0.5) / 14),
			Size = UDim2.new(math.random(15, 40) / 100, 0, 0, math.random(2, 5)),
			BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.6),
			BackgroundTransparency = math.random(55, 85) / 100,
			BorderSizePixel = 0,
			ZIndex = 62,
			Parent = lines,
		})
		task.spawn(function()
			local speed = math.random(6, 12) / 10
			while line.Parent do
				line.Position = UDim2.fromScale(isLeft and -0.3 or 1.3, line.Position.Y.Scale)
				UIKit.tween(line, speed, { Position = UDim2.fromScale(isLeft and 1.3 or -0.3, line.Position.Y.Scale) }, Enum.EasingStyle.Linear).Completed:Wait()
			end
		end)
	end
	-- Liseré lumineux le long de la diagonale.
	UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(isLeft and 1 or 0, 0.5),
		Size = UDim2.new(0, 6, 1, 0),
		BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.55),
		BorderSizePixel = 0,
		ZIndex = 63,
		Parent = panel,
	})

	-- Contenu non incliné, posé par-dessus.
	local content = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(isLeft and 0.26 or 0.74, 0.54),
		Size = UDim2.fromOffset(460, 560),
		ZIndex = 64,
		Parent = parent,
	})
	UIKit.scaled(content)
	-- Halo derrière l'avatar.
	local halo = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(380, 380),
		BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.3), BackgroundTransparency = 0.6, ZIndex = 64, Parent = content })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = halo })
	UIKit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.7, 0.8), NumberSequenceKeypoint.new(1, 1) }),
		Parent = halo })
	local avatar = UIKit.new("ImageLabel", { BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.55), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(330, 330), Image = "", ZIndex = 65, Parent = content })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = avatar })
	UIKit.stroke(avatar, GOLD, 7, 0)
	if info.UserId > 0 then
		task.spawn(function()
			avatar.Image = headshot(info.UserId)
		end)
	else
		-- Bot : blason doré de Varek.
		local crest = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(190, 190), Rotation = 45,
			BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 66, Parent = avatar })
		UIKit.corner(crest, 18)
		UIKit.gradient(crest, Color3.fromRGB(255, 225, 140), Color3.fromRGB(190, 120, 40), 90)
		UIKit.stroke(crest, Color3.fromRGB(70, 30, 10), 5, 0)
		local inner = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.72, 0.72),
			BackgroundTransparency = 1, ZIndex = 67, Parent = crest })
		UIKit.corner(inner, 12)
		UIKit.stroke(inner, Color3.fromRGB(110, 55, 15), 2, 0)
		UIKit.label({ Text = "BOT", Font = Enum.Font.Merriweather, TextColor3 = Color3.fromRGB(70, 30, 10), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.5), Rotation = -45, ZIndex = 68, Parent = crest }, 56)
	end
	-- Pseudo en grand, doré, contour sombre.
	local name = UIKit.label({ Text = string.upper(info.Name), Font = Enum.Font.Merriweather, TextColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(0, 412),
		Size = UDim2.new(1, 0, 0, 62), ZIndex = 66, Parent = content }, 52)
	UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 240, 190), Color3.fromRGB(230, 170, 70)), Rotation = 90, Parent = name })
	UIKit.new("UIStroke", { Color = Color3.fromRGB(30, 12, 5), Thickness = 3, Parent = name })
	-- Équipe : une gemme par créature, à la couleur de son élément.
	local team = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 484), Size = UDim2.fromOffset(300, 40),
		ZIndex = 66, Parent = content })
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 18), Parent = team })
	for i, f in ipairs(info.Deck) do
		local card = CardsData.CardById[f.Id]
		local el = card and CardsData.Elements[card.Element]
		local holder = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(34, 34), LayoutOrder = i, ZIndex = 66, Parent = team })
		local gem = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.75, 0.75), Rotation = 45,
			BackgroundColor3 = el and el.Color or color, ZIndex = 67, Parent = holder })
		UIKit.corner(gem, 4)
		UIKit.stroke(gem, GOLD, 2.5, 0)
	end
	content:SetAttribute("Dir", dir)
	return panel, content
end

function DuelScreen:Start(data)
	if self.Arena then
		self.Arena:Destroy()
		self.Arena = nil
	end
	self.Token += 1
	local token = self.Token
	self:Clear()
	self.Stage = nil
	self.PendingTurn = nil
	self.SelectStage = nil
	self.OppState = nil
	self.Data = data
	local root = self.Root
	root.Visible = true
	root.BackgroundTransparency = 1
	UIKit.tween(root, 0.2, { BackgroundTransparency = 0 })

	local intro = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 61, ClipsDescendants = true, Parent = root })
	local slab = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(2.4, 2.4), Rotation = SLANT,
		BackgroundTransparency = 1, ZIndex = 61, Parent = intro })
	local leftPanel, leftContent = side(slab, intro, data.Me, true, BLUE)
	local rightPanel, rightContent = side(slab, intro, data.Opp, false, RED)
	leftContent.Position = UDim2.fromScale(-0.4, 0.54)
	rightContent.Position = UDim2.fromScale(1.4, 0.54)

	-- Bandeau titre.
	local isTraining = data.Opp.UserId <= 0
	local banner = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -80), Size = UDim2.fromOffset(520, 56),
		BackgroundColor3 = Color3.fromRGB(18, 12, 26), ZIndex = 70, Parent = intro })
	UIKit.scaled(banner)
	UIKit.corner(banner, 8)
	UIKit.stroke(banner, GOLD, 3, 0)
	UIKit.label({ Text = isTraining and "ENTRAÎNEMENT" or "DUEL DU COLISÉE", Font = Enum.Font.Merriweather, TextColor3 = GOLD, Size = UDim2.fromScale(1, 1), ZIndex = 71,
		Parent = banner }, 32)

	-- Entrée des deux camps.
	UIKit.playSound("Reveal", 0.5, 0.7)
	UIKit.tween(leftPanel, 0.5, { Position = UDim2.fromScale(0.5, 0) }, Enum.EasingStyle.Quint)
	UIKit.tween(rightPanel, 0.5, { Position = UDim2.fromScale(0.5, 0) }, Enum.EasingStyle.Quint)
	task.wait(0.15)
	UIKit.tween(leftContent, 0.55, { Position = UDim2.fromScale(0.26, 0.54) }, Enum.EasingStyle.Back)
	UIKit.tween(rightContent, 0.55, { Position = UDim2.fromScale(0.74, 0.54) }, Enum.EasingStyle.Back)
	UIKit.tween(banner, 0.5, { Position = UDim2.new(0.5, 0, 0, 24) }, Enum.EasingStyle.Back)
	task.wait(0.5)
	if token ~= self.Token then
		return
	end

	-- Rayon de lumière sur la diagonale.
	local beam = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 0, 2.4, 0), Rotation = SLANT,
		BackgroundColor3 = Color3.fromRGB(255, 235, 170), BorderSizePixel = 0, ZIndex = 68, Parent = intro })
	UIKit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }),
		Parent = beam })
	UIKit.tween(beam, 0.3, { Size = UDim2.new(0, 26, 2.4, 0) }, Enum.EasingStyle.Quad)

	-- Médaillon VS au centre.
	local medal = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(210, 210),
		BackgroundTransparency = 1, ZIndex = 72, Parent = intro })
	UIKit.scaled(medal)
	local ringOuter = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 72, Parent = medal })
	UIKit.corner(ringOuter, 22)
	UIKit.gradient(ringOuter, Color3.fromRGB(255, 225, 140), Color3.fromRGB(175, 105, 30), 90)
	UIKit.stroke(ringOuter, Color3.fromRGB(60, 25, 5), 5, 0)
	local core = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.78, 0.78), Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 73, Parent = medal })
	UIKit.corner(core, 16)
	UIKit.gradient(core, Color3.fromRGB(45, 25, 70), Color3.fromRGB(12, 8, 22), 90)
	UIKit.stroke(core, Color3.fromRGB(255, 235, 170), 2, 0.2)
	local spin = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.35, 1.35),
		BackgroundTransparency = 1, ZIndex = 71, Parent = medal })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = spin })
	local spinStroke = UIKit.stroke(spin, GOLD, 3, 0.2)
	UIKit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0) }),
		Parent = spinStroke })
	local spinConn = RunService.RenderStepped:Connect(function(dt)
		spin.Rotation += dt * 120
	end)
	local vs = UIKit.label({ Text = "VS", Font = Enum.Font.Merriweather, TextColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.6), ZIndex = 75, Parent = medal }, 96)
	UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), Color3.fromRGB(240, 160, 50)), Rotation = 90, Parent = vs })
	UIKit.new("UIStroke", { Color = Color3.fromRGB(40, 15, 5), Thickness = 4, Parent = vs })
	local medalScale = UIKit.new("UIScale", { Scale = 3.5, Parent = medal })
	UIKit.tween(medalScale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
	task.wait(0.2)
	-- Impact : éclair blanc et onde de choc.
	local flash = UIKit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.15, Size = UDim2.fromScale(1, 1), ZIndex = 80, Parent = intro })
	UIKit.tween(flash, 0.5, { BackgroundTransparency = 1 })
	local shock = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(200, 200),
		BackgroundTransparency = 1, ZIndex = 70, Parent = intro })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shock })
	local shockStroke = UIKit.stroke(shock, Color3.fromRGB(255, 235, 170), 8, 0)
	UIKit.tween(shock, 0.6, { Size = UDim2.fromOffset(1400, 1400) }, Enum.EasingStyle.Quad)
	UIKit.tween(shockStroke, 0.6, { Transparency = 1, Thickness = 1 })
	self.Callbacks.Shake(0.9, 0.45)
	UIKit.playSound("Reveal", 0.8, 0.5)
	task.wait(1.4)
	if token ~= self.Token then
		spinConn:Disconnect()
		return
	end

	-- Sortie : les camps repartent, le médaillon disparaît.
	UIKit.tween(leftPanel, 0.35, { Position = UDim2.fromScale(-0.5, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UIKit.tween(rightPanel, 0.35, { Position = UDim2.fromScale(1.5, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UIKit.tween(leftContent, 0.35, { Position = UDim2.fromScale(-0.4, 0.54) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UIKit.tween(rightContent, 0.35, { Position = UDim2.fromScale(1.4, 0.54) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UIKit.tween(medalScale, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	UIKit.tween(beam, 0.3, { BackgroundTransparency = 1 })
	UIKit.tween(banner, 0.3, { Position = UDim2.new(0.5, 0, 0, -80) })
	task.wait(0.4)
	spinConn:Disconnect()
	intro:Destroy()

	-- Entrée en 3D dans le Colisée : chaque duelliste et son Anima.
	local ok, arena = pcall(Arena3D.new, data, self.Callbacks.Shake)
	if ok and arena then
		self.Arena = arena
		UIKit.tween(root, 0.5, { BackgroundTransparency = 1 })
		local played, err = pcall(arena.Entrance, arena)
		if not played then
			warn("[Arena3D]", err)
		end
		if token ~= self.Token then
			return
		end
	else
		if not ok then
			warn("[Arena3D]", arena)
		end
		UIKit.tween(root, 0.3, { BackgroundTransparency = 0.15 })
	end
	self:BuildBattle()
	self:Say("COMBAT !", GOLD, 60)
	UIKit.playSound("Hit", 0.8, 0.8)
end

-------------------------------------------------------------------------------
-- Outils communs
-------------------------------------------------------------------------------
local STRONG = { Feu = "Nature", Nature = "Eau", Eau = "Feu", Foudre = "Eau", Ombre = "Lumiere", Lumiere = "Ombre" }
local ENERGY_MAX = CardsData.Combat.EnergyMax
local ENERGY = Color3.fromRGB(130, 215, 255)
local INK = Color3.fromRGB(14, 10, 24)
local PANEL_LIGHT = Color3.fromRGB(44, 34, 70)
local GREEN = Color3.fromRGB(95, 225, 130)
local MUTED = Color3.fromRGB(90, 75, 130)

local function multiplier(attacker: string, defender: string): number
	if STRONG[attacker] == defender then
		return 1.5
	elseif STRONG[defender] == attacker then
		return 0.75
	end
	return 1
end

local function card(id: string)
	return CardsData.CardById[id]
end

local function elementOf(id: string)
	local c = card(id)
	return c and CardsData.Elements[c.Element] or CardsData.Elements.Feu
end

local function hpColor(ratio: number): Color3
	return ratio > 0.5 and GREEN or (ratio > 0.2 and Color3.fromRGB(255, 200, 70) or Color3.fromRGB(255, 80, 80))
end

-- Panneau sombre, liseré coloré, coins arrondis.
local function plate(parent: Instance, props: { [string]: any }, accent: Color3?, radius: number?): Frame
	props.BackgroundColor3 = Color3.new(1, 1, 1)
	props.Parent = parent
	local f = UIKit.new("Frame", props)
	UIKit.corner(f, radius or 12)
	UIKit.gradient(f, PANEL_LIGHT, INK, 90)
	UIKit.stroke(f, accent or GOLD, 2, 0.15)
	return f
end

local function text(parent: Instance, value: string, props: { [string]: any }, max: number): TextLabel
	props.Text = value
	props.Parent = parent
	props.TextColor3 = props.TextColor3 or CREAM
	props.Font = props.Font or UIKit.Fonts.Black
	return UIKit.label(props, max)
end

local function avatarCircle(parent: Instance, userId: number, size: number, color: Color3, props: { [string]: any }): ImageLabel
	props.Size = UDim2.fromOffset(size, size)
	props.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.5)
	props.Image = ""
	props.Parent = parent
	local img = UIKit.new("ImageLabel", props)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = img })
	UIKit.stroke(img, color, 3, 0)
	if userId > 0 then
		task.spawn(function()
			img.Image = headshot(userId)
		end)
	else
		text(img, "BOT", { Size = UDim2.fromScale(1, 1), TextColor3 = GOLD, ZIndex = (props.ZIndex or 62) + 1 }, 22)
	end
	return img
end

-------------------------------------------------------------------------------
-- 1. Sélection de l'équipe
-------------------------------------------------------------------------------
function DuelScreen:Select(data)
	self.Token += 1
	local token = self.Token
	self:Clear()
	self.Stage = nil
	self.PendingTurn = nil
	local root = self.Root
	root.Visible = true
	root.BackgroundTransparency = 1
	UIKit.tween(root, 0.25, { BackgroundTransparency = 0.12 })

	local stage = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1100, 640), ZIndex = 61, Parent = root })
	UIKit.scaled(stage)
	self.SelectStage = stage

	-- En-tête : titre, adversaire, minuteur.
	local title = text(stage, data.Training and "ENTRAÎNEMENT  •  CHOISIS TON ÉQUIPE" or "DUEL  •  CHOISIS TON ÉQUIPE",
		{ Font = UIKit.Fonts.Title, TextColor3 = GOLD, Size = UDim2.new(1, 0, 0, 44), ZIndex = 62 }, 40)
	UIKit.new("UIStroke", { Color = Color3.fromRGB(40, 15, 5), Thickness = 2, Parent = title })
	text(stage, string.format("Face à %s  •  sélectionne %d créature%s", data.Opp.Name, data.Size, data.Size > 1 and "s" or ""),
		{ Font = UIKit.Fonts.Bold, TextColor3 = UIKit.Colors.SubText, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 22), ZIndex = 62 }, 18)
	local timerTrack = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 76), Size = UDim2.fromOffset(420, 6),
		BackgroundColor3 = INK, ZIndex = 62, Parent = stage })
	UIKit.corner(timerTrack, 3)
	local timer = UIKit.new("Frame", { BackgroundColor3 = GOLD, Size = UDim2.fromScale(1, 1), ZIndex = 63, Parent = timerTrack })
	UIKit.corner(timer, 3)
	UIKit.tween(timer, data.Time, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)

	-- Collection (gauche).
	local library = plate(stage, { Position = UDim2.fromOffset(0, 98), Size = UDim2.fromOffset(720, 542), ZIndex = 61 })
	text(library, "TA COLLECTION", { Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 22), TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GOLD, ZIndex = 62 }, 18)
	local scroll = UIKit.new("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 42), Size = UDim2.new(1, -28, 1, -56),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = GOLD,
		BorderSizePixel = 0, ZIndex = 62, Parent = library })
	UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(124, 172), CellPadding = UDim2.fromOffset(12, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = scroll })

	-- Équipe (droite).
	local teamPanel = plate(stage, { Position = UDim2.fromOffset(740, 98), Size = UDim2.fromOffset(360, 542), ZIndex = 61 })
	text(teamPanel, "TON ÉQUIPE", { Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 22), TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GOLD, ZIndex = 62 }, 18)
	local slotFrames = {}
	for i = 1, 3 do
		local slot = UIKit.new("Frame", { Position = UDim2.fromOffset(16, 44 + (i - 1) * 112), Size = UDim2.new(1, -32, 0, 100), BackgroundColor3 = INK,
			BackgroundTransparency = 0.2, ZIndex = 62, Parent = teamPanel })
		UIKit.corner(slot, 10)
		local stroke = UIKit.stroke(slot, MUTED, 1.5, 0.2)
		local num = text(slot, tostring(i), { Font = UIKit.Fonts.Title, TextColor3 = MUTED, Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(0, 30, 1, 0), ZIndex = 63 }, 32)
		local thumb = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(46, 8), Size = UDim2.fromOffset(60, 84), ZIndex = 63, Parent = slot })
		local name = text(slot, "", { Font = UIKit.Fonts.Bold, TextColor3 = UIKit.Colors.SubText,
			Position = UDim2.fromOffset(118, 18), Size = UDim2.new(1, -128, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 63 }, 18)
		local stats = text(slot, "", { Font = UIKit.Fonts.Bold, TextColor3 = UIKit.Colors.SubText, Position = UDim2.fromOffset(118, 50),
			Size = UDim2.new(1, -128, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 63, RichText = true }, 15)
		slotFrames[i] = { Frame = slot, Stroke = stroke, Num = num, Thumb = thumb, Name = name, Stats = stats }
	end
	local summary = text(teamPanel, "", { Font = UIKit.Fonts.Bold, Position = UDim2.fromOffset(16, 384), Size = UDim2.new(1, -32, 0, 40),
		RichText = true, ZIndex = 62 }, 16)
	local oppState = text(teamPanel, data.Opp.Name .. " choisit son équipe...", { Font = UIKit.Fonts.Bold, TextColor3 = UIKit.Colors.SubText,
		Position = UDim2.fromOffset(16, 428), Size = UDim2.new(1, -32, 0, 22), ZIndex = 62 }, 15)
	self.OppState = oppState
	if data.Training then
		oppState.Text = "Le mannequin s'adaptera à ton équipe."
	end

	local picked: { string } = {}
	local tiles = {}
	local locked = false
	local confirm

	local function refresh()
		local hp, atk = 0, 0
		for i, s in ipairs(slotFrames) do
			for _, c in ipairs(s.Thumb:GetChildren()) do
				c:Destroy()
			end
			local id = picked[i]
			local c = id and card(id)
			if c then
				local el = CardsData.Elements[c.Element]
				CardView.create(c, { Parent = s.Thumb })
				s.Name.Text = c.Name
				s.Name.TextColor3 = CREAM
				s.Stats.Text = string.format('<font color="#%s">%s</font>   ♥ %d   ⚔ %d   <font color="#FFD778">✦ %s</font>', el.Color:ToHex(), el.Label, c.HP, c.Attack, c.Ability.Name)
				s.Stroke.Color = el.Color
				s.Num.TextColor3 = GOLD
				hp += c.HP
				atk += c.Attack
			else
				s.Name.Text = i <= data.Size and "Emplacement libre" or "—"
				s.Name.TextColor3 = UIKit.Colors.SubText
				s.Stats.Text = ""
				s.Stroke.Color = MUTED
				s.Num.TextColor3 = MUTED
			end
		end
		summary.Text = #picked > 0 and string.format("Équipe : <b>♥ %d PV</b>   •   <b>⚔ %d ATQ</b>", hp, atk) or "Touche une carte pour l'ajouter."
		for id, t in pairs(tiles) do
			local index = table.find(picked, id)
			t.Badge.Visible = index ~= nil
			t.BadgeText.Text = index and tostring(index) or ""
			t.Stroke.Transparency = index and 0 or 1
			t.Dim.BackgroundTransparency = (not index and #picked >= data.Size) and 0.5 or 1
		end
		local ready = #picked == data.Size
		confirm.Active = ready and not locked
		UIKit.setDimmed(confirm, not ready or locked)
	end

	for order, entry in ipairs(data.Cards) do
		local c = card(entry.Id)
		if c then
			local tile = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 63, Parent = scroll })
			local view = CardView.create(c, { Parent = tile })
			view.ZIndex = 63
			local stroke = UIKit.stroke(tile, GOLD, 4, 1)
			UIKit.corner(tile, 8)
			local dim = UIKit.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 70, Parent = tile })
			UIKit.corner(dim, 8)
			local badge = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(30, 30),
				BackgroundColor3 = GOLD, Visible = false, ZIndex = 72, Parent = tile })
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = badge })
			UIKit.stroke(badge, INK, 2, 0)
			local badgeText = text(badge, "", { Size = UDim2.fromScale(1, 1), TextColor3 = INK, ZIndex = 73 }, 18)
			if (entry.Count or 1) > 1 then
				text(tile, "x" .. entry.Count, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -4), Size = UDim2.fromOffset(40, 18),
					TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 71 }, 14)
			end
			tiles[entry.Id] = { Badge = badge, BadgeText = badgeText, Stroke = stroke, Dim = dim }
			tile.Activated:Connect(function()
				if locked then
					return
				end
				local index = table.find(picked, entry.Id)
				if index then
					table.remove(picked, index)
				elseif #picked < data.Size then
					table.insert(picked, entry.Id)
				else
					return
				end
				UIKit.playSound("Click", 0.5, index and 0.9 or 1.2)
				refresh()
			end)
		end
	end

	confirm = UIKit.button({ Text = "VALIDER L'ÉQUIPE", Style = "Gold", Position = UDim2.fromOffset(16, 466), Size = UDim2.new(1, -32, 0, 60), TextSize = 22,
		Parent = teamPanel, Callback = function()
			if locked or #picked ~= data.Size then
				return
			end
			locked = true
			refresh()
			task.spawn(function()
				local ok = self.Callbacks.Pick(table.clone(picked))
				if token ~= self.Token then
					return
				end
				if ok then
					summary.Text = summary.Text .. "\n<font color=\"#6EE68C\">✔ Équipe validée</font>"
				else
					locked = false
					refresh()
				end
			end)
		end })
	refresh()
	UIKit.focus(confirm)
end

function DuelScreen:OppReady()
	if self.OppState and self.OppState.Parent then
		self.OppState.Text = "✔ Ton adversaire est prêt !"
		self.OppState.TextColor3 = GREEN
	end
end

-------------------------------------------------------------------------------
-- 2. Arène de combat (épurée : deux cartes, leurs vies, le tour, 3 actions)
-------------------------------------------------------------------------------
local CARD_Y = 290
local SMOOTH = Enum.EasingStyle.Quint

local function hpBar(parent: Instance, props: { [string]: any })
	props.BackgroundColor3 = Color3.fromRGB(10, 8, 18)
	props.BackgroundTransparency = 0.2
	props.Parent = parent
	local track = UIKit.new("Frame", props)
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = track })
	local z = props.ZIndex or 62
	local trail = UIKit.new("Frame", { BackgroundColor3 = Color3.fromRGB(255, 235, 170), Size = UDim2.fromScale(1, 1), ZIndex = z + 1, Parent = track })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = trail })
	local fill = UIKit.new("Frame", { BackgroundColor3 = GREEN, Size = UDim2.fromScale(1, 1), ZIndex = z + 2, Parent = track })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = fill })
	local label = text(parent, "", { AnchorPoint = Vector2.new(0.5, 0), Position = props.Position + UDim2.fromOffset(0, 20),
		Size = UDim2.fromOffset(200, 20), ZIndex = z }, 16)
	return { Track = track, Fill = fill, Trail = trail, Label = label }
end

local function setBar(bar, ratio: number)
	ratio = math.clamp(ratio, 0, 1)
	UIKit.tween(bar.Fill, 0.35, { Size = UDim2.fromScale(ratio, 1), BackgroundColor3 = hpColor(ratio) }, SMOOTH)
	task.delay(0.5, function()
		if bar.Trail.Parent then
			UIKit.tween(bar.Trail, 0.6, { Size = UDim2.fromScale(ratio, 1) }, SMOOTH)
		end
	end)
end

function DuelScreen:BuildBattle()
	local root = self.Root
	local data = self.Data
	local stage = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1100, 640), ZIndex = 61, Parent = root })
	UIKit.scaled(stage)
	self.Stage = stage

	self.Sides = {}
	for _, key in ipairs({ "Me", "Opp" }) do
		local isMe = key == "Me"
		local color = isMe and BLUE or RED
		local info = data[key]
		local x = isMe and 300 or 800

		-- Étiquette discrète du joueur : avatar, pseudo, une pastille par créature.
		local tag = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, 70),
			Size = UDim2.fromOffset(260, 46), ZIndex = 62, Parent = stage })
		avatarCircle(tag, info.UserId, 40, color, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), ZIndex = 63 })
		text(tag, info.Name, { Font = UIKit.Fonts.Bold, Position = UDim2.fromOffset(50, 2), Size = UDim2.new(1, -50, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 63 }, 18)
		local dots = {}
		for i = 1, #info.Deck do
			local d = UIKit.new("Frame", { Position = UDim2.fromOffset(50 + (i - 1) * 20, 28), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = elementOf(info.Deck[i].Id).Color,
				ZIndex = 63, Parent = tag })
			UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = d })
			dots[i] = d
		end
		-- Jauge d'énergie : un losange par point.
		local pips = {}
		for i = 1, ENERGY_MAX do
			local pip = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(132 + (i - 1) * 20, 34), Size = UDim2.fromOffset(11, 11),
				Rotation = 45, BackgroundColor3 = ENERGY, BackgroundTransparency = 0.85, ZIndex = 63, Parent = tag })
			UIKit.stroke(pip, ENERGY, 1, 0.3)
			pips[i] = pip
		end
		-- Statuts de la créature active (icône + tours restants).
		local statusLabel = text(stage, "", { RichText = true, Font = UIKit.Fonts.Bold, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, CARD_Y + 194),
			Size = UDim2.fromOffset(260, 22), ZIndex = 64 }, 17)

		-- Halo coloré derrière la carte (s'illumine pendant son tour).
		local aura = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, CARD_Y), Size = UDim2.fromOffset(300, 300),
			BackgroundColor3 = color, BackgroundTransparency = 1, ZIndex = 62, Parent = stage })
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = aura })
		UIKit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.65, 0.9), NumberSequenceKeypoint.new(1, 1) }),
			Parent = aura })
		local slot = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, CARD_Y),
			Size = UDim2.fromOffset(210, 292), ZIndex = 64, Parent = stage })
		local hp = hpBar(stage, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, CARD_Y + 160), Size = UDim2.fromOffset(220, 12), ZIndex = 64 })
		local guard = text(stage, "EN GARDE", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(x, CARD_Y - 150), Size = UDim2.fromOffset(120, 24),
			BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(70, 150, 255), Visible = false, ZIndex = 75 }, 13)
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = guard })

		self.Sides[key] = { Slot = slot, Aura = aura, Bar = hp, Dots = dots, Guard = guard, Active = 0, Color = color, BaseX = x, Deck = info.Deck,
			Offset = Vector2.zero, Pips = pips, Status = statusLabel, Energy = 0 }
	end

	-- Indicateur de tour (haut, centre) avec minuteur intégré.
	local pill = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(550, 8), Size = UDim2.fromOffset(280, 50),
		BackgroundColor3 = Color3.fromRGB(14, 10, 24), BackgroundTransparency = 0.15, ZIndex = 62, Parent = stage })
	UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = pill })
	self.PillStroke = UIKit.stroke(pill, GOLD, 2, 0.1)
	self.TurnLabel = text(pill, "PRÊTS ?", { Font = UIKit.Fonts.Title, TextColor3 = GOLD, Size = UDim2.new(1, 0, 1, -8), ZIndex = 63 }, 26)
	local track = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -60, 0, 3),
		BackgroundColor3 = Color3.fromRGB(50, 40, 70), BorderSizePixel = 0, ZIndex = 63, Parent = pill })
	self.Timer = UIKit.new("Frame", { BackgroundColor3 = GOLD, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 64, Parent = track })

	-- Légende d'action au centre (apparaît puis s'efface).
	self.Caption = text(stage, "", { Font = UIKit.Fonts.Title, RichText = true, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(550, CARD_Y),
		Size = UDim2.fromOffset(260, 120), TextTransparency = 1, ZIndex = 90 }, 30)
	self.CaptionStroke = UIKit.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 1, Parent = self.Caption })

	-- Plateau d'actions : glisse vers le haut pendant ton tour.
	local tray = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(550, 700),
		Size = UDim2.fromOffset(1060, 96), ZIndex = 62, Parent = stage })
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tray })
	self.Tray = tray
	self.Buttons = {}
	local defs = {
		{ "Attack", "ATTAQUE", "⚔", Color3.fromRGB(255, 110, 85), 210 },
		{ "Defend", "GARDE", "◈", Color3.fromRGB(80, 165, 255), 210 },
		{ "Ability", "CAPACITÉ", "✦", GOLD, 330 },
		{ "Switch", "CHANGER", "⇄", Color3.fromRGB(150, 120, 230), 210 },
	}
	for i, def in ipairs(defs) do
		local button = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(def[5], 84), BackgroundColor3 = Color3.new(1, 1, 1),
			LayoutOrder = i, ZIndex = 63, Selectable = true, Parent = tray })
		UIKit.corner(button, 16)
		UIKit.gradient(button, def[4]:Lerp(Color3.fromRGB(40, 30, 60), 0.35), def[4]:Lerp(Color3.fromRGB(12, 8, 20), 0.7), 90)
		local stroke = UIKit.stroke(button, def[4], 2, 0)
		text(button, def[3], { TextColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(44, 44),
			ZIndex = 64 }, 36)
		local title = text(button, def[2], { Font = UIKit.Fonts.Title, RichText = true, Position = UDim2.fromOffset(66, 12), Size = UDim2.new(1, -76, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 64 }, 24)
		local detail = text(button, "", { Font = UIKit.Fonts.Bold, RichText = true, TextColor3 = Color3.fromRGB(230, 220, 245), Position = UDim2.fromOffset(66, 44),
			Size = UDim2.new(1, -76, 0, 30), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 64 }, 14)
		local scale = UIKit.new("UIScale", { Parent = button })
		button.MouseEnter:Connect(function()
			if button.Active then
				UIKit.tween(scale, 0.15, { Scale = 1.06 }, SMOOTH)
			end
		end)
		button.MouseLeave:Connect(function()
			UIKit.tween(scale, 0.15, { Scale = 1 }, SMOOTH)
		end)
		button.Activated:Connect(function()
			self:Choose(def[1])
		end)
		self.Buttons[def[1]] = { Button = button, Title = title, Detail = detail, Stroke = stroke, Scale = scale }
	end

	-- Choix de la créature qui entre (au-dessus du plateau).
	local bench = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(550, 528), Size = UDim2.fromOffset(560, 96),
		BackgroundColor3 = INK, BackgroundTransparency = 0.1, Visible = false, ZIndex = 70, Parent = stage })
	UIKit.corner(bench, 14)
	UIKit.stroke(bench, Color3.fromRGB(150, 120, 230), 2, 0)
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bench })
	self.Bench = bench
	self.Waiting = nil

	-- Animation continue : les cartes flottent doucement, l'aura respire.
	local t0 = os.clock()
	self.IdleConn = RunService.RenderStepped:Connect(function()
		if not stage.Parent then
			if self.IdleConn then
				self.IdleConn:Disconnect()
			end
			return
		end
		local t = os.clock() - t0
		for key, s in pairs(self.Sides) do
			local phase = key == "Me" and 0 or math.pi
			if s.View and not s.Busy then
				s.Slot.Position = UDim2.fromOffset(s.BaseX, CARD_Y + math.sin(t * 1.6 + phase) * 6)
				s.Slot.Rotation = math.sin(t * 1.1 + phase) * 1.2
			end
		end
	end)

	if self.Arena then
		for _, s in pairs(self.Sides) do
			s.Slot.Visible = false
			s.Aura.Visible = false
		end
	end
	self:SetButtons(false)
	self:UpdateSide("Me", data.Me.Deck)
	self:UpdateSide("Opp", data.Opp.Deck)
	self:SetEnergy("Me", data.MyEnergy)
	self:SetEnergy("Opp", data.OppEnergy)
	if self.PendingTurn then
		self:Turn(self.PendingTurn)
	end
end

-- Index de la créature active d'une équipe (champ Active du serveur, sinon
-- la première encore debout).
local function activeIndexOf(deck): number
	for i, f in ipairs(deck) do
		if f.Active and f.HP > 0 then
			return i
		end
	end
	for i, f in ipairs(deck) do
		if f.HP > 0 then
			return i
		end
	end
	return 0
end

-- Icônes des statuts actifs d'une créature (« 🔥2  ☠3  ◈24 »).
local function statusText(f): string
	if not f then
		return ""
	end
	local parts = {}
	local function add(kind: string, value: any)
		local st = CardsData.Statuses[kind]
		local suffix = type(value) == "number" and tostring(value) or ""
		table.insert(parts, string.format('<font color="#%s">%s%s</font>', st.Color:ToHex(), st.Icon, suffix))
	end
	for _, kind in ipairs({ "Burn", "Poison", "Stun", "Freeze", "Weak", "Rage" }) do
		if (f[kind] or 0) > 0 then
			add(kind, f[kind])
		end
	end
	if (f.Shield or 0) > 0 then
		add("Shield", f.Shield)
	end
	if f.Reflect then
		add("Reflect", true)
	end
	return table.concat(parts, "   ")
end

function DuelScreen:SetEnergy(key: string, value: number?)
	local s = self.Sides and self.Sides[key]
	if not s or value == nil then
		return
	end
	local gained = value > s.Energy
	s.Energy = value
	for i, pip in ipairs(s.Pips) do
		local on = i <= value
		UIKit.tween(pip, 0.25, { BackgroundTransparency = on and 0 or 0.85 })
		if on and gained and i > value - 2 then
			local sc = pip:FindFirstChildOfClass("UIScale") or UIKit.new("UIScale", { Parent = pip })
			sc.Scale = 1.8
			UIKit.tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
end

function DuelScreen:RefreshActions()
	local me, opp = self.Sides.Me, self.Sides.Opp
	local mine = me.Deck[me.Active]
	local target = opp.Deck[opp.Active]
	local c, t = mine and card(mine.Id), target and card(target.Id)
	if not (c and t) then
		return
	end
	local mult = multiplier(c.Element, t.Element)
	local tag = mult > 1 and ' <font color="#7CF59A">×1,5</font>' or (mult < 1 and ' <font color="#FF8080">×0,75</font>' or "")
	local atk = c.Attack * ((mine.Weak or 0) > 0 and CardsData.Combat.WeakFactor or 1) * ((mine.Rage or 0) > 0 and CardsData.Combat.RageFactor or 1)
	local base = math.floor(atk * mult + 0.5)
	self.Buttons.Attack.Detail.Text = string.format("%d dégâts%s  ·  +%d◆", base, tag, CardsData.Combat.EnergyAttack)
	self.Buttons.Defend.Detail.Text = string.format("+%d PV · bloque ½ · +%d◆", math.floor(c.HP * CardsData.Combat.GuardHeal + 0.5), CardsData.Combat.EnergyDefend)
	local ability = c.Ability
	local affordable = me.Energy >= ability.Cost
	self.Buttons.Ability.Title.Text = string.format('%s  <font color="#%s">%d◆</font>', string.upper(ability.Name),
		affordable and "82D7FF" or "FF8080", ability.Cost)
	self.Buttons.Ability.Detail.Text = CardsData.abilityText(ability)
	local benchCount = 0
	for i, f in ipairs(me.Deck) do
		if f.HP > 0 and i ~= me.Active then
			benchCount += 1
		end
	end
	self.Buttons.Switch.Detail.Text = benchCount > 0 and string.format("%d en réserve · prend le tour", benchCount) or "Aucune réserve"
	self.CanAbility = affordable
	self.CanSwitch = benchCount > 0
end

function DuelScreen:SetButtons(enabled: boolean)
	for action, b in pairs(self.Buttons or {}) do
		local on = enabled and (action ~= "Ability" or self.CanAbility == true) and (action ~= "Switch" or self.CanSwitch == true)
		b.Button.Active = on
		UIKit.tween(b.Button, 0.2, { BackgroundTransparency = on and 0 or 0.55 })
		b.Stroke.Transparency = on and 0 or 0.7
		if not on then
			b.Scale.Scale = 1
		end
	end
	self.CanAct = enabled
	if not enabled and self.Bench then
		self.Bench.Visible = false
	end
end

-- Plateau d'actions : visible uniquement pendant ton tour.
function DuelScreen:ShowTray(visible: boolean)
	if self.Tray then
		UIKit.tween(self.Tray, 0.45, { Position = UDim2.fromOffset(550, visible and 536 or 700) }, SMOOTH)
	end
	if not visible and self.Bench then
		self.Bench.Visible = false
	end
end

-- Liste des créatures de réserve ; un clic les fait entrer.
function DuelScreen:OpenBench()
	local bench = self.Bench
	if bench.Visible then
		bench.Visible = false
		return
	end
	for _, child in ipairs(bench:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local me, opp = self.Sides.Me, self.Sides.Opp
	local target = opp.Deck[opp.Active]
	local t = target and card(target.Id)
	for i, f in ipairs(me.Deck) do
		local c = card(f.Id)
		if c and f.HP > 0 and i ~= me.Active then
			local el = CardsData.Elements[c.Element]
			local mult = t and multiplier(c.Element, t.Element) or 1
			local hint = mult > 1 and '  <font color="#7CF59A">fort ×1,5</font>' or (mult < 1 and '  <font color="#FF8080">faible ×0,75</font>' or "")
			local b = UIKit.new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(260, 76), BackgroundColor3 = el.Dark,
				LayoutOrder = i, ZIndex = 71, Selectable = true, Parent = bench })
			UIKit.corner(b, 12)
			UIKit.stroke(b, el.Color, 2, 0)
			text(b, c.Name, { Font = UIKit.Fonts.Title, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 26),
				TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 72 }, 22)
			text(b, string.format('<font color="#%s">%s</font>  ♥ %d/%d%s', el.Color:ToHex(), el.Label, f.HP, f.MaxHP, hint),
				{ Font = UIKit.Fonts.Bold, RichText = true, Position = UDim2.fromOffset(14, 40), Size = UDim2.new(1, -28, 0, 22),
					TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 72 }, 15)
			b.Activated:Connect(function()
				if self.CanAct then
					bench.Visible = false
					self:SetButtons(false)
					self:ShowTray(false)
					UIKit.playSound("Click", 0.6, 1)
					self.Callbacks.Act("Switch:" .. i)
				end
			end)
		end
	end
	bench.Visible = true
end

function DuelScreen:Choose(action: string)
	if not self.CanAct or (action == "Ability" and not self.CanAbility) or (action == "Switch" and not self.CanSwitch) then
		return
	end
	local b = self.Buttons[action]
	UIKit.tween(b.Scale, 0.08, { Scale = 0.92 }).Completed:Once(function()
		UIKit.tween(b.Scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	UIKit.playSound("Click", 0.6, 1.1)
	if action == "Switch" then
		self:OpenBench()
		return
	end
	self:SetButtons(false)
	self:ShowTray(false)
	self.Callbacks.Act(action)
end

function DuelScreen:UpdateSide(key: string, deck)
	local s = self.Sides[key]
	s.Deck = deck
	local activeIndex = activeIndexOf(deck)
	for i, f in ipairs(deck) do
		local d = s.Dots[i]
		if d then
			UIKit.tween(d, 0.3, { BackgroundTransparency = f.HP > 0 and 0 or 0.8, Size = i == activeIndex and UDim2.fromOffset(14, 14) or UDim2.fromOffset(12, 12) })
		end
	end
	if activeIndex ~= s.Active then
		local previous = s.View
		local previousFighter = s.Active > 0 and deck[s.Active]
		local knockedOut = previousFighter == nil or previousFighter.HP <= 0
		s.Active = activeIndex
		if previous then
			s.Busy = true
			local dir = key == "Me" and -1 or 1
			local holder = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = s.Slot.Position,
				Size = s.Slot.Size, ZIndex = 63, Parent = s.Slot.Parent })
			previous.Parent = holder
			if knockedOut then
				-- K.O. : la carte bascule, tombe et s'efface.
				UIKit.tween(holder, 0.6, { Rotation = 30 * dir, Position = s.Slot.Position + UDim2.fromOffset(60 * dir, 140) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			else
				-- Changement : la carte recule vers sa réserve.
				UIKit.tween(holder, 0.45, { Rotation = -8 * dir, Position = s.Slot.Position + UDim2.fromOffset(260 * dir, -40) }, Enum.EasingStyle.Quint)
			end
			task.delay(0.6, function()
				holder:Destroy()
				s.Busy = false
			end)
		end
		local f = deck[activeIndex]
		local c = f and card(f.Id)
		if self.Arena then
			self.Arena:SetActive(key, c and c.Id, knockedOut)
		end
		if c then
			local view = CardView.create(c, { Detailed = true, Parent = s.Slot })
			view.ZIndex = 65
			local scale = UIKit.new("UIScale", { Scale = 0, Parent = view })
			task.delay(previous and 0.45 or 0, function()
				UIKit.tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
			s.View = view
			s.Aura.BackgroundColor3 = CardsData.Elements[c.Element].Color
		else
			s.View = nil
		end
	end
	local f = deck[activeIndex]
	if f then
		setBar(s.Bar, f.HP / f.MaxHP)
		s.Bar.Label.Text = string.format("%d / %d", f.HP, f.MaxHP)
		s.Guard.Visible = f.Guard == true
		s.Status.Text = statusText(f)
	else
		setBar(s.Bar, 0)
		s.Bar.Label.Text = "K.O."
		s.Guard.Visible = false
		s.Status.Text = ""
	end
end

-- Texte central bref (« TON TOUR », « Super efficace ! », « K.O. ! »).
function DuelScreen:Say(value: string, color: Color3, size: number?)
	local c = self.Caption
	if not c then
		return
	end
	c.Text = value
	c.TextColor3 = color
	local constraint = c:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint then
		constraint.MaxTextSize = size or 30
	end
	c.TextTransparency = 1
	self.CaptionStroke.Transparency = 1
	local scale = c:FindFirstChildOfClass("UIScale") or UIKit.new("UIScale", { Parent = c })
	scale.Scale = 0.6
	UIKit.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	UIKit.tween(c, 0.2, { TextTransparency = 0 })
	UIKit.tween(self.CaptionStroke, 0.2, { Transparency = 0.2 })
	task.delay(1.1, function()
		if c.Parent and c.Text == value then
			UIKit.tween(c, 0.35, { TextTransparency = 1 })
			UIKit.tween(self.CaptionStroke, 0.35, { Transparency = 1 })
		end
	end)
end

function DuelScreen:Turn(data)
	if not self.Stage then
		self.PendingTurn = data
		return
	end
	self.PendingTurn = nil
	self:UpdateSide("Me", data.Me)
	self:UpdateSide("Opp", data.Opp)
	self:SetEnergy("Me", data.MyEnergy)
	self:SetEnergy("Opp", data.OppEnergy)
	local mine = data.Mine
	local oppColor = RED:Lerp(Color3.new(1, 1, 1), 0.35)
	local accent = mine and GOLD or oppColor
	self.TurnLabel.Text = mine and "TON TOUR" or ("TOUR DE " .. string.upper(data.ActiveName))
	UIKit.tween(self.TurnLabel, 0.3, { TextColor3 = accent })
	UIKit.tween(self.PillStroke, 0.3, { Color = accent })
	self.Timer.BackgroundColor3 = accent
	self.Timer.Size = UDim2.fromScale(1, 1)
	UIKit.tween(self.Timer, data.Time, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	for key, s in pairs(self.Sides) do
		local on = (key == "Me") == mine
		UIKit.tween(s.Aura, 0.5, { BackgroundTransparency = on and 0 or 1, Size = on and UDim2.fromOffset(380, 380) or UDim2.fromOffset(300, 300) }, SMOOTH)
	end
	self:RefreshActions()
	self:SetButtons(mine)
	self:ShowTray(mine)
	if mine then
		UIKit.playSound("Click", 0.5, 1.4)
		UIKit.focus(self.Buttons.Attack.Button)
	end
end

-- Nombre qui jaillit de la carte touchée.
local function popNumber(parent: Instance, value: string, color: Color3, big: boolean?)
	local l = text(parent, value, { Font = UIKit.Fonts.Title, TextColor3 = color, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(220, 80), ZIndex = 85 }, big and 76 or 60)
	UIKit.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3, Parent = l })
	local scale = UIKit.new("UIScale", { Scale = 1.8, Parent = l })
	UIKit.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	UIKit.tween(l, 0.9, { Position = UDim2.fromScale(0.5, 0.1), TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.5)
	task.delay(1.5, function()
		l:Destroy()
	end)
end

local EFFECT_SAY = {
	Burn = "BRÛLURE !",
	Poison = "EMPOISONNÉ !",
	Stun = "ÉTOURDI !",
	Freeze = "GELÉ !",
	Weak = "AFFAIBLI !",
	Rage = "RAGE !",
	Shield = "BOUCLIER !",
	Reflect = "MIROIR !",
	Cleanse = "PURIFIÉ !",
}

-- Anneau qui s'élargit autour d'une carte (garde, bouclier, soin).
local function ring(slot: Instance, color: Color3)
	local r = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, ZIndex = 84, Parent = slot })
	UIKit.corner(r, 18)
	local st = UIKit.stroke(r, color, 6, 0)
	UIKit.tween(r, 0.7, { Size = UDim2.fromScale(1.35, 1.25) }, SMOOTH)
	UIKit.tween(st, 0.7, { Transparency = 1 })
	task.delay(0.8, function()
		r:Destroy()
	end)
end

function DuelScreen:Resolve(data)
	if not self.Stage then
		return
	end
	self:SetButtons(false)
	self:ShowTray(false)
	local myId = Players.LocalPlayer.UserId
	local token = self.Token
	local function apply()
		if self.Stage and self.Token == token then
			self:UpdateSide("Me", data.Me)
			self:UpdateSide("Opp", data.Opp)
			self:SetEnergy("Me", data.MyEnergy)
			self:SetEnergy("Opp", data.OppEnergy)
			self:RefreshActions()
		end
	end
	local cinematic = false
	for _, e in ipairs(data.Events) do
		local mine = e.From == myId
		local actorKey = mine and "Me" or "Opp"
		local actor = self.Sides[actorKey]
		local target = self.Sides[mine and "Opp" or "Me"]
		local arena = self.Arena
		if e.Action == "Tick" then
			-- Brûlure ou poison en début de tour.
			local st = CardsData.Statuses[e.Status]
			if arena then
				arena:Tick(actorKey, st.Color, st.Icon .. " -" .. e.Damage)
			end
			popNumber(actor.Slot, st.Icon .. " -" .. e.Damage, st.Color)
			if actor.View then
				local tint = UIKit.new("Frame", { BackgroundColor3 = st.Color, BackgroundTransparency = 0.4, Size = UDim2.fromScale(1, 1), ZIndex = 83, Parent = actor.Slot })
				UIKit.corner(tint, 12)
				UIKit.tween(tint, 0.6, { BackgroundTransparency = 1 })
				task.delay(0.65, function()
					tint:Destroy()
				end)
			end
			self:Say(string.upper(st.Label), st.Color)
			UIKit.playSound("Burst", 0.4, e.Status == "Burn" and 1.1 or 0.7)
			self.Callbacks.Shake(0.15, 0.2)
		elseif e.Action == "Stunned" then
			local st = CardsData.Statuses[e.Status]
			self:Say(st.Icon .. " " .. string.upper(st.Label) .. " : tour perdu", st.Color, 34)
			ring(actor.Slot, st.Color)
		elseif e.Action == "Switch" then
			self:Say("⇄ CHANGEMENT", Color3.fromRGB(190, 170, 255))
			UIKit.playSound("Swoosh", 0.5, 1.2)
		elseif e.Action == "Defend" then
			if arena then
				arena:Guard(actorKey, "+" .. (e.Heal or 0))
			end
			popNumber(actor.Slot, "+" .. (e.Heal or 0), GREEN)
			ring(actor.Slot, Color3.fromRGB(120, 195, 255))
			self:Say("GARDE", Color3.fromRGB(130, 200, 255))
			UIKit.playSound("Click", 0.6, 0.8)
		elseif e.Action == "Ability" and not e.Hits then
			-- Capacité sans attaque : soin, bouclier, miroir...
			self:Say("✦ " .. string.upper(e.Ability or ""), GOLD, 36)
			UIKit.playSound("Charge", 0.6, 1.1)
			ring(actor.Slot, GOLD)
			if arena then
				if (e.Heal or 0) > 0 then
					arena:Buff(actorKey, "+" .. e.Heal)
				elseif e.Shield then
					arena:Buff(actorKey, "◈ " .. e.Shield, Color3.fromRGB(120, 200, 255))
				else
					arena:Buff(actorKey)
				end
			end
			if (e.Heal or 0) > 0 then
				popNumber(actor.Slot, "+" .. e.Heal, GREEN)
			elseif e.Shield then
				popNumber(actor.Slot, "◈ " .. e.Shield, Color3.fromRGB(120, 200, 255))
			end
			local effects = e.Effects or {}
			if effects[1] and EFFECT_SAY[effects[#effects]] then
				task.delay(1, function()
					if self.Stage and self.Token == token then
						self:Say(EFFECT_SAY[effects[#effects]], GOLD)
					end
				end)
			end
		elseif arena then
			-- Attaque ou capacité offensive, mise en scène dans le Colisée 3D.
			cinematic = true
			if e.Action == "Ability" then
				self:Say("✦ " .. string.upper(e.Ability or ""), GOLD, 40)
			end
			task.spawn(function()
				local ok, err = pcall(arena.Attack, arena, actorKey, e)
				if not ok then
					warn("[Arena3D]", err)
				end
				if self.Stage and self.Token == token then
					apply()
					local verdict, color
					if e.KO then
						verdict, color = "K.O. !", Color3.fromRGB(255, 90, 90)
					elseif e.Execute then
						verdict, color = "EXÉCUTION !", Color3.fromRGB(255, 120, 200)
					elseif e.Effects and e.Effects[1] and EFFECT_SAY[e.Effects[1]] then
						verdict, color = EFFECT_SAY[e.Effects[1]], CardsData.Statuses[e.Effects[1]].Color
					elseif (e.Reflected or 0) > 0 then
						verdict, color = "RENVOYÉ !", Color3.fromRGB(200, 240, 255)
					elseif e.Mult > 1 then
						verdict, color = "Super efficace !", Color3.fromRGB(124, 245, 154)
					elseif e.Blocked then
						verdict, color = "Paré !", Color3.fromRGB(130, 200, 255)
					elseif e.Mult < 1 then
						verdict, color = "Peu efficace...", Color3.fromRGB(200, 190, 220)
					end
					if verdict then
						self:Say(verdict, color, e.KO and 56 or 40)
					end
					if (e.Heal or 0) > 0 then
						arena:Number(actorKey, "+" .. e.Heal, GREEN)
					end
				end
			end)
		else
			-- Attaque ou capacité offensive : vraie cinématique plein écran.
			local atkFighter = actor.Deck[actor.Active]
			local tgtFighter = target.Deck[target.Active]
			local atkCard = atkFighter and card(atkFighter.Id)
			local tgtCard = tgtFighter and card(tgtFighter.Id)
			if atkCard and tgtCard then
				cinematic = true
				self.Tray.Visible = false
				task.spawn(function()
					local ok, err = pcall(DuelCinematic.play, {
						Parent = self.Root,
						Mine = mine,
						AttackerId = atkCard.Id,
						TargetId = tgtCard.Id,
						AttackerElement = atkCard.Element,
						TargetElement = tgtCard.Element,
						Event = e,
						Shake = self.Callbacks.Shake,
						Alive = function()
							return self.Stage ~= nil and self.Token == token
						end,
					})
					if not ok then
						warn("[DuelCinematic]", err)
						local leftover = self.Root:FindFirstChild("Cinematic")
						if leftover then
							leftover:Destroy()
						end
					end
					if self.Stage and self.Token == token then
						self.Tray.Visible = true
						apply()
						if (e.Reflected or 0) > 0 then
							popNumber(actor.Slot, "◇ -" .. e.Reflected, Color3.fromRGB(200, 240, 255))
						end
						if (e.Heal or 0) > 0 then
							popNumber(actor.Slot, "+" .. e.Heal, GREEN)
						end
						if e.KO then
							self:Say("K.O. !", Color3.fromRGB(255, 90, 90), 56)
						end
					end
				end)
			end
		end
	end
	if not cinematic then
		task.delay(0.5, apply)
	end
end

function DuelScreen:Result(data)
	if not (self.Stage or self.SelectStage) then
		return
	end
	self:SetButtons(false)
	if self.Waiting then
		self.Waiting.Visible = false
	end
	local win = data.Outcome == "Win"
	local draw = data.Outcome == "Draw"
	local veil = UIKit.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 95, Parent = self.Root })
	UIKit.tween(veil, 0.4, { BackgroundTransparency = 0.45 })
	local banner = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 250),
		BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 96, Parent = self.Root })
	UIKit.scaled(banner)
	UIKit.corner(banner, 18)
	local color = draw and Color3.fromRGB(150, 140, 170) or (win and GOLD or RED)
	UIKit.gradient(banner, color:Lerp(Color3.new(0, 0, 0), 0.45), INK, 90)
	UIKit.stroke(banner, color, 4, 0)
	local title = text(banner, draw and "ÉGALITÉ" or (win and "VICTOIRE !" or "DÉFAITE"), { Font = UIKit.Fonts.Title, TextColor3 = color,
		Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 96), ZIndex = 97 }, 88)
	UIKit.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3, Parent = title })
	local training = self.Data == nil or self.Data.Opp.UserId <= 0
	local rewardText = training and "Entraînement : pas de gemmes en jeu."
		or (draw and "+60 ◆" or (win and "+150 ◆" or "+30 ◆ pour ta participation"))
	text(banner, data.Reason, { Font = UIKit.Fonts.Bold, Position = UDim2.fromOffset(20, 130), Size = UDim2.new(1, -40, 0, 30), ZIndex = 97 }, 22)
	text(banner, rewardText, { TextColor3 = GOLD, Position = UDim2.fromOffset(20, 170), Size = UDim2.new(1, -40, 0, 40), ZIndex = 97 }, 30)
	local scale = UIKit.new("UIScale", { Scale = 0.3, Parent = banner })
	UIKit.tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	UIKit.playSound("Reveal", 0.7, win and 1.2 or 0.7)
	if win then
		self.Callbacks.Shake(0.4, 0.3)
	end
end

function DuelScreen:Close()
	if self.Arena then
		self.Arena:Destroy()
		self.Arena = nil
	end
	self.Token += 1
	self.Stage = nil
	self.SelectStage = nil
	UIKit.tween(self.Root, 0.3, { BackgroundTransparency = 1 })
	task.delay(0.3, function()
		if not self.Stage and not self.SelectStage then
			self:Clear()
			self.Root.Visible = false
		end
	end)
end

return DuelScreen
