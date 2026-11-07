-- Booster 3D (modèle « BoosterModel » importé dans ReplicatedStorage) :
--   • présentoir tournant au-dessus de l'autel de l'arène (animation Repos) ;
--   • ouverture dans l'écran de révélation : le sachet arrive, tremble, puis
--     joue l'animation « Ouverture » du fichier et retourne les cartes.
-- Animations : identifiants publiés en attributs sur BoosterModel (AnimOpen,
-- AnimIdle, AnimFlip1, AnimFlip2, AnimFlip3) ou, dans Studio, séquences
-- importées (KeyframeSequence) rangées dans BoosterModel ou ReplicatedStorage.
-- Sans animation disponible, une ouverture animée par script prend le relais.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BoosterFX = {}

local ANIMS = {
	Open = { "AnimOpen", "Ouverture" },
	Idle = { "AnimIdle", "Repos" },
	Flip1 = { "AnimFlip1", "Retourner_carte_1" },
	Flip2 = { "AnimFlip2", "Retourner_carte_2" },
	Flip3 = { "AnimFlip3", "Retourner_carte_3" },
}

function BoosterFX.template(): Model?
	local m = ReplicatedStorage:FindFirstChild("BoosterModel")
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

local registered: { [string]: string } = {}
local loggedOnce = false
local function animationId(template: Model, key: string): string?
	local attribute, name = ANIMS[key][1], ANIMS[key][2]
	local id = template:GetAttribute(attribute)
	if type(id) == "string" and id ~= "" then
		return id
	end
	if registered[key] == nil then
		registered[key] = ""
		for _, holder in ipairs({ template, ReplicatedStorage }) do
			for _, d in ipairs(holder:GetDescendants()) do
				if d:IsA("KeyframeSequence") and string.find(d.Name, name, 1, true) then
					local ok, result = pcall(function()
						return game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(d)
					end)
					if ok then
						registered[key] = result
					end
					break
				end
			end
			if registered[key] ~= "" then
				break
			end
		end
	end
	return registered[key] ~= "" and registered[key] or nil
end

