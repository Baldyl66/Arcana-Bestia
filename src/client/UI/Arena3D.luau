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
local RigPlayer = require(script.Parent:WaitForChild("RigPlayer"))
local Freeze = require(script.Parent:WaitForChild("Freeze"))

local Arena3D = {}
Arena3D.__index = Arena3D

local L = VillageData.Layout
local PLAYER_DIST = 20 -- les duellistes (placés par le serveur)
local ANIMA_DIST = 10 -- les Anima, devant leur dresseur
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

-------------------------------------------------------------------------------
-- Animations propres à une créature (modèles 3D faits dans Claude Design)
-------------------------------------------------------------------------------
-- Le GLB d'un Anima porte des clips nommés « <id>_<Clip> » (ex. flamichat_Repos,
-- flamichat_GriffeArdente). Clips reconnus : Repos, Apparition, Course, Attaque,
-- Degats, KO et la capacité (son nom sans espaces ni accents, ou « Capacite »).
-- En Studio, l'import les range en KeyframeSequence (recopiées dans le modèle par
-- Assets.server.luau). En jeu publié : publier les animations et mettre leurs ids
-- en attributs Anim_<Clip> sur le modèle de ReplicatedStorage.Animas.
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local CLIP_LOOP = { Repos = true, Course = true }
local clipIds: { [string]: string } = {} -- [id_clip en minuscules] = id d'animation ("" = absent)
local animSets = setmetatable({}, { __mode = "k" }) -- [Model] = { Animator, CardId, Template, Tracks }

-- Pièces des modèles Claude Design : { couleur, matériau, transparence } d'après leur nom
-- (« pelage2 » se lit « pelage »).
local PIECES = {
	flamme_rouge = { Color3.fromRGB(226, 64, 12), Enum.Material.Neon, 0.2 },
	flamme_orange = { Color3.fromRGB(255, 122, 22), Enum.Material.Neon, 0.05 },
	flamme_jaune = { Color3.fromRGB(255, 200, 62), Enum.Material.Neon, 0 },
	braise = { Color3.fromRGB(255, 84, 16), Enum.Material.Neon, 0 },
	yeux = { Color3.fromRGB(255, 165, 20), Enum.Material.Neon, 0 },
	cornee = { Color3.fromRGB(255, 255, 255), Enum.Material.Glass, 0.75 },
	pelage = { Color3.fromRGB(38, 34, 31), Enum.Material.Fabric, 0 },
	poils = { Color3.fromRGB(29, 26, 24), Enum.Material.Fabric, 0 },
	pelage_sombre = { Color3.fromRGB(23, 20, 26), Enum.Material.Fabric, 0 },
	oreille_int = { Color3.fromRGB(90, 36, 20), Enum.Material.SmoothPlastic, 0 },
	pupilles = { Color3.fromRGB(13, 7, 4), Enum.Material.SmoothPlastic, 0 },
	griffes = { Color3.fromRGB(228, 220, 205), Enum.Material.SmoothPlastic, 0 },
	nez = { Color3.fromRGB(59, 38, 36), Enum.Material.SmoothPlastic, 0 },
	moustaches = { Color3.fromRGB(226, 219, 207), Enum.Material.SmoothPlastic, 0 },
}
-- Os qui portent de vraies flammes (particules) sur les créatures importées.
local FX_BONES = { Cou = 10, Queue6 = 8, Tete = 4 }

local ACCENTS = { ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["à"] = "a", ["â"] = "a", ["î"] = "i", ["ï"] = "i",
	["ô"] = "o", ["û"] = "u", ["ù"] = "u", ["ç"] = "c", ["É"] = "E", ["È"] = "E" }
