-- Cinématique plein écran d'une attaque de duel :
--   1. bandes cinéma + fond aux couleurs de l'élément, lignes de vitesse ;
--   2. l'attaquant entre en grand, bannière « nom + attaque » ;
--   3. charge à travers l'écran avec traînée ;
--   4. coupe sur la cible : flash, onde de choc, éclats de l'élément,
--      recul, chiffre de dégâts géant et verdict (super efficace, K.O...) ;
--   5. sortie en fondu, retour à l'arène.
-- Les spéciaux sont plus longs : charge d'énergie, ralenti, double impact.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local CardView = require(script.Parent:WaitForChild("CardView"))

local DuelCinematic = {}

local W, H = 1366, 768
local GOLD = Color3.fromRGB(255, 215, 120)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local CARD_W, CARD_H = 300, 438

-- Durées (le serveur attend un peu plus longtemps, voir DuelCombat).
DuelCinematic.Duration = { Attack = 2.4, Special = 3.1 }

-- Style des éclats par élément.
local VFX = {
	Feu = { Shape = "Ember", Extra = Color3.fromRGB(255, 220, 90) },
	Eau = { Shape = "Wave", Extra = Color3.fromRGB(200, 240, 255) },
	Nature = { Shape = "Leaf", Extra = Color3.fromRGB(200, 255, 140) },
	Foudre = { Shape = "Bolt", Extra = WHITE },
	Ombre = { Shape = "Void", Extra = Color3.fromRGB(40, 10, 70) },
	Lumiere = { Shape = "Ray", Extra = WHITE },
}

local function new(class: string, props)
	return UIKit.new(class, props)
end

local function round(inst: Instance, r: number?)
	new("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(0.5, 0), Parent = inst })
end

local function wait(t: number, alive: () -> boolean): boolean
	local stop = os.clock() + t
	while os.clock() < stop do
		if not alive() then
			return false
		end
		task.wait()
	end
	return alive()
end

-- Lignes de vitesse qui défilent horizontalement (direction dir).
local function speedLines(parent: Instance, dir: number, color: Color3, z: number)
	local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = z, Parent = parent })
	local lines = {}
	for i = 1, 26 do
		local l = new("Frame", { BackgroundColor3 = i % 3 == 0 and WHITE or color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(math.random(120, 420), math.random(2, 5)), BackgroundTransparency = math.random(30, 70) / 100, ZIndex = z, Parent = holder })
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }),
			Parent = l })
		lines[i] = { Frame = l, X = math.random() * (W + 800) - 400, Y = math.random() * H, Speed = math.random(2200, 4200) }
	end
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not holder.Parent then
			conn:Disconnect()
			return
		end
		for _, line in ipairs(lines) do
			line.X -= line.Speed * dt * dir
			if dir > 0 and line.X < -400 then
				line.X, line.Y = W + 400, math.random() * H
			elseif dir < 0 and line.X > W + 400 then
				line.X, line.Y = -400, math.random() * H
			end
			line.Frame.Position = UDim2.fromOffset(line.X, line.Y)
		end
	end)
	return holder
end