-- Boîte englobante des pièces visibles (les os et pièces techniques
-- invisibles de l'import faussent GetBoundingBox).
local function visibleBounds(m: Model, skipCards: boolean?): (Vector3, Vector3)
	local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 and not (skipCards and string.sub(string.lower(d.Name), 1, 5) == "carte") then
			local half = d.Size / 2
			for _, cx in ipairs({ -1, 1 }) do
				for _, cy in ipairs({ -1, 1 }) do
					for _, cz in ipairs({ -1, 1 }) do
						local corner = d.CFrame:PointToWorldSpace(Vector3.new(half.X * cx, half.Y * cy, half.Z * cz))
						minV = minV:Min(corner)
						maxV = maxV:Max(corner)
					end
				end
			end
		end
	end
	if minV.X == math.huge then
		local cf, size = m:GetBoundingBox()
		return cf.Position, size
	end
	return (minV + maxV) / 2, maxV - minV
end

-- Copie prête à l'emploi : pièces ancrées, pivot au centre, pistes d'animation.
local function prepare(template: Model): (Model, { [string]: AnimationTrack })
	local m = template:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("KeyframeSequence") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local center = visibleBounds(m)
	m.WorldPivot = CFrame.new(center)

	local controller = m:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController")
	controller.Parent = m
	local animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = controller
	local tracks = {}
	for key in pairs(ANIMS) do
		local id = animationId(template, key)
		if id then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, track = pcall(animator.LoadAnimation, animator, anim)
			if ok and track then
				track.Looped = key == "Idle"
				tracks[key] = track
			end
		end
	end
	if not loggedOnce then
		loggedOnce = true
		local found = {}
		for key in pairs(ANIMS) do
			table.insert(found, key .. "=" .. (tracks[key] and "oui" or "non"))
		end
		print("[BoosterFX] Animations du booster : " .. table.concat(found, ", "))
	end
	return m, tracks
end

local function findPart(m: Model, prefix: string): BasePart?
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and string.sub(string.lower(d.Name), 1, #prefix) == prefix then
			return d
		end
	end
	return nil
end

local function tween(inst: Instance, duration: number, goal, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(inst, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

-- Attend la fin d'une piste (ou sa durée, si la fin n'est pas signalée).
local function playAndWait(track: AnimationTrack)
	track:Play(0.1)
	local length = track.Length > 0 and track.Length or 1.5
	local done = false
	local conn = track.Stopped:Connect(function()
		done = true
	end)
	local start = os.clock()
	while not done and os.clock() - start < length + 0.2 do
		task.wait()
	end
	conn:Disconnect()
end

-------------------------------------------------------------------------------
-- Animation procédurale fidèle au fichier Claude Design (booster_arcana.html)
-- Les formules ci-dessous sont celles du HTML (unités : largeur du sachet = 1).
-- On les applique aux os du modèle importé, à la bonne échelle.
-------------------------------------------------------------------------------
local W, NC, CB0 = 1, 3, 0.2
local Y_TEAR = (700 - 117) / 341
local OPEN_DUR_P, T_TEAR_P, T_FAN_P, FLIP_DUR_P = 5.6, 1.05, 4.2, 1.1
local FLIP_DIR, FLIP_SIDE = { 1, 1, -1 }, { 0, -1, 1 }

local function ss(a: number, b: number, t: number): number
	local x = math.clamp((t - a) / (b - a), 0, 1)
	return x * x * (3 - 2 * x)
end
local function lin(a: number, b: number, t: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end
local function eb(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	if x <= 0 then
		return 0
	end
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end
local function eo(x: number): number
	return 1 - (1 - x) ^ 3
end

-- Poses (position, rotation XYZ) de chaque os à l'instant t.
local function packAt(t: number)
	local up = ss(0.05, 0.6, t) * (1 - ss(2.0, 2.7, t))
	local shake = ss(0.4, 0.95, t) * (1 - ss(0.98, 1.1, t))
	local drop = ss(2.95, 3.7, t)
	return { 0.02 * math.sin(t * 61) * shake, 0.14 * up - 0.1 * drop + 0.015 * math.sin(t * 47) * shake, -0.35 * drop },
		{ 0, 0.25 * math.sin(t * 2.6) * ss(0.05, 0.6, t) * (1 - ss(0.6, 1.0, t)), 0.05 * math.sin(t * 53) * shake }
end
local function hautAt(t: number)
	local peel = ss(T_TEAR_P - 0.1, T_TEAR_P + 0.25, t)
	local f = ss(T_TEAR_P + 0.2, T_TEAR_P + 0.9, t)
	local aw = ss(T_TEAR_P + 0.6, T_TEAR_P + 1.0, t)
	return { W / 2 + 0.9 * f + 6 * aw, Y_TEAR + 0.03 * peel + 0.9 * f - 0.4 * f * f + 3 * aw, 0.4 * f - 2 * aw },
		{ -1.2 * f, 2.4 * f, -0.45 * peel - 2.2 * f }, aw
end
local function cardAt(i: number, t: number)
	local k = ({ 0, -1, 1 })[i]
	local t0 = 1.35 + (i - 1) * 0.3
	local out = eo(lin(t0, t0 + 0.5, t))
	local fwd = ss(t0 + 0.38, t0 + 0.9, t)
	local fan = eb(lin(3.2 + math.abs(k) * 0.06, T_FAN_P, t))
	local bob = 0.02 * math.sin((t - T_FAN_P) * 3 + (i - 1)) * ss(T_FAN_P, T_FAN_P + 0.5, t)
	local order = (NC - i) * 0.012
	local zi = (1 - (i - 1)) * 0.0035
	local ry = CB0 + (Y_TEAR + 0.08 - CB0) * out
	local rz = zi + (0.35 + order - zi) * fwd
	local fx, fy, fz = 0.5 * k, 0.85 - 0.06 * k * k, 0.45 + order
	local drop = ss(2.95, 3.7, t)
	return { fx * fan, ry + (fy - ry) * fan + bob + 0.1 * drop, rz + (fz - rz) * fan + 0.35 * drop },
		{ -0.12 * fwd * (1 - fan) - 0.05 * fan, 0, -0.14 * k * fan }
end
local function flipAt(i: number, p: number)
	local slide = ss(0, 0.14, p) * (1 - ss(0.88, 1, p))
	local lift = ss(0.12, 0.3, p) * (1 - ss(0.74, 0.88, p))
	local rot = ss(0.28, 0.8, p)
	local tilt = 0.06 * lift * math.sin(math.pi * rot)
	return { 0.34 * FLIP_SIDE[i] * slide, 0.08 * lift, 0.45 * lift }, { 0, FLIP_DIR[i] * math.pi * rot, tilt * FLIP_DIR[i] }
end
local function restAt(t: number)
	return { 0, 0.04 * math.sin(t * math.pi), 0 }, { 0, 0.12 * math.sin(t * math.pi / 2), 0.02 * math.sin(t * math.pi) }
end

-- Pilote des os d'un modèle importé.
local Rig = {}
Rig.__index = Rig

function Rig.new(model: Model)
	local bones = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Bone") then
			bones[d.Name] = d
		end
	end
	local haut = bones.haut
	if not (bones.pack and haut and bones.carte_1) then
		return nil
	end
	local self = setmetatable({}, Rig)
	self.Bones = bones
	self.Rest = {}
	for name, b in pairs(bones) do
		self.Rest[name] = b.CFrame
	end
	-- Échelle et sens de l'axe X d'après la position de repos de « haut ».
	local hp = haut.CFrame.Position
	self.K = math.abs(hp.Y) / Y_TEAR
	self.SX = hp.X < 0 and -1 or 1
	-- Sens de l'axe avant/arrière : dans le fichier, la face avant est vers +Z.
	-- Si l'import l'a inversée, les cartes doivent sortir vers -Z.
	self.SZ = 1
	local front, back
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "face_avant" then
				front = d
			elseif d.Name == "face_arriere" then
				back = d
			end
		end
	end
	if front and back then
		local pivot = model:GetPivot()
		local fz = pivot:PointToObjectSpace(front.Position).Z
		local bz = pivot:PointToObjectSpace(back.Position).Z
		if math.abs(fz - bz) > 1e-3 then
			self.SZ = fz < bz and -1 or 1
		end
	end
	self.Flip = { 0, 0, 0 }
	return self
end

function Rig:set(name: string, p, r)
	local b = self.Bones[name]
	local rest = self.Rest[name]
	if not (b and rest) then
		return
	end
	local k, sx, sz = self.K, self.SX, self.SZ
	-- Rotation du fichier exprimée dans le repère de l'import (miroir M R M).
	local rot = CFrame.fromEulerAnglesXYZ(r[1], r[2], r[3])
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = rot:GetComponents()
	local m = { sx, 1, sz }
	local mirrored = CFrame.new(0, 0, 0,
		m[1] * r00 * m[1], m[1] * r01 * m[2], m[1] * r02 * m[3],
		m[2] * r10 * m[1], m[2] * r11 * m[2], m[2] * r12 * m[3],
		m[3] * r20 * m[1], m[3] * r21 * m[2], m[3] * r22 * m[3])
	local desired = CFrame.new(p[1] * k * sx, p[2] * k, p[3] * k * sz) * mirrored
	b.Transform = rest:Inverse() * desired
end

function Rig:pose(t: number)
	local p, r = packAt(t)
	self:set("pack", p, r)
	local hp, hr, away = hautAt(t)
	self:set("haut", hp, hr)
	self.HautAway = away
	for i = 1, NC do
		local cp, cr = cardAt(i, t)
		self:set("carte_" .. i, cp, cr)
	end
end

function Rig:flip(i: number, p: number)
	local fp, fr = flipAt(i, p)
	self:set("carte_" .. i .. "_mesh", fp, fr)
end

function Rig:rest(t: number)
	local p, r = restAt(t)
	self:set("pack", p, r)
	self:set("haut", { W / 2, Y_TEAR, 0 }, { 0, 0, 0 })
	for i = 1, NC do
		self:set("carte_" .. i, { 0, CB0, (1 - (i - 1)) * 0.0035 }, { 0, 0, 0 })
		self:set("carte_" .. i .. "_mesh", { 0, 0, 0 }, { 0, 0, 0 })
	end
end

function Rig:bonePosition(name: string): Vector3?
	local b = self.Bones[name]
	return b and b.TransformedWorldCFrame.Position or nil
end
BoosterFX.Rig = Rig

-- Présentoir de l'autel : le booster flotte et tourne, le cristal est caché.
function BoosterFX.startDisplay()
	-- Le serveur recopie le modèle importé au démarrage : on lui laisse le temps.
	ReplicatedStorage:WaitForChild("BoosterModel", 15)
	local template = BoosterFX.template()
	if not template then
		return
	end
	while not workspace:GetAttribute("WorldReady") do
		task.wait(0.5)
	end
	local arena = workspace:WaitForChild("World"):WaitForChild("Arena", 30)
	-- L'autel 3D importé a déjà ses propres boosters flottants.
	if not arena or arena:GetAttribute("CustomAltar") then
		return
	end
	-- Le cristal et la boule lumineuse laissent la place au booster
	-- (la lumière et les étincelles de la boule restent).
	for _, name in ipairs({ "ArcanaCrystal", "CrystalCore" }) do
		local p = arena:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Transparency = 1
		end
	end
	local display, tracks = prepare(template)
	display.Name = "BoosterDisplay"
	-- Sur l'autel, seul le sachet flotte : les cartes restent cachées dedans.
	local cardParts = {}
	for _, d in ipairs(display:GetDescendants()) do
		if d:IsA("BasePart") and string.sub(string.lower(d.Name), 1, 5) == "carte" then
			cardParts[d] = d.Transparency
			d.Transparency = 1
		end
	end
	local _, size = visibleBounds(display, true)
	local center = Vector3.new(0, 7.4 + size.Y / 2 + 1.2, 0)
	display:PivotTo(CFrame.new(center))
	display.Parent = workspace
	local rig = Rig.new(display)
	if rig then
		-- Les os sont pilotés par script : aucune piste importée ne doit tourner.
		for _, track in pairs(tracks) do
			track:Stop(0)
		end
	elseif tracks.Idle then
		tracks.Idle:Play()
	end
	local t = 0
	local state = { Opening = false, Yaw = 0, Roll = 0 }
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		if state.Opening then
			display:PivotTo(CFrame.new(center) * CFrame.Angles(0, state.Yaw, math.rad(state.Roll)))
		else
			if rig then
				rig:rest(t)
			end
			display:PivotTo(CFrame.new(center + Vector3.new(0, math.sin(t * 1.4) * 0.6, 0)) * CFrame.Angles(0, t * 0.9, math.sin(t * 0.8) * 0.06))
		end
	end)
	BoosterFX.Display = { Model = display, Tracks = tracks, Center = center, Size = size, State = state, Cards = cardParts, Rig = rig }
end

-- Repères de l'animation « Ouverture » de Claude Design (secondes).
local OPEN_DUR, T_TEAR, T_FAN = 5.6, 1.05, 4.2
local FLIP_DUR = 1.1
-- Cartes du sachet : 1 = Nature, 2 = Feu, 3 = Glace.
local CARD_COLORS = { Color3.fromRGB(111, 211, 106), Color3.fromRGB(255, 138, 52), Color3.fromRGB(127, 211, 255) }
local ELEMENT_CARD = { Nature = 1, Feu = 2, Eau = 3, Glace = 3 }

local function findBone(m: Model, name: string): Bone?
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Bone") and d.Name == name then
			return d
		end
	end
	return nil
end

-- Fige une piste sur sa dernière image (comme clampWhenFinished dans three.js) :
-- sans ça, Roblox ramène les os à la pose de départ à la fin de l'animation.
local function playAndHold(track: AnimationTrack, length: number)
	track:Play(0.05)
	track.Looped = false
	task.delay(math.max(0, length - 0.06), function()
		if track.IsPlaying then
			track:AdjustSpeed(0)
		end
	end)
end

-- Effets : gerbe d'étincelles, éclair lumineux, anneau qui s'élargit.
local function sparks(at: Vector3, colors: { Color3 }, count: number, spread: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = workspace
	local keypoints = {}
	for i, c in ipairs(colors) do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), c))
	end
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(4 * spread, 11 * spread)
	e.SpreadAngle = Vector2.new(70, 70)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, -14, 0)
	e.Drag = 1.5
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 * spread), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0, 1)
	e.Color = #keypoints >= 2 and ColorSequence.new(keypoints) or ColorSequence.new(colors[1])
	e.Parent = anchor
	e:Emit(count)
	game:GetService("Debris"):AddItem(anchor, 2)
