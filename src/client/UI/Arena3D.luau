-- Colisée en 3D (local au joueur) : entrée des duellistes avec leur Anima,
-- Anima face à face pendant le combat, attaques mises en scène en 3D
-- (caméra, charge, impact élémentaire, recul, chiffres de dégâts).
--
-- Modèles : si ReplicatedStorage.Animas contient un Model nommé comme la
-- créature (ex. « flamichat »), il est utilisé ; sinon une créature
-- élémentaire provisoire est générée.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local CardsData = require(Configs:WaitForChild("CardsData"))
local VillageData = require(Configs:WaitForChild("VillageData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local Arena3D = {}
Arena3D.__index = Arena3D

local L = VillageData.Layout
local PLAYER_DIST = 14 -- les duellistes (placés par le serveur)
local ANIMA_DIST = 7 -- les Anima, devant leur dresseur
local SIZE = { Commun = 2.6, PeuCommun = 3, Rare = 3.5, Epique = 4.2, Legendaire = 5 }
local LIGHT = {
	Feu = Color3.fromRGB(255, 220, 120),
	Eau = Color3.fromRGB(200, 240, 255),
	Nature = Color3.fromRGB(210, 255, 160),
	Foudre = Color3.fromRGB(255, 255, 200),
	Ombre = Color3.fromRGB(200, 150, 255),
	Lumiere = Color3.fromRGB(255, 255, 240),
}
local TEX = {
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}

local function tween(inst: Instance, t: number, goal, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function part(props): BasePart
	local p = Instance.new(props.ClassName or "Part")
	props.ClassName = nil
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

-- Temps écoulé « interruptible » : faux si l'arène a été détruite.
function Arena3D:wait(t: number): boolean
	local stop = os.clock() + t
	while os.clock() < stop do
		if self.Dead then
			return false
		end
		task.wait()
	end
	return not self.Dead
end

-------------------------------------------------------------------------------
-- Anima
-------------------------------------------------------------------------------
local function emitter(parent: Instance, element: string, rate: number): ParticleEmitter
	local el = CardsData.Elements[element] or CardsData.Elements.Feu
	local light = LIGHT[element] or Color3.new(1, 1, 1)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(light, el.Color)
	e.LightEmission = 0.8
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Texture = TEX.Spark
	if element == "Feu" then
		e.Texture = TEX.Fire
		e.Acceleration = Vector3.new(0, 6, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	elseif element == "Eau" then
		e.Acceleration = Vector3.new(0, 3, 0)
		e.Speed = NumberRange.new(0.5, 1.5)
	elseif element == "Nature" then
		e.Acceleration = Vector3.new(0, -2, 0)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-120, 120)
	elseif element == "Ombre" then
		e.Texture = TEX.Smoke
		e.LightEmission = 0
		e.Color = ColorSequence.new(Color3.fromRGB(40, 15, 70), el.Color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2) })
	elseif element == "Foudre" then
		e.Speed = NumberRange.new(4, 8)
		e.Lifetime = NumberRange.new(0.15, 0.3)
	end
	e.Parent = parent
	return e
end

-- Créature élémentaire provisoire (en attendant les vrais modèles).
local function placeholder(card, size: number): Model
	local el = CardsData.Elements[card.Element] or CardsData.Elements.Feu
	local light = LIGHT[card.Element] or Color3.new(1, 1, 1)
	local model = Instance.new("Model")
	local core = part({ Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.one * size, Color = el.Color, Material = Enum.Material.SmoothPlastic,
		Parent = model })
	part({ Name = "Belly", Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.62, Color = light, Material = Enum.Material.Neon, Transparency = 0.15,
		CFrame = CFrame.new(0, -size * 0.12, -size * 0.2), Parent = model })
	-- Yeux brillants, tournés vers -Z (l'avant).
	for _, sx in ipairs({ -1, 1 }) do
		local eye = part({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.2, Color = Color3.fromRGB(20, 12, 30),
			CFrame = CFrame.new(sx * size * 0.19, size * 0.12, -size * 0.4), Parent = model })
		part({ Name = "Shine", Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.07, Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon,
			CFrame = eye.CFrame * CFrame.new(size * 0.03, size * 0.04, -size * 0.07), Parent = model })
		-- Cornes / oreilles.
		part({ Name = "Horn", Size = Vector3.new(size * 0.16, size * 0.5, size * 0.16), Color = el.Dark, Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(sx * size * 0.28, size * 0.5, 0) * CFrame.Angles(0, 0, -sx * math.rad(25)), Parent = model })
		-- Petites pattes.
		part({ Name = "Paw", Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.28, Color = el.Dark,
			CFrame = CFrame.new(sx * size * 0.28, -size * 0.45, -size * 0.1), Parent = model })
	end
	-- Queue.
	part({ Name = "Tail", Shape = Enum.PartType.Ball, Size = Vector3.new(size * 0.3, size * 0.3, size * 0.6), Color = el.Color,
		CFrame = CFrame.new(0, -size * 0.1, size * 0.55), Parent = model })
	model.PrimaryPart = core
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p ~= core then
			p.CFrame = core.CFrame * p.CFrame
		end
	end
	return model
end

local function buildAnima(cardId: string): (Model, number)
	local card = CardsData.CardById[cardId]
	local size = SIZE[card and card.Rarity or "Commun"] or 3
	local folder = ReplicatedStorage:FindFirstChild("Animas")
	local source = folder and folder:FindFirstChild(cardId)
	local model: Model
	if source and source:IsA("Model") then
		model = source:Clone()
		local _, box = model:GetBoundingBox()
		local largest = math.max(box.X, box.Y, box.Z)
		if largest > 0 then
			model:ScaleTo(model:GetScale() * size * 1.4 / largest)
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		if not model.PrimaryPart then
			model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
		end
	else
		model = placeholder(card or CardsData.Cards[1], size)
	end
	model.Name = "Anima_" .. cardId
	local root = model.PrimaryPart :: BasePart
	local element = card and card.Element or "Feu"
	local el = CardsData.Elements[element]
	local glow = Instance.new("PointLight")
	glow.Color = el.Color
	glow.Range = size * 4
	glow.Brightness = 1.5
	glow.Parent = root
	local aura = emitter(root, element, 12)
	aura.Name = "Aura"
	-- Effets d'impact (déclenchés à la demande avec :Emit).
	local burst = emitter(root, element, 0)
	burst.Name = "Burst"
	burst.Speed = NumberRange.new(10, 22)
	burst.Lifetime = NumberRange.new(0.3, 0.7)
	-- Traînée pendant la charge.
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.4, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.4, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(LIGHT[element] or Color3.new(1, 1, 1), el.Color)
	trail.LightEmission = 1
	trail.Lifetime = 0.25
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Enabled = false
	trail.Parent = root
	-- Contour lumineux (flash d'impact).
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(255, 60, 60)
	hl.OutlineTransparency = 1
	hl.FillTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = model
	return model, size
end

-------------------------------------------------------------------------------
-- Création
-------------------------------------------------------------------------------
-- data : données « Start » du duel (Me/Opp avec UserId et Deck).
-- opts.Spectator : vue d'un spectateur (caméra libre, barres de vie) ;
-- opts.MeSign : côté du joueur « Me » sur l'axe des duellistes (+1 / -1).
function Arena3D.new(data, shake: (number, number) -> (), opts)
	opts = opts or {}
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local self = setmetatable({}, Arena3D)
	self.Spectator = opts.Spectator == true
	self.Data = data
	self.Shake = shake
	self.Folder = Instance.new("Folder")
	self.Folder.Name = "DuelArena3D"
	self.Folder.Parent = workspace
	self.Sides = {}
	self.Hidden = {}

	-- Sol de la piste : rayon vers le bas au centre du colisée.
	local c = L.Colosseum
	local top = Vector3.new(c.X, (L.Ground or 0) + 80, c.Y)
	local params = RaycastParams.new()
	local ignore = { self.Folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(top, Vector3.new(0, -160, 0), params)
	local floorY = hit and hit.Position.Y or (L.Ground or 0) + 0.5
	self.Center = Vector3.new(c.X, floorY, c.Y)

	-- Axe des duellistes (perpendiculaire aux portes), comme côté serveur.
	local gate = math.rad(L.ColosseumGate)
	local axis = Vector3.new(-math.sin(gate), 0, math.cos(gate))
	local me = Players.LocalPlayer
	local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	local sign = 1
	if opts.MeSign then
		sign = opts.MeSign
	elseif root and (root.Position - self.Center):Dot(axis) < 0 then
		sign = -1
	end
	for key, s in pairs({ Me = sign, Opp = -sign }) do
		local dir = axis * s
		self.Sides[key] = {
			Dir = dir,
			PlayerSpot = self.Center + dir * PLAYER_DIST,
			Spot = self.Center + dir * ANIMA_DIST,
			UserId = data[key].UserId,
		}
	end
	-- Plan large : la caméra regarde l'axe de côté, ton Anima à gauche.
	local perp = Vector3.new(math.cos(gate), 0, math.sin(gate))
	local function wide(side: number): CFrame
		local pos = self.Center + perp * side * 25 + Vector3.new(0, 8, 0)
		return CFrame.lookAt(pos, self.Center + Vector3.new(0, 3, 0))
	end
	self.Wide = wide(1)
	if self.Wide.RightVector:Dot(self.Sides.Me.Dir) > 0 then
		self.Wide = wide(-1)
	end
	self.CamTarget = self.Wide
	self.CamCF = self.Wide
	self:lightCircle(true)
	-- Le flou de profondeur du décor blanchit les plans rapprochés : coupé
	-- pendant le duel, rétabli à la fin.
	self.Blur = {}
	for _, fx in ipairs(self.Spectator and {} or Lighting:GetChildren()) do
		if fx:IsA("DepthOfFieldEffect") and fx.Enabled then
			fx.Enabled = false
			table.insert(self.Blur, fx)
		end
	end

	-- Caméra scriptée, lissée.
	if not self.Spectator then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	self.StepName = self.Spectator and "ArcanaArena3DSpec" or "ArcanaArena3D"
	local t0 = os.clock()
	RunService:BindToRenderStep(self.StepName, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local k = 1 - math.exp(-dt * (self.CamSpeed or 6))
		self.CamCF = self.CamCF:Lerp(self.CamTarget, k)
		local t = os.clock() - t0
		-- Légère respiration du plan (pas pour les spectateurs : caméra libre).
		if not self.Spectator then
			camera.CFrame = self.CamCF * CFrame.new(math.sin(t * 0.4) * 0.3, math.sin(t * 0.55) * 0.2, 0)
		end
		-- Les Anima flottent doucement.
		for key, s in pairs(self.Sides) do
			if s.Model and s.Model.Parent and not s.Busy then
				local phase = key == "Me" and 0 or math.pi
				local bob = math.sin(t * 2 + phase) * 0.25
				s.Model:PivotTo(s.Home * CFrame.new(0, bob, 0))
			end
		end
	end)
	return self
end

-- Cercle des Arcanes : runes plus vives pendant le duel, piliers des
-- éléments en jeu illuminés (local à ce joueur).
function Arena3D:lightCircle(on: boolean)
	local world = workspace:FindFirstChild("World")
	local circle = world and world:FindFirstChild("Colosseum")
	if not circle then
		return
	end
	local runes = circle:FindFirstChild("Runes")
	if runes then
		for _, p in ipairs(runes:GetChildren()) do
			if p:IsA("BasePart") then
				tween(p, 0.8, { Transparency = on and 0 or 0.25, Color = on and Color3.fromRGB(190, 150, 255) or Color3.fromRGB(150, 110, 255) })
				local halo = p:FindFirstChildOfClass("PointLight")
				if halo then
					tween(halo, 0.8, { Brightness = on and 2 or 1.2 })
				end
			end
		end
	end
	self.Circle = circle
	self:lightPillars()
end

function Arena3D:lightPillars()
	local pillars = self.Circle and self.Circle:FindFirstChild("Piliers")
	if not pillars then
		return
	end
	local active = {}
	if not self.Dead then
		for _, s in pairs(self.Sides) do
			local card = s.CardId and CardsData.CardById[s.CardId]
			if card then
				active[card.Element] = true
			end
		end
	end
	for _, pillar in ipairs(pillars:GetChildren()) do
		local on = active[pillar:GetAttribute("Element")] == true
		local crystal = pillar:FindFirstChild("Cristal")
		local light = crystal and crystal:FindFirstChildOfClass("PointLight")
		local sparks = crystal and crystal:FindFirstChild("Eclat")
		if light then
			tween(light, 0.6, { Brightness = on and 6 or 1.5, Range = on and 28 or 16 })
		end
		if crystal then
			tween(crystal, 0.6, { Transparency = on and 0 or 0.15 })
			crystal.Material = on and Enum.Material.Neon or Enum.Material.Glass
		end
		if sparks then
			sparks.Rate = on and 25 or 4
		end
	end
end

-- Coupe ou glisse la caméra vers un plan.
function Arena3D:Cam(cf: CFrame, speed: number?, cut: boolean?)
	if self.Spectator then
		return
	end
	self.CamTarget = cf
	self.CamSpeed = speed or 6
	if cut then
		self.CamCF = cf
	end
end

-- Repère d'un Anima à sa place, tourné vers l'adversaire.
function Arena3D:homeOf(key: string, size: number): CFrame
	local s = self.Sides[key]
	local pos = s.Spot + Vector3.new(0, size * 0.5 + 1.2, 0)
	-- Face à l'adversaire, légèrement tourné vers la caméra du plan large.
	local toward = self.Center + (self.Wide.Position - self.Center) * Vector3.new(1, 0, 1) * 0.35
	return CFrame.lookAt(pos, Vector3.new(toward.X, pos.Y, toward.Z))
end

-------------------------------------------------------------------------------
-- Effets
-------------------------------------------------------------------------------
function Arena3D:pillar(pos: Vector3, color: Color3, height: number)
	local beam = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, 0.5, 0.5), Color = color, Material = Enum.Material.Neon,
		Transparency = 0.1, CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Parent = self.Folder })
	tween(beam, 0.25, { Size = Vector3.new(height, 7, 7) }, Enum.EasingStyle.Quint)
	task.delay(0.35, function()
		tween(beam, 0.6, { Size = Vector3.new(height, 0.2, 0.2), Transparency = 1 })
	end)
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2, 2), Color = color, Material = Enum.Material.Neon, Transparency = 0.2,
		CFrame = CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Parent = self.Folder })
	tween(ring, 0.8, { Size = Vector3.new(0.2, 22, 22), Transparency = 1 }, Enum.EasingStyle.Quint)
	task.delay(1.2, function()
		beam:Destroy()
		ring:Destroy()
	end)