-- « Griffe ardente » -> « GriffeArdente »
local function clipName(text: string): string
	local out = {}
	for word in string.gmatch(text, "[^%s'%-]+") do
		for from, to in pairs(ACCENTS) do
			word = string.gsub(word, from, to)
		end
		table.insert(out, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return table.concat(out)
end

local function clipId(template: Instance, cardId: string, clip: string): string?
	local attr = template:GetAttribute("Anim_" .. clip)
	if type(attr) == "string" and attr ~= "" then
		return attr
	end
	local key = string.lower(cardId .. "_" .. clip)
	if clipIds[key] == nil then
		clipIds[key] = ""
		for _, holder in ipairs({ template, ReplicatedStorage:FindFirstChild("Animas") }) do
			for _, d in ipairs(holder and holder:GetDescendants() or {}) do
				if d:IsA("KeyframeSequence") and string.find(string.lower(d.Name), key, 1, true) then
					local ok, id = pcall(KeyframeSequenceProvider.RegisterKeyframeSequence, KeyframeSequenceProvider, d)
					if ok and type(id) == "string" then
						clipIds[key] = id
					end
					break
				end
			end
			if clipIds[key] ~= "" then
				break
			end
		end
	end
	return if clipIds[key] ~= "" then clipIds[key] else nil
end

-- Nom des animations des modèles en voxels animés (fichier .glb converti).
local RIG_CLIPS = { Repos = "repos", Course = "course", Degats = "coup_recu", KO = "ko", Apparition = "victoire", Attaque = "griffe_ardente",
	Marche = "marche", Victoire = "victoire" }
local function rigClip(model: Model, clip: string): string?
	if RigPlayer.has(model, RIG_CLIPS[clip] or "") then
		return RIG_CLIPS[clip]
	end
	-- Capacité : « GriffeArdente » ↔ « griffe_ardente ».
	local want = string.lower((string.gsub(clip, "[_%s]", "")))
	for _, candidate in ipairs({ string.lower(clip), (string.gsub(string.lower(clip), "(%l)(%u)", "%1_%2")) }) do
		if RigPlayer.has(model, candidate) then
			return candidate
		end
	end
	for _, name in ipairs({ "griffe_ardente", "repos", "marche", "course", "coup_recu", "ko", "victoire" }) do
		if string.lower((string.gsub(name, "_", ""))) == want and RigPlayer.has(model, name) then
			return name
		end
	end
	return nil
end

-- Joue un clip de la créature ; renvoie nil si elle ne l'a pas (modèle provisoire, etc.).
local function playClip(model: Model?, clip: string, fade: number?, speed: number?): AnimationTrack?
	if model and RigPlayer.isRig(model) then
		local name = rigClip(model, clip)
		if name and RigPlayer.play(model, name, speed) then
			return true :: any
		end
		return nil
	end
	local set = model and animSets[model]
	if not set or not (model :: Model).Parent then
		return nil
	end
	local track = set.Tracks[clip]
	if track == nil then
		track = false
		local id = clipId(set.Template, set.CardId, clip)
		if id then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, result = pcall(set.Animator.LoadAnimation, set.Animator, anim)
			if ok and result then
				result.Looped = CLIP_LOOP[clip] == true
				result.Priority = if clip == "Repos" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Action
				track = result
			end
		end
		set.Tracks[clip] = track
	end
	if track then
		track:Play(fade or 0.12, 1, speed or 1)
		return track
	end
	return nil
end

local function stopClip(model: Model?, clip: string, fade: number?)
	if model and RigPlayer.isRig(model) then
		local name = rigClip(model, clip)
		if name then
			RigPlayer.stop(model, name)
		end
		return
	end
	local set = model and animSets[model]
	local track = set and set.Tracks[clip]
	if track then
		track:Stop(fade or 0.15)
	end
end

-- Clip de la capacité d'une créature (ex. « GriffeArdente »), sinon « Capacite », sinon « Attaque ».
local function playAbilityClip(model: Model?, card): AnimationTrack?
	local name = card and card.Ability and card.Ability.Name
	return (name and playClip(model, clipName(name))) or playClip(model, "Capacite") or playClip(model, "Attaque")
end

-- Centre des pièces visibles (les os et pièces techniques de l'import faussent GetBoundingBox).
local function visibleCenter(m: Model): Vector3
	local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
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
		return m:GetPivot().Position
	end
	return (minV + maxV) / 2
end

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

-- Anima en cubes, à partir des données de ReplicatedStorage.Voxels
-- (générées depuis un sprite pixel art par tools/sprite_to_voxel.py).
-- Le sprite est dans le plan X (vers la tête) / Y (vers le haut), avec une
-- épaisseur en Z ; les couleurs très vives (flammes, yeux) passent en Neon.
local DEPTH = 3 -- épaisseur par défaut (anciennes données sans relief)
local function voxelModel(data): Model
	local model = Instance.new("Model")
	local cx, cy = data.W / 2, data.H / 2
	local biggest: BasePart? = nil
	for _, b in ipairs(data.Boxes) do
		local color = data.Palette[b[5]]
		local bright = math.max(color.R, color.G, color.B) > 0.9 and color.R > 0.8 and color.B < 0.45
		local p = part({ Size = Vector3.new(b[3], b[4], b[6] or DEPTH), Color = color, Material = bright and Enum.Material.Neon or Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(b[1] + b[3] / 2 - cx, b[2] + b[4] / 2 - cy, 0), Parent = model })
		if bright then
			p:SetAttribute("Flame", true)
		end
		if not biggest or p.Size.Magnitude > biggest.Size.Magnitude then
			biggest = p
		end
	end
	model.PrimaryPart = biggest
	model.WorldPivot = CFrame.new()
	model:SetAttribute("Voxel", true)
	return model
end

local function buildAnima(cardId: string, level: number?): (Model, number)
	local card = CardsData.CardById[cardId]
	-- Les formes évoluées sont plus grandes.
	local _, stage = CardsData.stageOf(level or 1)
	local size = (SIZE[card and card.Rarity or "Commun"] or 3) * stage.Scale
	local folder = ReplicatedStorage:FindFirstChild("Animas")
	local source = folder and folder:FindFirstChild(cardId)
	local voxels = ReplicatedStorage:FindFirstChild("Voxels")
	local voxelData = voxels and voxels:FindFirstChild(cardId)
	local rigs = ReplicatedStorage:FindFirstChild("Rigs")
	local rigData = rigs and rigs:FindFirstChild(cardId)
	local model: Model
	if rigData and rigData:IsA("ModuleScript") and not (source and source:IsA("Model")) then
		-- Créature en voxels animée (membres, marche, attaques...).
		model = RigPlayer.build(require(rigData) :: any, size)
	elseif voxelData and voxelData:IsA("ModuleScript") and not (source and source:IsA("Model")) then
		-- Créature en cubes : mise à l'échelle comme les modèles importés.
		model = voxelModel(require(voxelData) :: any)
		local _, box = model:GetBoundingBox()
		local largest = math.max(box.X, box.Y, box.Z)
		if largest > 0 then
			model:ScaleTo(size * 1.6 / largest)
		end
	elseif source and source:IsA("Model") then
		model = source:Clone()
		local _, box = model:GetBoundingBox()
		local largest = math.max(box.X, box.Y, box.Z)
		if largest > 0 then
			model:ScaleTo(model:GetScale() * size * 1.4 / largest)
		end
		local mainPart: BasePart? = nil
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				-- Pièces nommées (flammes, braises, yeux…) : Neon et couleur de la palette.
				local piece = PIECES[(string.gsub(string.lower(d.Name), "[%.%d]+$", ""))]
				if piece then
					d.Color = piece[1]
					d.Material = piece[2]
					d.Transparency = piece[3]
					if piece[2] == Enum.Material.Neon or piece[2] == Enum.Material.Glass then
						d.CastShadow = false
					end
				end
				if not mainPart or d.Size.Magnitude > mainPart.Size.Magnitude then
					mainPart = d
				end
			elseif d:IsA("KeyframeSequence") or d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			end
		end
		if not model.PrimaryPart then
			model.PrimaryPart = mainPart
		end
		-- Pivot au centre visible, tourné vers l'avant de la créature (os Tete devant Bassin),
		-- quel que soit l'axe d'export du GLB : Arena3D oriente l'Anima avec ce pivot.
		local head, hips
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Bone") then
				if d.Name == "Tete" then
					head = d
				elseif d.Name == "Bassin" then
					hips = d
				end
				-- Flammes vivantes accrochées aux os : elles suivent les animations.
				local rate = FX_BONES[d.Name]
				if rate and card then
					local fx = emitter(d, card.Element, rate)
					fx.Name = "FlammeVive"
					fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.22), NumberSequenceKeypoint.new(1, 0) })
				end
			end
		end
		local root = model.PrimaryPart
		if root then
			local center = visibleCenter(model)
			local forward = if head and hips then (head.WorldPosition - hips.WorldPosition) * Vector3.new(1, 0, 1) else Vector3.zero
			local pivot = if forward.Magnitude > 1e-3 then CFrame.lookAt(center, center + forward.Unit) else CFrame.new(center) * root.CFrame.Rotation
			root.PivotOffset = root.CFrame:ToObjectSpace(pivot)
		end
		-- Lecteur d'animations (clips chargés à la demande, voir playClip).
		local controller = model:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController")
		controller.Parent = model
		local animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = controller
		animSets[model] = { Animator = animator, CardId = cardId, Template = source, Tracks = {} }
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
			Key = key,
			Dir = dir,
			PlayerSpot = self.Center + dir * PLAYER_DIST,
			Spot = self.Center + dir * ANIMA_DIST,
			UserId = data[key].UserId,
		}
	end
	-- Plan de combat face à face : caméra derrière ton Anima (vu de dos, en
	-- bas à gauche), l'adversaire en face, au fond à droite.
	local meDir = self.Sides.Me.Dir
	local forward = -meDir
	local right = forward:Cross(Vector3.yAxis)
	self.SideVec = right
	local camPos = self.Center + meDir * (ANIMA_DIST + 7) + right * 5 + Vector3.new(0, 6, 0)
	self.Wide = CFrame.lookAt(camPos, self.Center + forward * 4 + Vector3.new(0, 2, 0))
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
		-- Personnage immobile pendant le combat.
		Freeze.hold("Combat")
		self.Frozen = true
	end
	self.StepName = self.Spectator and "ArcanaArena3DSpec" or "ArcanaArena3D"
	local t0 = os.clock()
	RunService:BindToRenderStep(self.StepName, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local k = 1 - math.exp(-dt * (self.CamSpeed or 6))
		self.CamCF = self.CamCF:Lerp(self.CamTarget, k)
		local t = os.clock() - t0
		-- Légère respiration du plan (pas pour les spectateurs : caméra libre).
		if not self.Spectator then
			local cf = self.CamCF * CFrame.new(math.sin(t * 0.4) * 0.3, math.sin(t * 0.55) * 0.2, 0)
			-- Jamais sous la piste : la caméra reste au-dessus du sol.
			local minY = self.Center.Y + 2
			if cf.Position.Y < minY then
				cf = cf + Vector3.new(0, minY - cf.Position.Y, 0)
			end
			camera.CFrame = cf
		end
		-- Les Anima flottent doucement.
		for key, s in pairs(self.Sides) do
			if s.Model and s.Model.Parent and not s.Busy then
				local phase = key == "Me" and 0 or math.pi
				local bob = math.sin(t * 2 + phase) * 0.25
				if s.Rig then
					s.Model:PivotTo(s.Home)
				elseif s.Voxel then
					local sway = math.sin(t * 0.9 + phase) * 0.32
					local breath = math.sin(t * 2.2 + phase) * 0.035
					s.Model:PivotTo(s.Home * CFrame.new(0, bob, 0) * CFrame.Angles(0, sway, breath))
					-- Quelques flammes changent d'éclat à chaque image.
					local flames = s.Flames
					if flames and #flames > 0 then
						for _ = 1, math.min(10, #flames) do
							flames[math.random(1, #flames)].Transparency = math.random() * 0.45
						end
					end
				else
					s.Model:PivotTo(s.Home * CFrame.new(0, bob, 0))
				end
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
	local pos = if s.Rig then s.Spot + Vector3.new(0, (s.HalfHeight or size * 0.5) + 0.05, 0) else s.Spot + Vector3.new(0, size * 0.5 + 1.2, 0)
	-- Anima en cubes (découpé, plat) : sa face regarde la caméra du plan de
	-- combat, la tête vers l'adversaire (à droite de l'écran pour ton Anima,
	-- à gauche pour celui d'en face).
	if s.Voxel and self.Wide then
		local toCam = (self.Wide.Position - pos) * Vector3.new(1, 0, 1)
		if toCam.Magnitude > 1e-3 then
			toCam = toCam.Unit
			return CFrame.lookAt(pos, pos + (key == "Me" and -toCam or toCam))
		end
	end
	-- Face à face avec l'adversaire.
	local toward = self.Center - s.Dir
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

-- Gerbe de particules ponctuelle.
function Arena3D:burst(pos: Vector3, color: Color3, texture: string, count: number, speed: number, size: number, accel: Vector3?)
	local holder = part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos), Parent = self.Folder })
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4), color)
	e.LightEmission = 0.9
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = accel or Vector3.zero
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = holder
	e:Emit(count)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

-- Pièce d'effet qui grandit puis s'efface.
function Arena3D:flare(props, grow: Vector3, life: number)
	props.Parent = self.Folder
	local p = part(props)
	tween(p, life * 0.4, { Size = grow }, Enum.EasingStyle.Quint)
	task.delay(life * 0.4, function()
		tween(p, life * 0.6, { Transparency = 1 })
	end)
	task.delay(life + 0.1, function()
		p:Destroy()
	end)
	return p
end