end

local function flash(at: Vector3, color: Color3, size: number)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Transparency = 0.2
	ball.Size = Vector3.one * size * 0.3
	ball.CFrame = CFrame.new(at)
	ball.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 6
	light.Range = size * 6
	light.Parent = ball
	tween(ball, 0.45, { Size = Vector3.one * size, Transparency = 1 })
	tween(light, 0.45, { Brightness = 0 })
	game:GetService("Debris"):AddItem(ball, 0.6)
end

local function ring(at: CFrame, color: Color3, size: number)
	local r = Instance.new("Part")
	r.Shape = Enum.PartType.Cylinder
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.Material = Enum.Material.Neon
	r.Color = color
	r.Transparency = 0.1
	r.Size = Vector3.new(0.05, size * 0.1, size * 0.1)
	r.CFrame = at * CFrame.Angles(0, math.rad(90), 0)
	r.Parent = workspace
	tween(r, 0.6, { Size = Vector3.new(0.05, size * 1.6, size * 1.6), Transparency = 1 })
	game:GetService("Debris"):AddItem(r, 0.7)
end

-- Ouverture « en vrai » sur le booster de l'autel, fidèle à l'animation
-- Claude Design : le sachet se soulève et tremble, la bande du haut
-- s'arrache (étincelles + éclair), les cartes sortent une à une puis
-- s'ouvrent en éventail (éclair), et la carte de l'élément obtenu se
-- retourne dans une explosion à sa couleur. La pose finale est conservée.
function BoosterFX.playWorldOpening(rarityColor: Color3, rarityOrder: number, shake: (number, number) -> (), element: string?): boolean
	local d = BoosterFX.Display
	if not (d and d.Model.Parent and (d.Rig or d.Tracks.Open)) then
		return false
	end
	local camera = workspace.CurrentCamera
	local character = game:GetService("Players").LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (camera and root) or (root.Position - d.Center).Magnitude > 40 then
		return false
	end
	local model = d.Model
	local state = d.State
	local toPlayer = Vector3.new(root.Position.X - d.Center.X, 0, root.Position.Z - d.Center.Z)
	if toPlayer.Magnitude < 0.1 then
		toPlayer = Vector3.new(0, 0, 1)
	end
	toPlayer = toPlayer.Unit
	-- Face avant du sachet tournée vers le joueur.
	state.Yaw = math.atan2(-toPlayer.X, -toPlayer.Z)
	state.Roll = 0
	state.Opening = true

	-- Caméra : cadrage serré puis recul quand les cartes s'ouvrent en éventail.
	local previousType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	local h = math.max(d.Size.Y, 1)
	local focus = d.Center + Vector3.new(0, h * 0.1, 0)
	local function eyeAt(k: number): CFrame
		local dist = h * (2.3 + 1.1 * k) + 2
		local target = focus + Vector3.new(0, h * 0.35 * k, 0)
		return CFrame.lookAt(target + toPlayer * dist + Vector3.new(0, h * 0.15, 0), target)
	end
	tween(camera, 0.6, { CFrame = eyeAt(0) }, Enum.EasingStyle.Sine).Completed:Wait()

	for part, transparency in pairs(d.Cards) do
		part.Transparency = transparency
	end
	if d.Tracks.Idle then
		d.Tracks.Idle:Stop(0.15)
	end
	local start = os.clock()
	local rig = d.Rig
	local poseConn
	if rig then
		poseConn = RunService.RenderStepped:Connect(function()
			rig:pose(math.min(os.clock() - start, OPEN_DUR))
		end)
	else
		playAndHold(d.Tracks.Open, OPEN_DUR)
	end
	model:SetAttribute("Opening", true)

	local top = findBone(model, "haut")
	local tore, fanned = false, false
	while true do
		local t = os.clock() - start
		-- Recul progressif de la caméra entre 0,9 s et 1,9 s.
		local k = math.clamp((t - 0.9) / 1.0, 0, 1)
		k = k * k * (3 - 2 * k)
		camera.CFrame = camera.CFrame:Lerp(eyeAt(k), 0.15)
		if not tore and t >= T_TEAR then
			tore = true
			local at = top and top.TransformedWorldCFrame.Position or (d.Center + Vector3.new(0, h * 0.45, 0))
			sparks(at, { Color3.fromRGB(255, 217, 115), Color3.fromRGB(255, 153, 64), Color3.fromRGB(128, 217, 255), Color3.fromRGB(217, 179, 255) }, 70, h / 3)
			flash(at, Color3.fromRGB(255, 225, 160), h * 0.9)
			if rarityOrder >= 4 then
				shake(0.25, 0.25)
			end
		end
		if not fanned and t >= T_FAN - 0.25 then
			fanned = true
			local at = d.Center + Vector3.new(0, h * 0.55, 0) + toPlayer * h * 0.3
			sparks(at, { Color3.fromRGB(255, 217, 115), Color3.fromRGB(128, 217, 255), rarityColor }, 90, h / 2.5)
			flash(at, rarityColor:Lerp(Color3.new(1, 1, 1), 0.5), h * 1.4)
		end
		if t >= OPEN_DUR then
			break
		end
		task.wait()
	end

	-- La carte de l'élément obtenu se retourne, explosion à sa couleur.
	local index = ELEMENT_CARD[element or ""] or 2
	local flipTrack = d.Tracks["Flip" .. index]
	local flipConn
	if rig then
		local flipStart = os.clock()
		flipConn = RunService.RenderStepped:Connect(function()
			rig:flip(index, math.min((os.clock() - flipStart) / FLIP_DUR, 1))
		end)
	end
	if rig or flipTrack then
		if not rig and flipTrack then
			playAndHold(flipTrack, FLIP_DUR)
		end
		task.wait(FLIP_DUR * 0.55)
		local bone = findBone(model, "carte_" .. index .. "_mesh")
		local at = bone and bone.TransformedWorldCFrame * CFrame.new(0, h * 0.25, 0) or CFrame.new(d.Center)
		local color = CARD_COLORS[index]
		sparks(at.Position, { color, Color3.new(1, 1, 1) }, 80, h / 3)
		flash(at.Position, color, h * 1.1)
		ring(CFrame.lookAt(at.Position, at.Position + toPlayer), color, h)
		task.wait(FLIP_DUR * 0.45 + 0.5)
	else
		task.wait(0.6)
	end

	-- Retour à l'état de présentoir après la révélation.
	task.delay(2, function()
		if poseConn then
			poseConn:Disconnect()
		end
		if flipConn then
			flipConn:Disconnect()
		end
		for _, key in ipairs({ "Open", "Flip1", "Flip2", "Flip3" }) do
			if d.Tracks[key] then
				d.Tracks[key]:Stop(0.3)
			end
		end
		task.wait(0.3)
		for part in pairs(d.Cards) do
			part.Transparency = 1
		end
		if d.Tracks.Idle then
			d.Tracks.Idle:Play(0.3)
		end
		model:SetAttribute("Opening", nil)
		state.Opening = false
	end)
	camera.CameraType = previousType
	return true