end

-- Chiffre flottant au-dessus d'un Anima (dégâts, soin...).
function Arena3D:Number(key: string, value: string, color: Color3, big: boolean?)
	local s = self.Sides[key]
	if not (s and s.Model and s.Model.PrimaryPart) then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 90)
	bb.StudsOffsetWorldSpace = Vector3.new(math.random(-10, 10) / 10, s.Size * 0.8 + 1.5, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = s.Model.PrimaryPart
	bb.Parent = self.Folder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = value
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = bb
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Parent = label
	local sc = Instance.new("UIScale")
	sc.Scale = big and 2.4 or 1.8
	sc.Parent = label
	tween(sc, 0.3, { Scale = big and 1.3 or 1 }, Enum.EasingStyle.Back)
	tween(bb, 1.3, { StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, 3, 0) })
	task.delay(0.8, function()
		tween(label, 0.5, { TextTransparency = 1 })
		tween(st, 0.5, { Transparency = 1 })
	end)
	task.delay(1.4, function()
		bb:Destroy()
	end)
end

function Arena3D:flashModel(key: string, color: Color3)
	local s = self.Sides[key]
	local hl = s and s.Model and s.Model:FindFirstChildOfClass("Highlight")
	if hl then
		hl.FillColor = color
		hl.FillTransparency = 0.1
		tween(hl, 0.4, { FillTransparency = 1 })
	end