-- Impact propre à l'élément de l'attaquant (plus spectaculaire pour une capacité).
function Arena3D:elementFX(element: string, from: Vector3, target: Vector3, targetSize: number, ability: boolean)
	local el = CardsData.Elements[element] or CardsData.Elements.Feu
	local color = el.Color
	local k = ability and 1.6 or 1
	local ground = Vector3.new(target.X, self.Center.Y + 0.1, target.Z)
	local flat = CFrame.Angles(0, 0, math.rad(90))
	if element == "Feu" then
		-- Explosion de flammes et onde de chaleur au sol.
		self:flare({ Shape = Enum.PartType.Ball, Size = Vector3.one, Color = Color3.fromRGB(255, 170, 60), Material = Enum.Material.Neon, Transparency = 0.2,
			CFrame = CFrame.new(target) }, Vector3.one * targetSize * 1.8 * k, 0.6)
		self:burst(target, color, TEX.Fire, math.floor(45 * k), 14, 2.2, Vector3.new(0, 12, 0))
		self:flare({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2, 2), Color = color, Material = Enum.Material.Neon, Transparency = 0.2,
			CFrame = CFrame.new(ground) * flat }, Vector3.new(0.2, 16 * k, 16 * k), 0.7)
		if ability then
			self:pillar(ground, color, 14)
		end
	elseif element == "Eau" then
		-- Vague qui se dresse puis s'écrase, éclaboussures.
		local dir = (target - from) * Vector3.new(1, 0, 1)
		dir = dir.Magnitude > 0 and dir.Unit or Vector3.zAxis
		local wave = part({ Size = Vector3.new(targetSize * 2.5 * k, 0.5, 1.5), Color = color, Material = Enum.Material.Glass, Transparency = 0.25,
			CFrame = CFrame.lookAt(ground - dir * 2, ground - dir * 2 + dir), Parent = self.Folder })
		local height = targetSize * 2.2 * k
		tween(wave, 0.25, { Size = Vector3.new(wave.Size.X, height, 1.5), CFrame = wave.CFrame + Vector3.new(0, height / 2, 0) }, Enum.EasingStyle.Quint)
		task.delay(0.25, function()
			tween(wave, 0.35, { CFrame = wave.CFrame * CFrame.new(0, -height / 2, -2) * CFrame.Angles(math.rad(-70), 0, 0), Transparency = 1 }, Enum.EasingStyle.Quad,
				Enum.EasingDirection.In)
		end)
		task.delay(0.7, function()
			wave:Destroy()
		end)
		self:burst(target, color, TEX.Spark, math.floor(50 * k), 16, 1, Vector3.new(0, -30, 0))
		self:flare({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2, 2), Color = Color3.fromRGB(200, 240, 255), Material = Enum.Material.Neon,
			Transparency = 0.3, CFrame = CFrame.new(ground) * flat }, Vector3.new(0.2, 14 * k, 14 * k), 0.8)
	elseif element == "Nature" then
		-- Épines qui jaillissent du sol autour de la cible, feuilles.
		local count = ability and 8 or 5
		for i = 1, count do
			local a = (i / count) * math.pi * 2 + math.random() * 0.4
			local r = targetSize * 0.7 + math.random() * 1.2
			local base = ground + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local h = (2.5 + math.random() * 2) * k
			local spike = part({ ClassName = "WedgePart", Size = Vector3.new(0.6, 0.1, 1.2), Color = Color3.fromRGB(70, 140, 60), Material = Enum.Material.Grass,
				CFrame = CFrame.lookAt(base, target) * CFrame.Angles(math.rad(-20), 0, 0), Parent = self.Folder })
			tween(spike, 0.18, { Size = Vector3.new(0.6, h, 1.2), CFrame = spike.CFrame * CFrame.new(0, h / 2, 0) }, Enum.EasingStyle.Back)
			task.delay(0.8, function()
				tween(spike, 0.3, { Size = Vector3.new(0.6, 0.1, 1.2), Transparency = 1 })
			end)
			task.delay(1.2, function()
				spike:Destroy()
			end)
		end
		self:burst(target, color, TEX.Spark, math.floor(35 * k), 9, 0.9, Vector3.new(0, -4, 0))
	elseif element == "Foudre" then
		-- Éclair en zigzag tombé du ciel sur la cible.
		local top = target + Vector3.new(0, 30, 0)
		local points = { top }
		local steps = 7
		for i = 1, steps - 1 do
			local p = top:Lerp(target, i / steps)
			table.insert(points, p + Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3))
		end
		table.insert(points, target)
		local bolts = ability and 2 or 1
		for b = 1, bolts do
			for i = 1, #points - 1 do
				local p1, p2 = points[i], points[i + 1]
				if b == 2 then
					p1 += Vector3.new(1.2, 0, -1.2)
					p2 += Vector3.new(1.2, 0, -1.2)
				end
				local seg = part({ Size = Vector3.new(0.35 * k, 0.35 * k, (p2 - p1).Magnitude), Color = Color3.fromRGB(255, 250, 200), Material = Enum.Material.Neon,
					CFrame = CFrame.lookAt((p1 + p2) / 2, p2), Parent = self.Folder })
				task.delay(0.1 + b * 0.05, function()
					tween(seg, 0.25, { Transparency = 1 })
				end)
				task.delay(0.5, function()
					seg:Destroy()
				end)
			end
		end
		self:flashScreen(ability and 0.5 or 0.3)
		self:burst(target, color, TEX.Spark, math.floor(55 * k), 22, 0.8)
		self:flare({ Shape = Enum.PartType.Ball, Size = Vector3.one, Color = color, Material = Enum.Material.Neon, Transparency = 0.3, CFrame = CFrame.new(target) },
			Vector3.one * targetSize * 1.5 * k, 0.4)
	elseif element == "Ombre" then
		-- Sphère de ténèbres qui se referme sur la cible, fumée violette.
		local orb = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * targetSize * 3 * k, Color = Color3.fromRGB(25, 10, 45), Material = Enum.Material.Neon,
			Transparency = 0.6, CFrame = CFrame.new(target), Parent = self.Folder })
		tween(orb, 0.3, { Size = Vector3.one * targetSize * 0.6, Transparency = 0.1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.3, function()
			tween(orb, 0.4, { Size = Vector3.one * targetSize * 2.4 * k, Transparency = 1 }, Enum.EasingStyle.Quint)
		end)
		task.delay(0.8, function()
			orb:Destroy()
		end)
		self:burst(target, color, TEX.Smoke, math.floor(30 * k), 6, 2.5, Vector3.new(0, 2, 0))
	else
		-- Lumière : rayon céleste et éclats dorés.
		local h = 40
		local beam = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 0.3, 0.3), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon,
			Transparency = 0.1, CFrame = CFrame.new(ground + Vector3.new(0, h / 2, 0)) * flat, Parent = self.Folder })
		tween(beam, 0.2, { Size = Vector3.new(h, targetSize * 1.6 * k, targetSize * 1.6 * k) }, Enum.EasingStyle.Quint)
		task.delay(0.35, function()
			tween(beam, 0.5, { Size = Vector3.new(h, 0.2, 0.2), Transparency = 1 })
		end)
		task.delay(0.9, function()
			beam:Destroy()
		end)
		self:flashScreen(ability and 0.45 or 0.25)
		self:burst(target, Color3.fromRGB(255, 225, 140), TEX.Spark, math.floor(50 * k), 12, 1.2)
	end
end

-- Aura de charge élémentaire autour de l'attaquant (capacités).
function Arena3D:chargeFX(element: string, pos: Vector3, size: number)
	local el = CardsData.Elements[element] or CardsData.Elements.Feu
	local tex = element == "Feu" and TEX.Fire or (element == "Ombre" and TEX.Smoke or TEX.Spark)
	self:burst(pos, el.Color, tex, 30, 4, 1.2, Vector3.new(0, 6, 0))
	self:flare({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, Color = el.Color, Material = Enum.Material.ForceField, CFrame = CFrame.new(pos) },
		Vector3.one * size * 2.2, 0.7)
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
function Arena3D:SetActive(key: string, cardId: string?, knockedOut: boolean?, level: number?)
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
			-- K.O. : animation de la créature si elle en a une, puis bascule, s'enfonce et s'efface.
			stopClip(old, "Repos", 0.1)
			playClip(old, "KO", 0.1, 1.3)
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
	local model, size = buildAnima(cardId, level)
	s.Size = size
	s.Voxel = model:GetAttribute("Voxel") == true
	s.Rig = model:GetAttribute("Rig") == true
	s.HalfHeight = model:GetAttribute("HalfHeight")
	s.Flames = {}
	if s.Voxel then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("Flame") then
				table.insert(s.Flames, d)
			end
		end
	end
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
		playClip(model, "Repos", 0)
		playClip(model, "Apparition", 0)
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
	local function deckFirst(key: string): (string?, number?)
		local deck = self.Data[key].Deck or {}
		for _, f in ipairs(deck) do
			if f.Active then
				return f.Id, f.Level
			end
		end
		return deck[1] and deck[1].Id, deck[1] and deck[1].Level
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
		local id, level = deckFirst(key)
		self:SetActive(key, id, nil, level)
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