-- Éclats radiaux typés selon l'élément.
local function burst(parent: Instance, center: Vector2, element: string, power: number, z: number)
	local el = CardsData.Elements[element] or CardsData.Elements.Feu
	local vfx = VFX[element] or VFX.Feu
	local count = math.floor(22 * power)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.4
		local dist = math.random(160, 360) * power
		local color = math.random() < 0.35 and vfx.Extra or el.Color
		local size, rot
		if vfx.Shape == "Bolt" or vfx.Shape == "Ray" then
			size = UDim2.fromOffset(math.random(60, 140), vfx.Shape == "Ray" and 6 or 4)
			rot = math.deg(angle)
		elseif vfx.Shape == "Leaf" then
			size = UDim2.fromOffset(math.random(14, 24), math.random(8, 12))
			rot = math.random(0, 360)
		else
			local s = math.random(10, 26)
			size = UDim2.fromOffset(s, s)
			rot = 45
		end
		local p = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(center.X, center.Y), Size = size, Rotation = rot,
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z, Parent = parent })
		if vfx.Shape == "Ember" or vfx.Shape == "Wave" or vfx.Shape == "Void" then
			round(p)
		elseif vfx.Shape == "Leaf" then
			round(p, 6)
		end
		local target = center + Vector2.new(math.cos(angle), math.sin(angle)) * dist
		if vfx.Shape == "Ember" then
			target -= Vector2.new(0, math.random(40, 140)) -- les braises montent
		end
		local dur = math.random(45, 80) / 100
		UIKit.tween(p, dur, { Position = UDim2.fromOffset(target.X, target.Y), BackgroundTransparency = 1, Rotation = rot + math.random(-120, 120),
			Size = vfx.Shape == "Void" and UDim2.fromOffset(60, 60) or size }, Enum.EasingStyle.Quint)
		task.delay(dur + 0.05, function()
			p:Destroy()
		end)
	end
	-- Onde(s) de choc.
	for k = 1, (vfx.Shape == "Wave" and 3 or 1) + (power > 1.2 and 1 or 0) do
		local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(center.X, center.Y), Size = UDim2.fromOffset(40, 40),
			BackgroundTransparency = 1, ZIndex = z, Parent = parent })
		round(ring)
		local st = new("UIStroke", { Color = k == 1 and WHITE or el.Color, Thickness = 10, Parent = ring })
		local delayT = (k - 1) * 0.1
		task.delay(delayT, function()
			if ring.Parent then
				UIKit.tween(ring, 0.55, { Size = UDim2.fromOffset(620 * power, 620 * power) }, Enum.EasingStyle.Quint)
				UIKit.tween(st, 0.55, { Transparency = 1, Thickness = 1 })
			end
		end)
		task.delay(delayT + 0.6, function()
			ring:Destroy()
		end)
	end
	-- Éclairs en zigzag pour la Foudre.
	if vfx.Shape == "Bolt" then
		for _ = 1, 4 do
			local x = center.X + math.random(-200, 200)
			local y = 0
			while y < center.Y do
				local len = math.random(40, 90)
				local a = math.random(-35, 35)
				local seg = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(5, len), Rotation = a,
					BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = z, Parent = parent })
				new("UIStroke", { Color = el.Color, Thickness = 3, Parent = seg })
				UIKit.tween(seg, 0.35, { BackgroundTransparency = 1 })
				task.delay(0.4, function()
					seg:Destroy()
				end)
				x += math.sin(math.rad(-a)) * len
				y += math.cos(math.rad(a)) * len
			end
		end
	end
end

local function flash(parent: Instance, color: Color3, alpha: number, dur: number, z: number)
	local f = new("Frame", { BackgroundColor3 = color, BackgroundTransparency = alpha, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = parent })
	UIKit.tween(f, dur, { BackgroundTransparency = 1 })
	task.delay(dur + 0.05, function()
		f:Destroy()
	end)
end

local function bigCard(parent: Instance, cardId: string, z: number): (Frame, UIScale)
	local holder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(CARD_W, CARD_H), ZIndex = z, Parent = parent })
	local c = CardsData.CardById[cardId]
	if c then
		local view = CardView.create(c, { Detailed = true, Parent = holder })
		view.ZIndex = z
	end
	local scale = new("UIScale", { Parent = holder })
	return holder, scale
end

local function cardName(cardId: string): string
	local c = CardsData.CardById[cardId]
	return c and c.Name or "?"
end