end

function Arena3D:bubble(key: string, color: Color3)
	local s = self.Sides[key]
	if not (s and s.Model) then
		return
	end
	local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * s.Size * 1.2, Color = color, Material = Enum.Material.ForceField,
		CFrame = s.Model:GetPivot(), Parent = self.Folder })
	tween(b, 0.4, { Size = Vector3.one * s.Size * 2.2 }, Enum.EasingStyle.Back)
	task.delay(0.9, function()
		tween(b, 0.4, { Transparency = 1 })
	end)
	task.delay(1.4, function()
		b:Destroy()
	end)
end

function Arena3D:flashScreen(intensity: number)
	if self.Spectator then
		return
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = intensity
	cc.Parent = Lighting
	tween(cc, 0.3, { Brightness = 0 })
	task.delay(0.35, function()
		cc:Destroy()
	end)
end

-------------------------------------------------------------------------------
-- Anima en jeu
-------------------------------------------------------------------------------
-- Fait entrer une créature (invocation) ; l'ancienne repart ou tombe K.O.
function Arena3D:SetActive(key: string, cardId: string?, knockedOut: boolean?)
	local s = self.Sides[key]
	if not s or s.CardId == cardId then
		return
	end
	s.CardId = cardId
	self:lightPillars()
	local old = s.Model
	if old then
		s.Model = nil
		local pivot = old:GetPivot()
		if knockedOut then
			-- K.O. : bascule, s'enfonce et s'efface.
			for _, d in ipairs(old:GetDescendants()) do
				if d:IsA("BasePart") then
					tween(d, 0.9, { Transparency = 1 })
				elseif d:IsA("ParticleEmitter") then
					d.Enabled = false
				end
			end
			local v = Instance.new("CFrameValue")
			v.Value = pivot
			v.Changed:Connect(function(cf)
				if old.Parent then
					old:PivotTo(cf)
				end
			end)
			tween(v, 0.9, { Value = pivot * CFrame.new(0, -s.Size * 0.6, 0) * CFrame.Angles(math.rad(70), 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(1, function()
				old:Destroy()
				v:Destroy()
			end)
		else
			-- Rappel : rayon de lumière et disparition.
			local el = CardsData.Elements[(CardsData.CardById[old.Name:sub(7)] or {}).Element or "Lumiere"]
			self:pillar(pivot.Position - Vector3.new(0, s.Size, 0), el and el.Color or Color3.new(1, 1, 1), 14)
			old:Destroy()
		end
	end
	if not cardId then
		return
	end
	local model, size = buildAnima(cardId)
	s.Size = size
	s.Home = self:homeOf(key, size)
	s.Model = model
	s.Busy = true
	local card = CardsData.CardById[cardId]
	local color = card and CardsData.Elements[card.Element].Color or Color3.new(1, 1, 1)
	-- Invocation : pilier de lumière, puis l'Anima jaillit du sol.
	task.delay(knockedOut and 0.9 or 0.2, function()
		if self.Dead or s.Model ~= model then
			model:Destroy()
			return
		end
		self:pillar(s.Spot, color, 18)
		model:PivotTo(s.Home * CFrame.new(0, -size, 0))
		model.Parent = self.Folder
		local v = Instance.new("CFrameValue")
		v.Value = model:GetPivot()
		v.Changed:Connect(function(cf)
			if model.Parent then
				model:PivotTo(cf)
			end
		end)
		tween(v, 0.6, { Value = s.Home }, Enum.EasingStyle.Back)
		UIKit.playSound("Burst", 0.5, 1.2)
		task.delay(0.65, function()
			v:Destroy()
			if s.Model == model then
				s.Busy = false
			end
		end)
	end)
end

-------------------------------------------------------------------------------
-- Entrée des duellistes
-------------------------------------------------------------------------------
local function hideCharacter(character: Model?, hidden: boolean)
	if not character then
		return
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

-- Copie locale d'un avatar qui marche jusqu'à sa place.
function Arena3D:walker(userId: number, from: Vector3, to: Vector3, duration: number)
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	if not character then
		return nil
	end
	character.Archivable = true
	local clone = character:Clone()
	if not clone then
		return nil
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.LocalTransparencyModifier = 0
		end
	end
	local root = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) then
		clone:Destroy()
		return nil
	end
	root.Anchored = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local hip = (character:FindFirstChild("HumanoidRootPart") :: BasePart).Position.Y - to.Y
	hip = math.clamp(hip, 2, 6)
	clone.Parent = self.Folder
	-- Animation de marche reprise du script « Animate » du joueur.
	local animate = character:FindFirstChild("Animate")
	local walk = animate and animate:FindFirstChild("walk")
	local anim = walk and walk:FindFirstChildOfClass("Animation")
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local track
	if anim then
		local ok, result = pcall(animator.LoadAnimation, animator, anim)
		if ok then
			track = result
			track.Looped = true
			track:Play(0.1)
		end
	end
	local start = os.clock()
	local look = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Unit
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - start) / duration, 0, 1)
		local pos = from:Lerp(to, k) + Vector3.new(0, hip, 0)
		if k < 1 then
			root.CFrame = CFrame.lookAt(pos, pos + look)
		else
			conn:Disconnect()
			if track then
				track:Stop(0.3)
			end
			local face = Vector3.new(self.Center.X, pos.Y, self.Center.Z)
			root.CFrame = CFrame.lookAt(pos, face)
		end
	end)
	return clone