-------------------------------------------------------------------------------
-- Capacités uniques : briques d'effets réutilisables
-------------------------------------------------------------------------------
-- Pièce d'effet qui s'efface après `delay` puis disparaît.
local function vanish(p: Instance, delay: number, duration: number)
	task.delay(delay, function()
		if p.Parent then
			if p:IsA("BasePart") then
				tween(p, duration, { Transparency = 1 })
			end
		end
	end)
	task.delay(delay + duration + 0.05, function()
		p:Destroy()
	end)
end

-- Repère tourné vers la caméra (les effets « dessinés » restent lisibles).
local function camBasis(pos: Vector3): CFrame
	local cam = workspace.CurrentCamera
	local c = cam and cam.CFrame or CFrame.new()
	return CFrame.fromMatrix(pos, c.RightVector, c.UpVector)
end

local function neon(props): BasePart
	props.Material = props.Material or Enum.Material.Neon
	return part(props)
end

-- Griffures : `count` entailles lumineuses en diagonale sur la cible.
function Arena3D:fxClaws(target: Vector3, color: Color3, count: number, size: number)
	for k = 1, count do
		local offset = (k - (count + 1) / 2) * size * 0.32
		local cf = camBasis(target) * CFrame.new(offset, 0, -size * 0.6) * CFrame.Angles(0, 0, math.rad(55))
		local slash = neon({ Size = Vector3.new(0.12, 0.2, 0.2), Color = color, CFrame = cf, Parent = self.Folder })
		task.delay((k - 1) * 0.06, function()
			tween(slash, 0.12, { Size = Vector3.new(size * 1.6, 0.2, 0.2) }, Enum.EasingStyle.Quint)
		end)
		vanish(slash, 0.25 + k * 0.06, 0.3)
	end
	self:burst(target, color, TEX.Spark, 25, 12, 0.6)
end

-- Projectile (bloquant) : boule lumineuse de `from` à `to`, avec arc.
function Arena3D:fxProjectile(from: Vector3, to: Vector3, color: Color3, size: number, duration: number, arc: number?, texture: string?)
	local ball = neon({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, Color = color, CFrame = CFrame.new(from), Parent = self.Folder })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = size * 6
	light.Brightness = 3
	light.Parent = ball
	local trail = emitter(ball, "Feu", 40)
	trail.Texture = texture or TEX.Spark
	trail.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4), color)
	trail.Size = NumberSequence.new(size * 0.8, 0)
	trail.Speed = NumberRange.new(0.5, 1.5)
	local start = os.clock()
	while os.clock() - start < duration and not self.Dead do
		local k = (os.clock() - start) / duration
		ball.CFrame = CFrame.new(from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * (arc or 0), 0))
		task.wait()
	end
	ball.CFrame = CFrame.new(to)
	trail.Enabled = false
	vanish(ball, 0, 0.15)
end

-- Rayon entre deux points (s'élargit puis s'amincit).
function Arena3D:fxBeam(from: Vector3, to: Vector3, color: Color3, width: number, life: number)
	local len = (to - from).Magnitude
	local beam = neon({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, 0.2, 0.2), Color = color,
		CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0), Parent = self.Folder })
	tween(beam, life * 0.25, { Size = Vector3.new(len, width, width) }, Enum.EasingStyle.Quint)
	task.delay(life * 0.5, function()
		tween(beam, life * 0.5, { Size = Vector3.new(len, 0.1, 0.1), Transparency = 1 })
	end)
	task.delay(life + 0.05, function()
		beam:Destroy()
	end)
end

-- Éclair en zigzag.
function Arena3D:fxBolt(from: Vector3, to: Vector3, color: Color3, width: number)
	local points = { from }
	for i = 1, 6 do
		local p = from:Lerp(to, i / 7)
		table.insert(points, p + Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3))
	end
	table.insert(points, to)
	for i = 1, #points - 1 do
		local p1, p2 = points[i], points[i + 1]
		local seg = neon({ Size = Vector3.new(width, width, (p2 - p1).Magnitude), Color = color, CFrame = CFrame.lookAt((p1 + p2) / 2, p2), Parent = self.Folder })
		vanish(seg, 0.12, 0.2)
	end
	self:burst(to, color, TEX.Spark, 30, 18, 0.7)
end

-- Pointes qui jaillissent du sol en cercle.
function Arena3D:fxSpikes(center: Vector3, color: Color3, material: Enum.Material, count: number, radius: number, height: number)
	local ground = Vector3.new(center.X, self.Center.Y + 0.1, center.Z)
	for i = 1, count do
		local ang = (i / count) * math.pi * 2 + math.random() * 0.3
		local base = ground + Vector3.new(math.cos(ang) * radius, 0, math.sin(ang) * radius)
		local h = height * (0.7 + math.random() * 0.5)
		local spike = part({ ClassName = "WedgePart", Size = Vector3.new(0.7, 0.1, 1.3), Color = color, Material = material,
			CFrame = CFrame.lookAt(base, ground) * CFrame.Angles(math.rad(-20), 0, 0), Parent = self.Folder })
		tween(spike, 0.16, { Size = Vector3.new(0.7, h, 1.3), CFrame = spike.CFrame * CFrame.new(0, h / 2, 0) }, Enum.EasingStyle.Back)
		vanish(spike, 0.9, 0.3)
	end
end

-- Tentacules / racines qui sortent du sol et se referment sur la cible.
function Arena3D:fxTentacles(center: Vector3, color: Color3, material: Enum.Material, count: number, radius: number, height: number)
	local ground = Vector3.new(center.X, self.Center.Y, center.Z)
	for i = 1, count do
		local ang = (i / count) * math.pi * 2
		local base = ground + Vector3.new(math.cos(ang) * radius, 0, math.sin(ang) * radius)
		local inward = CFrame.lookAt(base, ground)
		local t = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 0.9, 0.9), Color = color, Material = material,
			CFrame = inward * CFrame.Angles(0, 0, math.rad(90)), Parent = self.Folder })
		-- Pousse vers le haut puis se courbe vers le centre.
		tween(t, 0.25, { Size = Vector3.new(height, 0.9, 0.9), CFrame = inward * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)) }, Enum.EasingStyle.Back)
		task.delay(0.3, function()
			if t.Parent then
				tween(t, 0.2, { CFrame = inward * CFrame.Angles(math.rad(-35), 0, 0) * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)) })
			end
		end)
		vanish(t, 1, 0.3)
	end
end

-- Onde de choc au sol qui file de `from` à `to` en grandissant.
function Arena3D:fxShockwave(from: Vector3, to: Vector3, color: Color3, duration: number)
	local y = self.Center.Y + 0.15
	local ring = neon({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 2, 2), Color = color, Transparency = 0.2,
		CFrame = CFrame.new(Vector3.new(from.X, y, from.Z)) * CFrame.Angles(0, 0, math.rad(90)), Parent = self.Folder })
	tween(ring, duration, { Size = Vector3.new(0.25, 9, 9), CFrame = CFrame.new(Vector3.new(to.X, y, to.Z)) * CFrame.Angles(0, 0, math.rad(90)) }, Enum.EasingStyle.Quad)
	vanish(ring, duration, 0.25)
end

-- Anneaux concentriques (chant, rugissement, souffle).
function Arena3D:fxRings(pos: Vector3, color: Color3, count: number, maxSize: number, facing: Vector3?)
	for k = 1, count do
		task.delay((k - 1) * 0.12, function()
			local cf = facing and CFrame.lookAt(pos, pos + facing) * CFrame.Angles(0, math.rad(90), 0) or CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
			local r = neon({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 1, 1), Color = color, Transparency = 0.3, CFrame = cf, Parent = self.Folder })
			tween(r, 0.5, { Size = Vector3.new(0.15, maxSize, maxSize), Transparency = 1 }, Enum.EasingStyle.Quad)
			task.delay(0.55, function()
				r:Destroy()
			end)
		end)
	end
end