--[[ Joue la cinématique. options :
	Parent      : Frame plein écran (racine du duel)
	Mine        : true si l'attaquant est le joueur local
	AttackerId, TargetId, AttackerElement, TargetElement : cartes en jeu
	Event       : { Action, Damage, Mult, KO, Blocked }
	Shake       : (intensité, durée) -> ()
	Alive       : () -> boolean   (false si le duel a été fermé)
	Bloque jusqu'à la fin de la séquence. ]]
function DuelCinematic.play(options)
	local e = options.Event
	local special = e.Action == "Special"
	local alive = options.Alive
	local dir = options.Mine and 1 or -1 -- 1 : on attaque vers la droite
	local atkEl = CardsData.Elements[options.AttackerElement] or CardsData.Elements.Feu
	local tgtEl = CardsData.Elements[options.TargetElement] or CardsData.Elements.Feu
	local Z = 120

	local root = new("Frame", { Name = "Cinematic", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z, Active = true, Parent = options.Parent })
	-- Fond : dégradé de l'élément de l'attaquant.
	local bg = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = Z, Parent = root })
	local bgGrad = new("UIGradient", { Color = ColorSequence.new(atkEl.Dark, BLACK), Rotation = dir > 0 and 0 or 180, Parent = bg })
	-- Scène à taille fixe mise à l'échelle de l'écran.
	local stage = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H), ZIndex = Z + 1, Parent = root })
	local camera = workspace.CurrentCamera
	local stageScale = new("UIScale", { Parent = stage })
	local function fit()
		local v = camera and camera.ViewportSize or Vector2.new(W, H)
		stageScale.Scale = math.max(v.X / W, v.Y / H)
	end
	fit()
	-- Bandes cinéma (hors scène pour toujours couvrir les bords).
	local bars = {}
	for i, y in ipairs({ 0, 1 }) do
		local bar = new("Frame", { BackgroundColor3 = BLACK, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, y), Position = UDim2.fromScale(0, y),
			Size = UDim2.fromScale(1, 0), ZIndex = Z + 40, Parent = root })
		bars[i] = bar
		UIKit.tween(bar, 0.25, { Size = UDim2.fromScale(1, 0.12) }, Enum.EasingStyle.Quint)
	end
	UIKit.tween(bg, 0.25, { BackgroundTransparency = 0.05 })
	local function cleanup()
		root:Destroy()
	end

	-- 1. Entrée de l'attaquant ---------------------------------------------
	local lines = speedLines(stage, dir, atkEl.Color, Z + 2)
	local startX = dir > 0 and -CARD_W or W + CARD_W
	local poseX = dir > 0 and W * 0.36 or W * 0.64
	local attacker, atkScale = bigCard(stage, options.AttackerId, Z + 10)
	attacker.Position = UDim2.fromOffset(startX, H * 0.52)
	attacker.Rotation = -12 * dir
	atkScale.Scale = 1.15
	UIKit.tween(attacker, 0.38, { Position = UDim2.fromOffset(poseX, H * 0.5), Rotation = -4 * dir }, Enum.EasingStyle.Quint)
	UIKit.playSound("Swoosh", 0.6, special and 0.8 or 1.1)

	-- Bannière : nom de la créature + attaque.
	local banner = new("Frame", { AnchorPoint = Vector2.new(dir > 0 and 0 or 1, 0.5), Position = UDim2.fromOffset(dir > 0 and W or 0, H * 0.24),
		Size = UDim2.fromOffset(560, 92), BackgroundColor3 = WHITE, Rotation = -3 * dir, ZIndex = Z + 20, Parent = stage })
	new("UIGradient", { Color = ColorSequence.new(special and GOLD or atkEl.Color, atkEl.Dark), Rotation = dir > 0 and 0 or 180, Parent = banner })
	new("UIStroke", { Color = special and GOLD or WHITE, Thickness = 3, Parent = banner })
	UIKit.label({ Text = string.upper(cardName(options.AttackerId)), Font = UIKit.Fonts.Title, TextColor3 = WHITE, Position = UDim2.fromOffset(24, 6),
		Size = UDim2.new(1, -48, 0, 52), TextXAlignment = dir > 0 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, ZIndex = Z + 21, Parent = banner }, 48)
	UIKit.label({ Text = special and "✦  COUP SPÉCIAL  ✦" or "⚔  ATTAQUE", Font = UIKit.Fonts.Black, TextColor3 = special and Color3.fromRGB(255, 245, 200) or WHITE,
		Position = UDim2.fromOffset(24, 56), Size = UDim2.new(1, -48, 0, 28), TextXAlignment = dir > 0 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
		ZIndex = Z + 21, Parent = banner }, 24)
	for _, l in ipairs(banner:GetDescendants()) do
		if l:IsA("TextLabel") then
			new("UIStroke", { Color = BLACK, Thickness = 2, Transparency = 0.2, Parent = l })
		end
	end
	UIKit.tween(banner, 0.35, { Position = UDim2.fromOffset(dir > 0 and W * 0.5 or W * 0.5, H * 0.24) }, Enum.EasingStyle.Back)

	if special then
		-- Charge d'énergie : anneaux qui convergent, carte qui grossit, ralenti.
		if not wait(0.35, alive) then
			return cleanup()
		end
		UIKit.playSound("Charge", 0.7, 1)
		for k = 1, 3 do
			local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(poseX, H * 0.5), Size = UDim2.fromOffset(900, 900),
				BackgroundTransparency = 1, ZIndex = Z + 9, Parent = stage })
			round(ring)
			local st = new("UIStroke", { Color = k == 2 and WHITE or GOLD, Thickness = 4, Transparency = 0.8, Parent = ring })
			task.delay((k - 1) * 0.15, function()
				if ring.Parent then
					UIKit.tween(ring, 0.4, { Size = UDim2.fromOffset(CARD_W, CARD_W) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					UIKit.tween(st, 0.4, { Transparency = 0, Thickness = 10 })
				end
			end)
			task.delay((k - 1) * 0.15 + 0.42, function()
				ring:Destroy()
			end)
		end
		UIKit.tween(atkScale, 0.7, { Scale = 1.35 }, Enum.EasingStyle.Quad)
		options.Shake(0.15, 0.7)
		if not wait(0.75, alive) then
			return cleanup()
		end
		flash(root, GOLD, 0.3, 0.3, Z + 30)
	else
		if not wait(0.55, alive) then
			return cleanup()
		end
	end

	-- 2. Élan puis charge à travers l'écran ---------------------------------
	UIKit.tween(attacker, 0.12, { Position = UDim2.fromOffset(poseX - 50 * dir, H * 0.5), Rotation = -10 * dir }, Enum.EasingStyle.Quad)
	if not wait(0.13, alive) then
		return cleanup()
	end
	UIKit.playSound("Swoosh", 0.8, 0.9)
	-- Traînée : copies fantômes qui s'estompent.
	for k = 1, 4 do
		task.delay(k * 0.03, function()
			if not stage.Parent then
				return
			end
			local ghost = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = attacker.Position, Size = UDim2.fromOffset(CARD_W * atkScale.Scale, CARD_H * atkScale.Scale),
				Rotation = attacker.Rotation, BackgroundColor3 = atkEl.Color, BackgroundTransparency = 0.4, ZIndex = Z + 8, Parent = stage })
			round(ghost, 14)
			UIKit.tween(ghost, 0.3, { BackgroundTransparency = 1 })
			task.delay(0.32, function()
				ghost:Destroy()
			end)
		end)
	end
	UIKit.tween(attacker, 0.18, { Position = UDim2.fromOffset(dir > 0 and W + CARD_W * 1.2 or -CARD_W * 1.2, H * 0.5), Rotation = 6 * dir },
		Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UIKit.tween(banner, 0.2, { Position = UDim2.fromOffset(dir > 0 and -600 or W + 600, H * 0.24) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if not wait(0.18, alive) then
		return cleanup()
	end
	attacker:Destroy()
	banner:Destroy()
	lines:Destroy()

	-- 3. Coupe sur la cible : impact ----------------------------------------
	bgGrad.Color = ColorSequence.new(tgtEl.Dark, BLACK)
	bgGrad.Rotation = dir > 0 and 180 or 0
	local hitX = W * 0.5
	local target, tgtScale = bigCard(stage, options.TargetId, Z + 10)
	target.Position = UDim2.fromOffset(hitX, H * 0.5)
	tgtScale.Scale = 1.25
	local center = Vector2.new(hitX, H * 0.5)
	local hits = special and 2 or 1
	for h = 1, hits do
		flash(root, WHITE, 0, 0.25, Z + 30)
		burst(stage, center, options.AttackerElement, special and 1.5 or (e.Mult > 1 and 1.25 or 1), Z + 15)
		UIKit.playSound("Hit", 0.9, special and 0.8 or 1)
		UIKit.playSound("Burst", 0.6, special and 0.8 or 1.1)
		options.Shake(special and 0.9 or (e.Mult > 1 and 0.6 or 0.35), 0.25)
		-- Recul de la cible, teinte rouge.
		target.Position = UDim2.fromOffset(hitX + 70 * dir, H * 0.5)
		target.Rotation = 9 * dir
		UIKit.tween(target, 0.5, { Position = UDim2.fromOffset(hitX, H * 0.5), Rotation = 0 }, Enum.EasingStyle.Elastic)
		local tint = new("Frame", { BackgroundColor3 = Color3.fromRGB(255, 40, 40), BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), ZIndex = Z + 12,
			Parent = target })
		round(tint, 12)
		UIKit.tween(tint, 0.35, { BackgroundTransparency = 1 })
		task.delay(0.4, function()
			tint:Destroy()
		end)
		if h < hits and not wait(0.28, alive) then
			return cleanup()
		end
	end

	-- Chiffre de dégâts géant.
	local dmgColor = special and GOLD or (e.Mult > 1 and Color3.fromRGB(255, 120, 70) or Color3.fromRGB(255, 90, 90))
	local dmg = UIKit.label({ Text = "-" .. tostring(e.Damage), Font = UIKit.Fonts.Title, TextColor3 = dmgColor, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(hitX + 230 * dir, H * 0.42), Size = UDim2.fromOffset(360, 150), Rotation = -6 * dir, ZIndex = Z + 25, Parent = stage }, 140)
	new("UIStroke", { Color = BLACK, Thickness = 5, Parent = dmg })
	local dmgScale = new("UIScale", { Scale = 2.4, Parent = dmg })
	UIKit.tween(dmgScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

	local verdict, vColor
	if e.KO then
		verdict, vColor = "K.O. !", Color3.fromRGB(255, 80, 80)
	elseif e.Mult > 1 then
		verdict, vColor = "SUPER EFFICACE !", Color3.fromRGB(124, 245, 154)
	elseif e.Blocked then
		verdict, vColor = "PARÉ !", Color3.fromRGB(130, 200, 255)
	elseif e.Mult < 1 then
		verdict, vColor = "Peu efficace...", Color3.fromRGB(200, 190, 220)
	end
	if verdict then
		task.delay(0.2, function()
			if not stage.Parent then
				return
			end
			local v = UIKit.label({ Text = verdict, Font = UIKit.Fonts.Title, TextColor3 = vColor, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(hitX, H * 0.8), Size = UDim2.fromOffset(700, 90), ZIndex = Z + 25, Parent = stage }, e.KO and 88 or 64)
			new("UIStroke", { Color = BLACK, Thickness = 4, Parent = v })
			local s = new("UIScale", { Scale = 0.3, Parent = v })
			UIKit.tween(s, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			if e.KO then
				UIKit.tween(target, 0.6, { Rotation = 25 * dir, Position = UDim2.fromOffset(hitX + 80 * dir, H * 0.5 + 120) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				for _, d in ipairs(target:GetDescendants()) do
					if d:IsA("GuiObject") then
						UIKit.tween(d, 0.6, { BackgroundTransparency = 1 })
					end
				end
				UIKit.tween(bg, 0.3, { BackgroundColor3 = Color3.fromRGB(255, 160, 160) })
			end
		end)
	end

	-- 4. Sortie ------------------------------------------------------------
	local remaining = DuelCinematic.Duration[special and "Special" or "Attack"] - (special and 2.0 or 1.15)
	if not wait(math.max(remaining - 0.3, 0.3), alive) then
		return cleanup()
	end
	for _, bar in ipairs(bars) do
		UIKit.tween(bar, 0.3, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quint)
	end
	UIKit.tween(bg, 0.3, { BackgroundTransparency = 1 })
	for _, d in ipairs(stage:GetDescendants()) do
		if d:IsA("TextLabel") then
			UIKit.tween(d, 0.25, { TextTransparency = 1 })
		elseif d:IsA("UIStroke") then
			UIKit.tween(d, 0.25, { Transparency = 1 })
		elseif d:IsA("ImageLabel") then
			UIKit.tween(d, 0.25, { ImageTransparency = 1, BackgroundTransparency = 1 })
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			UIKit.tween(d, 0.25, { BackgroundTransparency = 1 })
		end
	end
	wait(0.3, function()
		return true
	end)
	cleanup()
end

return DuelCinematic