end

-- Cinématique d'entrée (bloquante, ~7 s) : chaque duelliste entre dans
-- l'arène et invoque son Anima, puis plan large du face-à-face.
function Arena3D:Entrance()
	local walkers = {}
	local chars = {}
	for _, key in ipairs({ "Me", "Opp" }) do
		local p = Players:GetPlayerByUserId(self.Sides[key].UserId)
		if p and p.Character then
			hideCharacter(p.Character, true)
			table.insert(chars, p.Character)
		end
	end
	self.HiddenChars = chars
	local function deckFirst(key: string): string?
		local deck = self.Data[key].Deck or {}
		for _, f in ipairs(deck) do
			if f.Active then
				return f.Id
			end
		end
		return deck[1] and deck[1].Id
	end

	-- Plan d'ensemble en plongée sur le sable.
	self:Cam(CFrame.lookAt(self.Center + Vector3.new(0, 40, 0) + self.Wide.LookVector * -20, self.Center), 2, true)
	if not self:wait(0.8) then
		return
	end
	for _, key in ipairs({ "Me", "Opp" }) do
		local s = self.Sides[key]
		local from = self.Center + s.Dir * (PLAYER_DIST + 16)
		local w = self:walker(s.UserId, from, s.PlayerSpot, 1.8)
		if w then
			table.insert(walkers, w)
		end
		-- Caméra devant le dresseur qui avance.
		local side = self.Wide.RightVector * (key == "Me" and -1 or 1)
		local camPos = s.PlayerSpot - s.Dir * 6 + side * 7 + Vector3.new(0, 4, 0)
		self:Cam(CFrame.lookAt(camPos, from:Lerp(s.PlayerSpot, 0.6) + Vector3.new(0, 3, 0)), 3, true)
		self:Cam(CFrame.lookAt(camPos, s.PlayerSpot + Vector3.new(0, 3, 0)), 2)
		if not self:wait(1.8) then
			return
		end
		-- Invocation de l'Anima.
		self:Cam(CFrame.lookAt(s.Spot - s.Dir * 9 + side * 4 + Vector3.new(0, 4, 0), s.Spot + Vector3.new(0, 2.5, 0)), 5)
		self:SetActive(key, deckFirst(key))
		self.Shake(0.35, 0.3)
		if not self:wait(1.5) then
			return
		end
	end
	-- Face-à-face.
	self:Cam(self.Wide, 2)
	if not self:wait(1.2) then
		return
	end
	for _, w in ipairs(walkers) do
		w:Destroy()
	end
	for _, ch in ipairs(chars) do
		hideCharacter(ch, false)
	end
	self.HiddenChars = nil