-- Pluie d'objets lumineux tombant sur une zone.
function Arena3D:fxRain(center: Vector3, color: Color3, count: number, duration: number, size: number, spread: number)
	for i = 1, count do
		task.delay((i - 1) / count * duration, function()
			if self.Dead then
				return
			end
			local land = center + Vector3.new((math.random() - 0.5) * spread, 0, (math.random() - 0.5) * spread)
			local p = neon({ Size = Vector3.new(size * 0.4, size * 1.6, size * 0.4), Color = color, CFrame = CFrame.new(land + Vector3.new(0, 18, 0)), Parent = self.Folder })
			tween(p, 0.3, { CFrame = CFrame.new(land) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.3, function()
				self:burst(land, color, TEX.Spark, 8, 6, 0.5)
				p:Destroy()
			end)
		end)
	end
end

-- Assombrit la scène (éclipse, nuit, vol nocturne).
function Arena3D:fxDarken(amount: number, duration: number)
	if self.Spectator then
		return
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Parent = Lighting
	tween(cc, 0.3, { Brightness = -amount, Saturation = -0.3 })
	task.delay(duration, function()
		tween(cc, 0.4, { Brightness = 0, Saturation = 0 })
	end)
	task.delay(duration + 0.45, function()
		cc:Destroy()
	end)
end

-- Coque de protection autour d'un Anima (matière et couleur au choix).
function Arena3D:fxShell(key: string, color: Color3, material: Enum.Material, shape: Enum.PartType?, life: number?)
	local s = self.Sides[key]
	if not (s and s.Model) then
		return
	end
	local p = part({ Shape = shape or Enum.PartType.Ball, Size = Vector3.one * s.Size * 0.6, Color = color, Material = material, Transparency = 0.35,
		CFrame = s.Model:GetPivot(), Parent = self.Folder })
	tween(p, 0.35, { Size = Vector3.one * s.Size * 2.1 }, Enum.EasingStyle.Back)
	vanish(p, life or 1.2, 0.4)
	return p
end

-- Bloc de glace qui emprisonne puis éclate.
function Arena3D:fxIce(target: Vector3, size: number)
	local ice = part({ Size = Vector3.one * 0.5, Color = Color3.fromRGB(170, 225, 255), Material = Enum.Material.Ice, Transparency = 0.3,
		CFrame = CFrame.new(target) * CFrame.Angles(0, math.rad(30), 0), Parent = self.Folder })
	tween(ice, 0.2, { Size = Vector3.new(size * 1.6, size * 1.9, size * 1.6) }, Enum.EasingStyle.Back)
	task.delay(0.8, function()
		self:burst(target, Color3.fromRGB(200, 240, 255), TEX.Spark, 50, 14, 0.9, Vector3.new(0, -20, 0))
		UIKit.playSound("Burst", 0.5, 1.4)
	end)
	vanish(ice, 0.8, 0.1)
end

-- Orbe qui grandit puis s'efface (soleil, lune noire...).
function Arena3D:fxOrb(pos: Vector3, color: Color3, material: Enum.Material, size: number, life: number): BasePart
	local orb = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = color, Material = material, CFrame = CFrame.new(pos), Parent = self.Folder })
	tween(orb, life * 0.4, { Size = Vector3.one * size }, Enum.EasingStyle.Quint)
	vanish(orb, life * 0.8, life * 0.2)
	return orb
end