end

-- Joue l'ouverture dans `parent`. Retourne false si aucun modèle.
function BoosterFX.playOpening(parent: GuiObject, rarityColor: Color3, rarityOrder: number, shake: (number, number) -> ()): boolean
	local template = BoosterFX.template()
	if not template then
		return false
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(170, 160, 200)
	viewport.LightColor = Color3.fromRGB(255, 245, 230)
	viewport.LightDirection = Vector3.new(-0.5, -0.6, -1)
	viewport.ZIndex = parent.ZIndex + 1
	viewport.ImageTransparency = 1
	viewport.Parent = parent
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local model, tracks = prepare(template)
	model:PivotTo(CFrame.new())
	model.Parent = world
	-- Caméra reculée selon la taille du modèle (cartes qui jaillissent comprises).
	local _, size = visibleBounds(model)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 35
	local distance = math.max(size.Y * 1.9, size.X * 2.4) / math.tan(math.rad(cam.FieldOfView / 2)) * 0.5
	cam.CFrame = CFrame.lookAt(Vector3.new(0, size.Y * 0.25, distance), Vector3.new(0, size.Y * 0.25, 0))
	cam.Parent = viewport
	viewport.CurrentCamera = cam

	local yaw = Instance.new("NumberValue")
	yaw.Value = -40
	local roll = 0
	local conn = RunService.RenderStepped:Connect(function()
		model:PivotTo(CFrame.Angles(0, math.rad(yaw.Value), math.rad(roll)))
	end)

	-- 1. Le sachet arrive en tournant.
	tween(viewport, 0.3, { ImageTransparency = 0 })
	tween(yaw, 0.7, { Value = 0 }, Enum.EasingStyle.Back).Completed:Wait()
	-- 2. Il tremble de plus en plus fort, éclairé à la couleur de la rareté.
	viewport.LightColor = Color3.fromRGB(255, 245, 230):Lerp(rarityColor, 0.35)
	for i = 1, 6 + rarityOrder * 2 do
		roll = ((i % 2 == 0) and 1 or -1) * (2 + i * 0.7)
		task.wait(0.05)
	end
	roll = 0
	if rarityOrder >= 4 then
		shake(0.3, 0.3)
	end

	if tracks.Open then
		-- 3. Animations du fichier : ouverture, puis les cartes se retournent.
		playAndWait(tracks.Open)
		for _, key in ipairs({ "Flip1", "Flip2", "Flip3" }) do
			if tracks[key] then
				tracks[key]:Play(0.05)
				task.wait(0.12)
			end
		end
		task.wait(0.6)
	else
		-- 3 bis. Ouverture animée par script : le rabat s'arrache, les cartes jaillissent.
		conn:Disconnect()
		local top = findPart(model, "haut")
		if top then
			tween(top, 0.5, { CFrame = top.CFrame * CFrame.new(1.5, 4, 1) * CFrame.Angles(math.rad(70), math.rad(40), math.rad(-30)), Transparency = 1 })
		end
		task.wait(0.15)
		local cards = {}
		for i = 1, 3 do
			local c = findPart(model, "carte_" .. i)
			if c then
				table.insert(cards, c)
			end
		end
		for i, c in ipairs(cards) do
			local startCf = c.CFrame
			local spread = i - (#cards + 1) / 2
			tween(c, 0.45, { CFrame = CFrame.new(startCf.Position + Vector3.new(spread * size.X * 0.4, size.Y * 0.7, 1.5)) * (startCf - startCf.Position)
				* CFrame.Angles(0, 0, math.rad(-spread * 12)) }, Enum.EasingStyle.Back)
			task.wait(0.08)
		end
		task.wait(0.4)
		for _, c in ipairs(cards) do
			tween(c, 0.35, { CFrame = c.CFrame * CFrame.Angles(0, math.pi, 0) })
		end
		task.wait(0.35)
	end
	if conn.Connected then
		conn:Disconnect()
	end

	-- 4. Tout s'efface dans l'éclair de lumière qui suit.
	tween(viewport, 0.25, { ImageTransparency = 1 }).Completed:Once(function()
		viewport:Destroy()
	end)
	return true
end

BoosterFX.prepare = prepare
BoosterFX.visibleBounds = visibleBounds

return BoosterFX