end

-------------------------------------------------------------------------------
-- Actions du combat
-------------------------------------------------------------------------------
function Arena3D:Tick(key: string, color: Color3, value: string)
	local s = self.Sides[key]
	if s and s.Model and s.Model.PrimaryPart then
		local burst = s.Model.PrimaryPart:FindFirstChild("Burst") :: ParticleEmitter?
		if burst then
			burst:Emit(20)
		end
		self:flashModel(key, color)
		self:Number(key, value, color)
	end
end

function Arena3D:Guard(key: string, value: string?)
	self:bubble(key, Color3.fromRGB(120, 195, 255))
	if value then
		self:Number(key, value, Color3.fromRGB(95, 225, 130))
	end
end

function Arena3D:Buff(key: string, value: string?, color: Color3?)
	local s = self.Sides[key]
	self:bubble(key, Color3.fromRGB(255, 215, 120))
	if s and s.Model then
		self:pillar(s.Spot, Color3.fromRGB(255, 225, 150), 10)
	end
	if value then
		self:Number(key, value, color or Color3.fromRGB(95, 225, 130))
	end
end

-- Attaque mise en scène (bloquante). e : événement du serveur.
function Arena3D:Attack(attackerKey: string, e)
	local a, t = self.Sides[attackerKey], self.Sides[attackerKey == "Me" and "Opp" or "Me"]
	if not (a.Model and t.Model) then
		return
	end
	local ability = e.Action == "Ability"
	local hits = e.Hits or { e.Damage }
	local dirAT = (t.Spot - a.Spot).Unit
	local right = dirAT:Cross(Vector3.yAxis)
	a.Busy = true

	-- 1. Par-dessus l'épaule de l'attaquant ; il se charge d'énergie.
	local over = CFrame.lookAt(a.Spot - dirAT * 8 + right * 3.5 + Vector3.new(0, 3.5 + a.Size * 0.3, 0), t.Spot + Vector3.new(0, t.Size * 0.5, 0))
	self:Cam(over, 9, true)
	local root = a.Model.PrimaryPart
	local light = root and root:FindFirstChildOfClass("PointLight")
	local burstA = root and root:FindFirstChild("Burst") :: ParticleEmitter?
	if light then
		tween(light, 0.4, { Brightness = ability and 8 or 4, Range = a.Size * 7 })
	end
	if ability then
		self:pillar(a.Spot, CardsData.Elements[(CardsData.CardById[a.Model.Name:sub(7)] or {}).Element or "Feu"].Color, 12)
		UIKit.playSound("Charge", 0.7, 1)
		self.Shake(0.15, 0.6)
	end
	-- Élan vers l'arrière.
	local back = a.Home * CFrame.new(0, 0.6, 1.5)
	local function moveTo(cf: CFrame, time: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
		local v = Instance.new("CFrameValue")
		v.Value = a.Model:GetPivot()
		v.Changed:Connect(function(x)
			if a.Model and a.Model.Parent then
				a.Model:PivotTo(x)
			end
		end)
		tween(v, time, { Value = cf }, style, dir)
		task.delay(time + 0.05, function()
			v:Destroy()
		end)
	end
	moveTo(back, ability and 0.6 or 0.35, Enum.EasingStyle.Quad)
	if not self:wait(ability and 0.75 or 0.4) then
		return
	end

	-- 2. Charge : traînée, caméra latérale qui suit.
	local trail = root and root:FindFirstChildOfClass("Trail")
	if trail then
		trail.Enabled = true
	end
	UIKit.playSound("Swoosh", 0.7, 0.9)
	local strikePos = t.Home.Position - dirAT * (t.Size * 0.5 + a.Size * 0.5 + 0.3)
	local side = CFrame.lookAt(self.Center + right * 15 + Vector3.new(0, 4, 0), t.Spot + Vector3.new(0, 2, 0))
	self:Cam(side, 12, true)
	moveTo(CFrame.lookAt(strikePos, strikePos + dirAT), 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if not self:wait(0.2) then
		return
	end

	-- 3. Impact(s).
	for i, dmg in ipairs(hits) do
		local tr = t.Model and t.Model.PrimaryPart
		local burstT = tr and tr:FindFirstChild("Burst") :: ParticleEmitter?
		if burstA then
			burstA:Emit(ability and 60 or 35)
		end
		if burstT then
			burstT:Emit(20)
		end
		self:flashModel(attackerKey == "Me" and "Opp" or "Me", Color3.fromRGB(255, 60, 60))
		self:flashScreen(ability and 0.35 or 0.2)
		self.Shake(ability and 0.8 or (e.Mult > 1 and 0.55 or 0.35), 0.25)
		UIKit.playSound("Hit", 0.9, ability and 0.85 or 1)
		UIKit.playSound("Burst", 0.5, 1.1)
		self:Number(attackerKey == "Me" and "Opp" or "Me", "-" .. tostring(dmg), ability and Color3.fromRGB(255, 215, 120) or Color3.fromRGB(255, 95, 95),
			ability or e.Mult > 1)
		-- Recul de la cible.
		if t.Model then
			t.Busy = true
			local tv = Instance.new("CFrameValue")
			tv.Value = t.Home * CFrame.new(0, 0.3, 1.6) * CFrame.Angles(math.rad(-15), 0, 0)
			tv.Changed:Connect(function(x)
				if t.Model and t.Model.Parent then
					t.Model:PivotTo(x)
				end
			end)
			t.Model:PivotTo(tv.Value)
			tween(tv, 0.45, { Value = t.Home }, Enum.EasingStyle.Elastic)
			task.delay(0.5, function()
				tv:Destroy()
				t.Busy = false
			end)
		end
		if i < #hits then
			-- Petit rebond avant le coup suivant.
			moveTo(CFrame.lookAt(strikePos - dirAT * 1.5, strikePos), 0.12)
			if not self:wait(0.15) then
				return
			end
			moveTo(CFrame.lookAt(strikePos, strikePos + dirAT), 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			if not self:wait(0.15) then
				return
			end
		end
	end
	if (e.Absorbed or 0) > 0 then
		self:bubble(attackerKey == "Me" and "Opp" or "Me", Color3.fromRGB(120, 200, 255))
	end
	if not self:wait(0.45) then
		return
	end

	-- 4. Retour à sa place, plan large.
	if trail then
		trail.Enabled = false
	end
	if light then
		tween(light, 0.5, { Brightness = 1.5, Range = a.Size * 4 })
	end
	moveTo(a.Home, 0.4, Enum.EasingStyle.Quint)
	self:Cam(self.Wide, 4)
	if (e.Reflected or 0) > 0 then
		self:Number(attackerKey, "◇ -" .. e.Reflected, Color3.fromRGB(200, 240, 255))
	end
	if not self:wait(0.45) then
		return
	end
	a.Busy = false
end

-- Barre de vie flottante au-dessus d'un Anima (vue spectateur).
function Arena3D:SetHP(key: string, hp: number, maxHP: number, title: string?)
	local s = self.Sides[key]
	if not s then
		return
	end
	local bb = s.HPBar
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "HP_" .. key
		bb.Size = UDim2.fromOffset(180, 46)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.MaxDistance = 200
		bb.Parent = self.Folder
		local name = Instance.new("TextLabel")
		name.Name = "Title"
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, 0, 0, 22)
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Parent = bb
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = name
		local track = Instance.new("Frame")
		track.Name = "Track"
		track.Position = UDim2.fromOffset(10, 28)
		track.Size = UDim2.new(1, -20, 0, 12)
		track.BackgroundColor3 = Color3.fromRGB(15, 10, 25)
		track.Parent = bb
		Instance.new("UICorner", track).CornerRadius = UDim.new(0.5, 0)
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(95, 225, 130)
		fill.Parent = track
		Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)
		s.HPBar = bb
	end
	if s.Model and s.Model.PrimaryPart then
		bb.Adornee = s.Model.PrimaryPart
		bb.StudsOffsetWorldSpace = Vector3.new(0, (s.Size or 3) * 0.8 + 1.2, 0)
	end
	if title then
		bb.Title.Text = title
	end
	local ratio = maxHP > 0 and math.clamp(hp / maxHP, 0, 1) or 0
	local color = ratio > 0.5 and Color3.fromRGB(95, 225, 130) or (ratio > 0.25 and Color3.fromRGB(255, 200, 80) or Color3.fromRGB(255, 90, 90))
	tween(bb.Track.Fill, 0.35, { Size = UDim2.fromScale(ratio, 1), BackgroundColor3 = color })
end

function Arena3D:Destroy()
	if self.Dead then
		return
	end
	self.Dead = true
	RunService:UnbindFromRenderStep(self.StepName or "ArcanaArena3D")
	self:lightCircle(false)
	if self.HiddenChars then
		for _, ch in ipairs(self.HiddenChars) do
			hideCharacter(ch, false)
		end
	end
	self.Folder:Destroy()
	for _, fx in ipairs(self.Blur or {}) do
		fx.Enabled = true
	end
	local camera = workspace.CurrentCamera
	if camera and not self.Spectator then
		camera.CameraType = Enum.CameraType.Custom
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

return Arena3D