-- Déplace un Anima (non bloquant) : CFrame interpolée.
function Arena3D:glide(s, cf: CFrame, duration: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	if not (s and s.Model) then
		return
	end
	local v = Instance.new("CFrameValue")
	v.Value = s.Model:GetPivot()
	v.Changed:Connect(function(x)
		if s.Model and s.Model.Parent then
			s.Model:PivotTo(x)
		end
	end)
	tween(v, duration, { Value = cf }, style, dir)
	task.delay(duration + 0.05, function()
		v:Destroy()
	end)
end

-- Rend un Anima translucide (traversée spectrale, ombre) ou le restaure.
function Arena3D:ghost(s, amount: number, duration: number)
	if not (s and s.Model) then
		return
	end
	for _, d in ipairs(s.Model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local base = d:GetAttribute("BaseT")
			if base == nil then
				base = d.Transparency
				d:SetAttribute("BaseT", base)
			end
			tween(d, duration, { Transparency = base + (1 - base) * amount })
		end
	end
end

-------------------------------------------------------------------------------
-- Capacités uniques : le catalogue
-------------------------------------------------------------------------------
-- Chaque attaque : Kind = "Melee" (charge puis coups), "Ranged" (reste à sa
-- place), "Aerial" (s'élève et frappe d'en haut), "Teleport" (disparaît et
-- frappe derrière la cible). Hit(self, ctx, i) joue l'effet du coup i ; il peut
-- bloquer (projectile qui voyage) avant que les dégâts s'affichent.
-- ctx : { From, To (positions), A, T (côtés), Size (taille cible), Dir (A→T) }
local C = {
	fire = Color3.fromRGB(255, 120, 40), ember = Color3.fromRGB(255, 200, 80), water = Color3.fromRGB(70, 165, 255),
	foam = Color3.fromRGB(200, 240, 255), leaf = Color3.fromRGB(95, 205, 110), spore = Color3.fromRGB(170, 230, 90),
	bolt = Color3.fromRGB(255, 240, 120), shadow = Color3.fromRGB(150, 95, 225), dark = Color3.fromRGB(40, 15, 70),
	light = Color3.fromRGB(255, 245, 200), gold = Color3.fromRGB(255, 205, 90), ice = Color3.fromRGB(170, 225, 255),
	rage = Color3.fromRGB(255, 80, 70), magma = Color3.fromRGB(255, 90, 20),
}

local UNIQUE = {
	-- Pyxel : trois griffures enflammées.
	flamichat = { Kind = "Melee", Hit = function(self, ctx)
		self:fxClaws(ctx.To, C.fire, 3, ctx.Size)
		self:burst(ctx.To, C.ember, TEX.Fire, 30, 10, 1.2, Vector3.new(0, 10, 0))
	end },
	-- Skorri : crache trois braises en cloche.
	braisille = { Kind = "Ranged", Hit = function(self, ctx)
		for k = 1, 3 do
			task.spawn(function()
				self:fxProjectile(ctx.From, ctx.To + Vector3.new((k - 2) * 1.2, 0, 0), C.ember, 0.6, 0.45, 3 + k, TEX.Fire)
			end)
			task.wait(0.1)
		end
		task.wait(0.4)
		self:burst(ctx.To, C.fire, TEX.Fire, 40, 12, 1.5, Vector3.new(0, 12, 0))
	end },
	-- Fungo : nuage de spores qui dérive jusqu'à la cible.
	mousseron = { Kind = "Ranged", Hit = function(self, ctx)
		local cloud = part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(ctx.From), Parent = self.Folder })
		local e = emitter(cloud, "Nature", 60)
		e.Texture = TEX.Smoke
		e.Color = ColorSequence.new(C.spore, Color3.fromRGB(120, 170, 60))
		e.Size = NumberSequence.new(1.5, 3)
		e.LightEmission = 0.3
		tween(cloud, 0.9, { CFrame = CFrame.new(ctx.To) }, Enum.EasingStyle.Sine)
		task.wait(0.9)
		self:burst(ctx.To, C.spore, TEX.Smoke, 40, 4, 2.5, Vector3.new(0, 2, 0))
		e.Enabled = false
		vanish(cloud, 1, 0)
	end },
	-- Zippik : charge électrique, cage d'arcs autour de la cible.
	etincelot = { Kind = "Melee", Hit = function(self, ctx)
		for k = 1, 5 do
			local ang = k * math.pi * 2 / 5
			local o = Vector3.new(math.cos(ang), 0, math.sin(ang)) * ctx.Size
			self:fxBolt(ctx.To + o + Vector3.new(0, ctx.Size, 0), ctx.To - o * 0.3, C.bolt, 0.25)
		end
		self:flashScreen(0.3)
	end },
	-- Grimlet : se fond dans l'ombre et frappe dans le dos.
	ombrelin = { Kind = "Teleport", Hit = function(self, ctx)
		self:burst(ctx.To, C.shadow, TEX.Smoke, 40, 5, 2, Vector3.new(0, 3, 0))
		self:fxClaws(ctx.To, C.shadow, 2, ctx.Size)
	end },
	-- Kharox : longue charge qui embrase le sol.
	cendrebouc = { Kind = "Melee", Charge = function(self, ctx)
		for k = 1, 5 do
			local p = ctx.From:Lerp(ctx.To, k / 6)
			self:burst(Vector3.new(p.X, self.Center.Y + 0.3, p.Z), C.fire, TEX.Fire, 15, 3, 1.3, Vector3.new(0, 8, 0))
		end
	end, Hit = function(self, ctx)
		self:fxOrb(ctx.To, C.fire, Enum.Material.Neon, ctx.Size * 2.6, 0.6)
		self:fxRings(Vector3.new(ctx.To.X, self.Center.Y + 0.2, ctx.To.Z), C.ember, 2, 14)
		self:burst(ctx.To, C.fire, TEX.Fire, 60, 16, 1.6, Vector3.new(0, 12, 0))
	end },
	-- Vashira : lame d'eau en croissant qui traverse la cible.
	marelame = { Kind = "Ranged", Hit = function(self, ctx)
		local dir = ctx.Dir
		local blade = neon({ Size = Vector3.new(0.3, ctx.Size * 1.6, 0.3), Color = C.water, Transparency = 0.1,
			CFrame = CFrame.lookAt(ctx.From, ctx.From + dir) * CFrame.Angles(0, 0, math.rad(20)), Parent = self.Folder })
		tween(blade, 0.35, { CFrame = CFrame.lookAt(ctx.To + dir * 6, ctx.To + dir * 7) * CFrame.Angles(0, 0, math.rad(20)), Size = Vector3.new(0.3, ctx.Size * 2.4, 2.5) },
			Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		vanish(blade, 0.4, 0.2)
		task.wait(0.25)
		self:burst(ctx.To, C.foam, TEX.Spark, 50, 18, 0.8, Vector3.new(0, -25, 0))
	end },
	-- Briarok : mâchoires de ronces qui se referment, deux fois.
	ronceloup = { Kind = "Melee", Hit = function(self, ctx, i)
		local cf = camBasis(ctx.To)
		for _, sy in ipairs({ 1, -1 }) do
			local jaw = part({ ClassName = "WedgePart", Size = Vector3.new(0.6, ctx.Size * 0.7, ctx.Size * 1.4), Color = Color3.fromRGB(70, 130, 55),
				Material = Enum.Material.Grass, CFrame = cf * CFrame.new(0, sy * ctx.Size, 0) * CFrame.Angles(sy > 0 and math.pi or 0, 0, 0), Parent = self.Folder })
			tween(jaw, 0.12, { CFrame = cf * CFrame.new(0, sy * ctx.Size * 0.25, 0) * CFrame.Angles(sy > 0 and math.pi or 0, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			vanish(jaw, 0.3, 0.2)
		end
		self:burst(ctx.To, C.leaf, TEX.Spark, 20 + i * 10, 9, 0.8)
	end },
	-- Volgrum : champ statique qui grossit et file vers la cible.
	orageon = { Kind = "Ranged", Hit = function(self, ctx)
		local orb = self:fxOrb(ctx.From, C.bolt, Enum.Material.ForceField, 4, 1.1)
		tween(orb, 0.6, { CFrame = CFrame.new(ctx.To) }, Enum.EasingStyle.Quad)
		for k = 1, 4 do
			task.delay(k * 0.12, function()
				self:fxBolt(orb.Position + Vector3.new(0, 2, 0), orb.Position + Vector3.new((math.random() - 0.5) * 4, -1, (math.random() - 0.5) * 4), C.bolt, 0.15)
			end)
		end
		task.wait(0.6)
		self:fxRings(ctx.To, C.bolt, 3, 10)
	end },
	-- Solenne : rugissement en ondes, puis aura de rage.
	aurelion = { Kind = "Ranged", Hit = function(self, ctx)
		self:fxRings(ctx.From + ctx.Dir * 2, C.gold, 4, 9, ctx.Dir)
		UIKit.playSound("Charge", 0.6, 0.6)
		self.Shake(0.4, 0.5)
		task.wait(0.35)
		self:fxShockwave(ctx.From, ctx.To, C.gold, 0.35)
		task.wait(0.35)
		self:fxShell(ctx.A.Key, C.rage, Enum.Material.ForceField, nil, 0.8)
	end },
	-- Wispira : traverse la cible comme un spectre et lui vole de l'énergie.
	spectrombre = { Kind = "Teleport", Hit = function(self, ctx)
		self:burst(ctx.To, C.shadow, TEX.Smoke, 30, 4, 2)
		for k = 1, 5 do
			task.delay(k * 0.08, function()
				self:fxProjectile(ctx.To, ctx.From + Vector3.new(0, 1, 0), Color3.fromRGB(160, 255, 200), 0.4, 0.5, 2)
			end)
		end
	end },
	-- Ignarax : s'élève et fait pleuvoir des plumes de feu.
	pyrogriff = { Kind = "Aerial", Hit = function(self, ctx)
		self:fxRain(ctx.To, C.fire, 14, 0.6, 1, 6)
		task.wait(0.65)
		self:fxOrb(ctx.To, C.ember, Enum.Material.Neon, ctx.Size * 2, 0.5)
		self:burst(ctx.To, C.fire, TEX.Fire, 50, 14, 1.5, Vector3.new(0, 10, 0))
	end },
	-- Kestrix : depuis le ciel, un éclair par coup.
	voltigeai = { Kind = "Aerial", Hit = function(self, ctx)
		self:fxBolt(ctx.From + Vector3.new(0, 4, 0), ctx.To, C.bolt, 0.35)
		self:flashScreen(0.35)
	end },
	-- Morwyn : tentacules d'eau qui enserrent, puis l'eau revient à lui.
	abyssalor = { Kind = "Ranged", Hit = function(self, ctx)
		self:fxTentacles(ctx.To, C.water, Enum.Material.Glass, 6, ctx.Size * 1.1, ctx.Size * 2.2)
		task.wait(0.55)
		self:burst(ctx.To, C.foam, TEX.Spark, 40, 10, 0.8, Vector3.new(0, -15, 0))
		for k = 1, 4 do
			task.delay(k * 0.08, function()
				self:fxProjectile(ctx.To, ctx.From, C.water, 0.5, 0.45, 2)
			end)
		end
	end },
	-- Noxtalon : la nuit tombe, il fond en piqué depuis l'obscurité.
	nocturbe = { Kind = "Aerial", Dive = true, Hit = function(self, ctx)
		self:fxDarken(0.35, 0.9)
		self:fxClaws(ctx.To, C.shadow, 4, ctx.Size * 1.2)
		self:burst(ctx.To, C.dark, TEX.Smoke, 40, 8, 2.2)
	end },
	-- Velmora : une lune noire se lève puis s'écrase (éclipse).
	umbrelune = { Kind = "Ranged", Hit = function(self, ctx)
		self:fxDarken(0.3, 1.2)
		local moon = self:fxOrb(ctx.To + Vector3.new(0, 10, 0), C.dark, Enum.Material.Neon, ctx.Size * 2.2, 1.3)
		local halo = self:fxOrb(ctx.To + Vector3.new(0, 10, 0), C.shadow, Enum.Material.ForceField, ctx.Size * 3, 1.3)
		task.wait(0.55)
		tween(moon, 0.25, { CFrame = CFrame.new(ctx.To) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(halo, 0.25, { CFrame = CFrame.new(ctx.To) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.25)
		self:fxRings(Vector3.new(ctx.To.X, self.Center.Y + 0.2, ctx.To.Z), C.shadow, 3, 16)
	end },
	-- Rhazul : piétine le sol, l'onde file et fait jaillir des éclairs.
	tonnerrhin = { Kind = "Ranged", Stomp = true, Hit = function(self, ctx)
		self.Shake(0.7, 0.4)
		self:fxRings(Vector3.new(ctx.From.X, self.Center.Y + 0.2, ctx.From.Z), C.bolt, 2, 10)
		self:fxShockwave(ctx.From, ctx.To, C.bolt, 0.4)
		task.wait(0.4)
		for k = 1, 3 do
			self:fxBolt(ctx.To + Vector3.new((k - 2) * 2, 14, 0), ctx.To + Vector3.new((k - 2) * 0.8, -1, 0), C.bolt, 0.3)
		end
	end },
	-- Vulkhar : le sol se fend, geysers de magma et météores.
	magmorex = { Kind = "Ranged", Hit = function(self, ctx)
		self:fxSpikes(ctx.To, Color3.fromRGB(60, 30, 25), Enum.Material.Basalt, 7, ctx.Size, ctx.Size * 1.2)
		for k = 1, 3 do
			local o = Vector3.new(math.cos(k * 2.1), 0, math.sin(k * 2.1)) * ctx.Size * 0.8
			self:fxBeam(Vector3.new(ctx.To.X, self.Center.Y, ctx.To.Z) + o, ctx.To + o + Vector3.new(0, 9, 0), C.magma, 1.4, 0.8)
		end
		self:fxRain(ctx.To, C.magma, 8, 0.5, 1.4, 5)
		task.wait(0.55)
		self:burst(ctx.To, C.fire, TEX.Fire, 70, 18, 2, Vector3.new(0, 14, 0))
	end },
	-- Thalassor : chant glacial en ondes, la cible est prise dans la glace.
	glacimar = { Kind = "Ranged", Hit = function(self, ctx)
		self:fxRings(ctx.From + ctx.Dir * 2, C.ice, 5, 8, ctx.Dir)
		task.wait(0.4)
		self:fxShockwave(ctx.From, ctx.To, C.ice, 0.3)
		task.wait(0.3)
		self:fxIce(ctx.To, ctx.Size)
	end },
	-- Aurelius : s'élève, devient un soleil et abat un rayon géant.
	solaryx = { Kind = "Aerial", Hit = function(self, ctx)
		self:fxOrb(ctx.From + Vector3.new(0, 2, 0), C.light, Enum.Material.Neon, 6, 1)
		UIKit.playSound("Charge", 0.7, 1.3)
		task.wait(0.5)
		self:fxBeam(ctx.From + Vector3.new(0, 2, 0), ctx.To, C.light, 3.5, 0.8)
		self:flashScreen(0.8)
		self:fxRings(Vector3.new(ctx.To.X, self.Center.Y + 0.2, ctx.To.Z), C.gold, 3, 18)
	end },
	-- Nyxalith : la nuit éternelle tombe, une comète violette s'abat, l'énergie revient.
	nyxaria = { Kind = "Ranged", Hit = function(self, ctx)
		self:fxDarken(0.45, 1.4)
		self:burst(ctx.To + Vector3.new(0, 8, 0), Color3.fromRGB(230, 220, 255), TEX.Spark, 60, 2, 0.4)
		task.wait(0.4)
		self:fxProjectile(ctx.To + Vector3.new(-6, 18, 0), ctx.To, C.shadow, 1.6, 0.4, 0, TEX.Smoke)
		self:fxOrb(ctx.To, C.shadow, Enum.Material.Neon, ctx.Size * 2.6, 0.5)
		for k = 1, 4 do
			task.delay(0.2 + k * 0.07, function()
				self:fxProjectile(ctx.To, ctx.From, C.shadow, 0.5, 0.45, 2)
			end)
		end
	end },
	-- Zhaltor : nuée d'orage et trois foudres colossales.
	fulguron = { Kind = "Aerial", Hit = function(self, ctx, i)
		if i == 1 then
			self:fxDarken(0.25, 1.6)
		end
		self:fxBolt(ctx.To + Vector3.new(0, 26, 0), ctx.To, C.bolt, 0.7)
		self:fxBeam(ctx.To + Vector3.new(0, 26, 0), ctx.To, Color3.new(1, 1, 1), 0.6, 0.25)
		self:flashScreen(0.5)
		self.Shake(0.6, 0.2)
	end },
}

-- Capacités sans attaque (bouclier, soin, miroir...) : effet propre à chaque créature.
local SUPPORT = {
	-- Nimbu : grosse bulle d'eau qui ondule.
	gouttelin = function(self, s)
		local b = self:fxShell(s.Key, C.water, Enum.Material.Glass, nil, 1.3)
		self:burst(s.Model:GetPivot().Position, C.foam, TEX.Spark, 30, 6, 0.6)
		if b then
			task.spawn(function()
				for k = 1, 6 do
					if not b.Parent then
						break
					end
					tween(b, 0.1, { Size = b.Size * (k % 2 == 0 and 1.06 or 0.95) })
					task.wait(0.1)
				end
			end)
		end
	end,
	-- Brumbel : s'enroule en boule et tourne, carapace de pierre.
	galetor = function(self, s)
		local home = s.Home
		task.spawn(function()
			for k = 1, 8 do
				if self.Dead or not s.Model then
					break
				end
				s.Model:PivotTo(home * CFrame.Angles(0, 0, -k * math.pi / 4))
				task.wait(0.05)
			end
			if s.Model then
				s.Model:PivotTo(home)
			end
		end)
		self:fxShell(s.Key, Color3.fromRGB(140, 125, 95), Enum.Material.Slate, Enum.PartType.Ball, 1)
	end,
	-- Liora : lucioles qui montent en spirale, colonne dorée apaisante.
	lucioline = function(self, s)
		local pos = s.Model:GetPivot().Position
		self:pillar(Vector3.new(pos.X, self.Center.Y, pos.Z), C.gold, 12)
		for k = 1, 10 do
			task.delay(k * 0.06, function()
				local ang = k * 0.9
				self:fxProjectile(pos + Vector3.new(math.cos(ang) * 2.5, -1, math.sin(ang) * 2.5), pos + Vector3.new(math.cos(ang + 2) * 1.5, 5, math.sin(ang + 2) * 1.5),
					C.gold, 0.3, 0.7, 0)
			end)
		end
	end,
	-- Tessaro : panneaux de miroir hexagonaux qui tournent autour de lui.
	aquatortue = function(self, s)
		local pos = s.Model:GetPivot().Position
		for k = 1, 6 do
			local ang = k * math.pi / 3
			local panel = part({ Size = Vector3.new(s.Size * 0.9, s.Size * 1.1, 0.15), Color = C.foam, Material = Enum.Material.Glass, Transparency = 0.2,
				Reflectance = 0.5, CFrame = CFrame.lookAt(pos + Vector3.new(math.cos(ang), 0, math.sin(ang)) * s.Size * 1.1, pos), Parent = self.Folder })
			tween(panel, 1, { CFrame = CFrame.lookAt(pos + Vector3.new(math.cos(ang + 1.5), 0, math.sin(ang + 1.5)) * s.Size * 1.1, pos) })
			vanish(panel, 1, 0.3)
		end
	end,
	-- Sylphira : couronne de fleurs qui éclosent, lianes, soin.
	florhydre = function(self, s)
		local pos = s.Model:GetPivot().Position
		self:fxTentacles(pos, C.leaf, Enum.Material.Grass, 5, s.Size * 1.2, s.Size * 1.5)
		for k = 1, 8 do
			local ang = k * math.pi / 4
			local flower = neon({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.2, Color = Color3.fromRGB(255, 140, 200),
				CFrame = CFrame.new(pos + Vector3.new(math.cos(ang) * s.Size * 1.3, 0.5, math.sin(ang) * s.Size * 1.3)), Parent = self.Folder })
			tween(flower, 0.4, { Size = Vector3.one * 0.9 }, Enum.EasingStyle.Back)
			vanish(flower, 1.1, 0.3)
		end
		self:burst(pos, Color3.fromRGB(255, 170, 210), TEX.Spark, 30, 5, 0.6, Vector3.new(0, -2, 0))
	end,
	-- Elarion : lumière sacrée qui descend, plumes, bouclier.
	seraphel = function(self, s)
		local pos = s.Model:GetPivot().Position
		self:fxBeam(pos + Vector3.new(0, 25, 0), pos, C.light, 3, 1)
		self:fxShell(s.Key, C.gold, Enum.Material.ForceField, nil, 1.1)
		self:burst(pos + Vector3.new(0, 4, 0), Color3.new(1, 1, 1), TEX.Spark, 35, 3, 0.7, Vector3.new(0, -3, 0))
	end,
	-- Grondahl : racines millénaires qui forment une cage protectrice.
	sylvaroc = function(self, s)
		local pos = s.Model:GetPivot().Position
		self:fxTentacles(pos, Color3.fromRGB(110, 80, 50), Enum.Material.Wood, 8, s.Size * 1.1, s.Size * 2)
		self:fxSpikes(pos, Color3.fromRGB(90, 85, 80), Enum.Material.Slate, 6, s.Size * 1.5, s.Size * 0.8)
		self:burst(pos, C.leaf, TEX.Spark, 25, 5, 0.6, Vector3.new(0, -3, 0))
	end,
	-- Yggrana : floraison sacrée, tempête de pétales et arbre de lumière.
	gaiandre = function(self, s)
		local pos = s.Model:GetPivot().Position
		self:fxTentacles(pos, Color3.fromRGB(120, 85, 50), Enum.Material.Wood, 10, s.Size * 1.3, s.Size * 2.6)
		self:fxOrb(pos + Vector3.new(0, s.Size * 2.2, 0), C.leaf, Enum.Material.Neon, s.Size * 2.4, 1.3)
		self:fxShell(s.Key, C.gold, Enum.Material.ForceField, nil, 1.2)
		self:burst(pos + Vector3.new(0, 4, 0), Color3.fromRGB(255, 180, 220), TEX.Spark, 70, 7, 0.7, Vector3.new(0, -4, 0))
	end,
}

function Arena3D:Buff(key: string, value: string?, color: Color3?)
	local s = self.Sides[key]
	local unique = s and s.Model and s.CardId and SUPPORT[s.CardId]
	if unique then
		local ok, err = pcall(unique, self, s)
		if not ok then
			warn("[Arena3D] soutien", s.CardId, err)
		end
	else
		self:bubble(key, Color3.fromRGB(255, 215, 120))
		if s and s.Model then
			self:pillar(s.Spot, Color3.fromRGB(255, 225, 150), 10)
		end
	end
	if value then
		self:Number(key, value, color or Color3.fromRGB(95, 225, 130))
	end
end

-- Attaque mise en scène (bloquante). e : événement du serveur.
-- Les capacités ont chacune leur chorégraphie (catalogue UNIQUE ci-dessus) ;
-- l'attaque simple garde la charge classique avec l'effet de l'élément.
function Arena3D:Attack(attackerKey: string, e)
	local a, t = self.Sides[attackerKey], self.Sides[attackerKey == "Me" and "Opp" or "Me"]
	if not (a.Model and t.Model) then
		return
	end
	local targetKey = attackerKey == "Me" and "Opp" or "Me"
	local ability = e.Action == "Ability"
	local hits = e.Hits or { e.Damage }
	local dirAT = (t.Spot - a.Spot).Unit
	local right = dirAT:Cross(Vector3.yAxis)
	a.Busy = true

	local atkCard = CardsData.CardById[a.CardId or ""] or CardsData.CardById[a.Model.Name:sub(7)]
	local element = atkCard and atkCard.Element or "Feu"
	local style = if ability and atkCard then UNIQUE[atkCard.Id] else nil

	-- 1. Par-dessus l'épaule de l'attaquant ; il se charge d'énergie.
	local over = CFrame.lookAt(a.Spot - dirAT * 8 + right * 3.5 + Vector3.new(0, 3.5 + a.Size * 0.3, 0), t.Spot + Vector3.new(0, t.Size * 0.5, 0))
	self:Cam(over, 9, true)
	local root = a.Model.PrimaryPart
	local light = root and root:FindFirstChildOfClass("PointLight")
	local burstA = root and root:FindFirstChild("Burst") :: ParticleEmitter?
	if light then
		tween(light, 0.4, { Brightness = ability and 8 or 4, Range = a.Size * 7 })
	end
	-- Animation propre à la créature : sa capacité ou son attaque simple.
	if ability then
		playAbilityClip(a.Model, atkCard)
	else
		playClip(a.Model, "Attaque")
	end
	if ability then
		self:pillar(a.Spot, CardsData.Elements[element].Color, 12)
		self:chargeFX(element, a.Model:GetPivot().Position, a.Size)
		UIKit.playSound("Charge", 0.7, 1)
		self.Shake(0.15, 0.6)
	end
	-- Élan vers l'arrière.
	-- Anima en cubes : il recule en se ramassant, tête relevée (axe X local = vers la tête).
	local back = if a.Voxel then a.Home * CFrame.new(-a.Size * 0.35, 0.8, 0) * CFrame.Angles(0, 0, 0.4) else a.Home * CFrame.new(0, 0.6, 1.5)
	local function moveTo(cf: CFrame, time: number, easing: Enum.EasingStyle?, dir: Enum.EasingDirection?)
		self:glide(a, cf, time, easing, dir)
	end
	moveTo(back, ability and 0.6 or 0.35, Enum.EasingStyle.Quad)
	if not self:wait(ability and 0.75 or 0.4) then
		return
	end

	local trail = root and root:FindFirstChildOfClass("Trail")
	local strikePos = t.Home.Position - dirAT * (t.Size * 0.5 + a.Size * 0.5 + 0.3)
	-- Caméra latérale, toujours du même côté que le plan de combat.
	local side = CFrame.lookAt(self.Center + (self.SideVec or right) * 15 + Vector3.new(0, 4, 0), t.Spot + Vector3.new(0, 2, 0))
	local function face(pos: Vector3, toward: Vector3): CFrame
		if a.Voxel then
			-- Bond tête la première vers la cible.
			return CFrame.new(pos + Vector3.new(0, a.Size * 0.25, 0)) * a.Home.Rotation * CFrame.Angles(0, 0, -0.45)
		end
		return CFrame.lookAt(pos, toward)
	end
	local function targetPos(): Vector3
		return t.Model and t.Model.Parent and t.Model:GetPivot().Position or t.Spot
	end
	local ctx = { A = a, T = t, Dir = dirAT, Size = t.Size, From = a.Model:GetPivot().Position, To = targetPos() }

	-- Un coup porté : effet, chiffres, secousse, recul de la cible.
	local function impact(i: number, dmg: number)
		local tr = t.Model and t.Model.PrimaryPart
		local burstT = tr and tr:FindFirstChild("Burst") :: ParticleEmitter?
		if burstA then
			burstA:Emit(ability and 60 or 35)
		end
		if burstT then
			burstT:Emit(20)
		end
		if not style and (i == 1 or ability) then
			self:elementFX(element, a.Spot, targetPos(), t.Size, ability and i == 1)
		end
		self:flashModel(targetKey, Color3.fromRGB(255, 60, 60))
		self:flashScreen(ability and 0.3 or 0.2)
		self.Shake(ability and 0.7 or (e.Mult > 1 and 0.55 or 0.35), 0.25)
		UIKit.playSound("Hit", 0.9, ability and 0.85 or 1)
		UIKit.playSound("Burst", 0.5, 1.1)
		self:Number(targetKey, "-" .. tostring(dmg), ability and Color3.fromRGB(255, 215, 120) or Color3.fromRGB(255, 95, 95), ability or e.Mult > 1)
		if t.Model then
			playClip(t.Model, "Degats", 0.05)
			t.Busy = true
			local tv = Instance.new("CFrameValue")
			tv.Value = if t.Voxel then t.Home * CFrame.new(-t.Size * 0.4, 0.4, 0) * CFrame.Angles(0, 0, 0.5)
				else t.Home * CFrame.new(0, 0.3, 1.6) * CFrame.Angles(math.rad(-15), 0, 0)
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
	end

	if style and style.Kind ~= "Melee" then
		-- 2bis. Capacité à distance, aérienne ou par téléportation.
		if style.Kind == "Aerial" then
			UIKit.playSound("Swoosh", 0.6, 0.8)
			moveTo(a.Home * CFrame.new(0, a.Size * 1.2 + 3, 0), 0.4, Enum.EasingStyle.Quad)
			if not self:wait(0.4) then
				return
			end
			if style.Dive then
				-- Piqué sur la cible.
				if trail then
					trail.Enabled = true
				end
				moveTo(face(strikePos, strikePos + dirAT), 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				if not self:wait(0.18) then
					return
				end
			end
		elseif style.Kind == "Teleport" then
			-- Se dissout, réapparaît derrière la cible.
			self:ghost(a, 1, 0.2)
			self:burst(a.Model:GetPivot().Position, CardsData.Elements[element].Color, TEX.Smoke, 30, 4, 2)
			if not self:wait(0.25) then
				return
			end
			local behind = t.Home.Position + dirAT * (t.Size * 0.5 + a.Size * 0.5 + 0.6)
			a.Model:PivotTo(if a.Voxel then CFrame.new(behind) * a.Home.Rotation * CFrame.Angles(0, math.pi, 0) else CFrame.lookAt(behind, t.Home.Position))
			self:ghost(a, 0, 0.15)
			if not self:wait(0.15) then
				return
			end
		elseif style.Stomp then
			-- Se dresse puis retombe lourdement.
			moveTo(a.Home * CFrame.new(0, a.Size * 0.8, 0), 0.2, Enum.EasingStyle.Quad)
			if not self:wait(0.2) then
				return
			end
			moveTo(a.Home, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			if not self:wait(0.12) then
				return
			end
		else
			-- À distance : retour à sa place, il lance son attaque.
			moveTo(a.Home, 0.2, Enum.EasingStyle.Quad)
		end
		self:Cam(side, 10, true)
		ctx.From = a.Model:GetPivot().Position
		for i, dmg in ipairs(hits) do
			ctx.To = targetPos()
			local ok, err = pcall(style.Hit, self, ctx, i)
			if not ok then
				warn("[Arena3D] capacité", atkCard and atkCard.Id, err)
			end
			if self.Dead then
				return
			end
			impact(i, dmg)
			if i < #hits and not self:wait(0.25) then
				return
			end
		end
		if trail then
			trail.Enabled = false
		end
		if not self:wait(0.4) then
			return
		end
		if style.Kind == "Teleport" then
			self:ghost(a, 1, 0.15)
			if not self:wait(0.15) then
				return
			end
			a.Model:PivotTo(a.Home)
			self:ghost(a, 0, 0.2)
		end
	else
		-- 2. Charge : traînée, caméra latérale qui suit.
		if trail then
			trail.Enabled = true
		end
		UIKit.playSound("Swoosh", 0.7, 0.9)
		self:Cam(side, 12, true)
		if a.Rig and not ability then
			playClip(a.Model, "Course", 0.05, 1.6)
		end
		if style and style.Charge then
			pcall(style.Charge, self, { A = a, T = t, Dir = dirAT, Size = t.Size, From = a.Spot, To = strikePos })
		end
		moveTo(face(strikePos, strikePos + dirAT), 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if not self:wait(0.2) then
			return
		end

		-- 3. Impact(s).
		for i, dmg in ipairs(hits) do
			if style then
				ctx.To = targetPos()
				local ok, err = pcall(style.Hit, self, ctx, i)
				if not ok then
					warn("[Arena3D] capacité", atkCard and atkCard.Id, err)
				end
			end
			impact(i, dmg)
			if i < #hits then
				-- Petit rebond avant le coup suivant.
				moveTo(face(strikePos - dirAT * 1.5, strikePos), 0.12)
				if not self:wait(0.15) then
					return
				end
				moveTo(face(strikePos, strikePos + dirAT), 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				if not self:wait(0.15) then
					return
				end
			end
		end
		if not self:wait(0.45) then
			return
		end
		if trail then
			trail.Enabled = false
		end
	end
	if (e.Absorbed or 0) > 0 then
		self:bubble(targetKey, Color3.fromRGB(120, 200, 255))
	end

	-- 4. Retour à sa place, plan large.
	if light then
		tween(light, 0.5, { Brightness = 1.5, Range = a.Size * 4 })
	end
	playClip(a.Model, "Course", 0.1, 1.4)
	moveTo(a.Home, 0.4, Enum.EasingStyle.Quint)
	self:Cam(self.Wide, 4)
	if (e.Reflected or 0) > 0 then
		self:Number(attackerKey, "◇ -" .. e.Reflected, Color3.fromRGB(200, 240, 255))
	end
	task.delay(0.4, stopClip, a.Model, "Course", 0.25)
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
	if self.Frozen then
		Freeze.release("Combat")
	end
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
