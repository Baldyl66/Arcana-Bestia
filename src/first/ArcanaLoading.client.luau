--[[
	ARCANA BESTIA : écran de chargement + apparition
	LocalScript placé dans ReplicatedFirst.

	Fin du chargement détectable depuis n'importe quel script client :
		player:GetAttributeChangedSignal("ArcanaLoaded")  /  player:GetAttribute("ArcanaLoaded") == true
]]

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
	Title = "ARCANA BESTIA",
	Subtitle = "LE SANCTUAIRE DES BÊTES",
	Status = "Invocation du monde",
	DoneStatus = "Le sanctuaire s'éveille",
	MinDuration = 1, -- durée minimale du chargement (secondes)
	MapTimeout = 60, -- au-delà, on entre même si la carte n'est pas complète
	TipInterval = 4.5,
	Tips = {
		"Les doublons te remboursent des gemmes selon leur rareté.",
		"Chaque booster contient 3 créatures : retourne les cartes une à une !",
		"Une carte Légendaire n'apparaît que dans 1,5 % des tirages.",
		"Reviens chaque jour pour récupérer ta récompense quotidienne.",
		"La Grand-Place de Brumeval est au sud de l'arène, au bout de l'avenue.",
		"Parle aux habitants de Brumeval : ils ont tous quelque chose à t'offrir.",
		"Entraîne-toi contre le mannequin de Varek avant de défier un joueur.",
		"Monte sur les remparts : la vue sur la cité est imprenable...",
	},
}

local FONT_TITLE = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
local FONT_UI = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
local FONT_TIP = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium)

local C = {
	bgTop = Color3.fromRGB(34, 16, 66),
	bgBottom = Color3.fromRGB(9, 5, 22),
	halo = Color3.fromRGB(92, 58, 160),
	ray = Color3.fromRGB(190, 150, 255),
	violet = Color3.fromRGB(165, 110, 255),
	lilac = Color3.fromRGB(200, 175, 255),
	tip = Color3.fromRGB(205, 190, 240),
	gold = Color3.fromRGB(246, 196, 110),
	goldLight = Color3.fromRGB(255, 246, 220),
	outline = Color3.fromRGB(64, 28, 30),
	cyan = Color3.fromRGB(125, 232, 255),
	white = Color3.new(1, 1, 1),
}

-- Repère de conception 1920x1080, mis à l'échelle automatiquement
local CENTER_X = 960
local GEM_Y = 372
local TITLE_Y = 600
local SUB_Y = 705
local BAR_Y = 795
local STATUS_Y = 842
local TIP_Y = 1005

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function make(className, props, children)
	local inst = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function tween(inst, duration, goal, style, direction, delayTime)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out, 0, false, delayTime or 0),
		goal
	)
	t:Play()
	return t
end

local function round(radius)
	return make("UICorner", { CornerRadius = radius or UDim.new(0.5, 0) })
end

local function seq(points)
	local kps = {}
	for _, p in points do
		table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(kps)
end

local function measure(text, font, size)
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = font
	params.Size = size
	params.Width = 4000
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
	if ok then
		return bounds
	end
	return Vector2.new(size * 0.62 * #text, size)
end

local CENTER = Vector2.new(0.5, 0.5)

------------------------------------------------------------------------
-- ÉTAT
------------------------------------------------------------------------
local introDone, exiting, sparksOn = false, false, false
local realProgress, displayed = 0, 0
local startTime = os.clock()
local conn

------------------------------------------------------------------------
-- STRUCTURE
------------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "ArcanaLoading",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 1000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

local root = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })

make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.white,
	BorderSizePixel = 0,
	ZIndex = 1,
	Parent = root,
}, {
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.bgTop, C.bgBottom) }),
})

local starLayer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = root })

local stage = make("Frame", {
	AnchorPoint = CENTER,
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(1920, 1080),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = root,
})
local stageScale = make("UIScale", { Parent = stage })

local cover = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	ZIndex = 10,
	Parent = root,
})

local flash = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(242, 234, 255),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 20,
	Parent = gui,
})

local function rescale()
	local size = root.AbsoluteSize
	if size.X > 0 and size.Y > 0 then
		stageScale.Scale = math.min(size.X / 1920, size.Y / 1080)
	end
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
rescale()

------------------------------------------------------------------------
-- ÉTOILES
------------------------------------------------------------------------
local starAlpha = make("NumberValue", { Value = 0 })
local stars = {}
for i = 1, 90 do
	local size = math.random(2, 4)
	local x, y = math.random(), math.random()
	local frame = make("Frame", {
		AnchorPoint = CENTER,
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = (math.random() < 0.22) and C.gold or C.white,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = starLayer,
	}, { round() })
	stars[i] = {
		frame = frame,
		x = x,
		y = y,
		speed = 0.6 + math.random() * 1.8,
		phase = math.random() * math.pi * 2,
		drift = 0.002 + math.random() * 0.006,
	}
end

------------------------------------------------------------------------
-- HALOS
------------------------------------------------------------------------
local haloHolder = make("Frame", {
	AnchorPoint = CENTER,
	Position = UDim2.fromOffset(CENTER_X, 540),
	Size = UDim2.fromOffset(1700, 1700),
	BackgroundTransparency = 1,
	ZIndex = 1,
	Parent = stage,
})
local haloScale = make("UIScale", { Scale = 0.7, Parent = haloHolder })

local halos = {}
for i, def in { { 1620, 0.9 }, { 1130, 0.88 }, { 760, 0.84 } } do
	local frame = make("Frame", {
		AnchorPoint = CENTER,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(def[1], def[1]),
		BackgroundColor3 = C.halo,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = haloHolder,
	}, { round() })
	halos[i] = { frame = frame, target = def[2], scale = make("UIScale", { Parent = frame }) }
end

------------------------------------------------------------------------
-- RAYONS
------------------------------------------------------------------------
local rays = {}
local RAY_COUNT = 9
for i = 1, RAY_COUNT do
	local width = (i % 2 == 0) and 12 or 6
	local frame = make("Frame", {
		AnchorPoint = CENTER,
		Position = UDim2.fromOffset(CENTER_X, GEM_Y),
		Size = UDim2.fromOffset(width, 640),
		BackgroundColor3 = C.ray,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = stage,
	}, {
		round(),
		make("UIGradient", {
			Rotation = 90,
			Transparency = seq({
				{ 0, 1 }, { 0.18, 0.6 }, { 0.36, 0.82 }, { 0.5, 1 }, { 0.64, 0.82 }, { 0.82, 0.6 }, { 1, 1 },
			}),
		}),
	})
	rays[i] = { frame = frame, width = width, base = (i - 1) * (180 / RAY_COUNT) }
end

------------------------------------------------------------------------
-- GEMME + ANNEAUX
------------------------------------------------------------------------
local gemHolder = make("Frame", {
	AnchorPoint = CENTER,
	Position = UDim2.fromOffset(CENTER_X, GEM_Y),
	Size = UDim2.fromOffset(420, 420),
	BackgroundTransparency = 1,
	ZIndex = 4,
	Parent = stage,
})
local gemScale = make("UIScale", { Scale = 0, Parent = gemHolder })

local outerGlow = make("Frame", {
	AnchorPoint = CENTER,
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(340, 340),
	BackgroundColor3 = C.violet,
	BackgroundTransparency = 0.88,
	BorderSizePixel = 0,
	ZIndex = 1,
	Parent = gemHolder,
}, { round() })

make("Frame", {
	AnchorPoint = CENTER,
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(196, 196),
	BackgroundColor3 = C.white,
	BorderSizePixel = 0,
	ZIndex = 2,
	Parent = gemHolder,
}, {
	round(),
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(152, 120, 242), Color3.fromRGB(102, 68, 198)),
	}),
})

local ringHolder = make("Frame", {
	AnchorPoint = CENTER,
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(420, 420),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = gemHolder,
})
local ringScale = make("UIScale", { Scale = 1.5, Parent = ringHolder })

local rings = {}
local function makeRing(size, color, thickness, arc, speed)
	local stroke = make("UIStroke", { Color = color, Thickness = thickness, Transparency = 1 })
	local grad = make("UIGradient", { Transparency = seq(arc), Rotation = math.random(0, 359), Parent = stroke })
	make("Frame", {
		AnchorPoint = CENTER,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = ringHolder,
	}, { round(), stroke })
	table.insert(rings, { stroke = stroke, grad = grad, speed = speed })
end

makeRing(204, C.cyan, 3, { { 0, 0.8 }, { 0.5, 0.15 }, { 1, 0 } }, 140)
makeRing(258, C.violet, 6, { { 0, 1 }, { 0.35, 1 }, { 0.62, 0 }, { 1, 0 } }, -80)
makeRing(318, C.gold, 4, { { 0, 1 }, { 0.5, 1 }, { 0.76, 0 }, { 1, 0 } }, 45)

local gem = make("Frame", {
	AnchorPoint = CENTER,
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(98, 98),
	Rotation = 45,
	BackgroundColor3 = C.white,
	BorderSizePixel = 0,
	ZIndex = 4,
	Parent = gemHolder,
}, {
	make("UICorner", { CornerRadius = UDim.new(0, 16) }),
	make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(232, 252, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(130, 215, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(86, 140, 245)),
		}),
	}),
	make("UIStroke", { Color = C.white, Thickness = 3, Transparency = 0.1 }),
	make("Frame", {
		Position = UDim2.fromScale(0.14, 0.14),
		Size = UDim2.fromScale(0.34, 0.34),
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, { make("UICorner", { CornerRadius = UDim.new(0, 8) }) }),
})

------------------------------------------------------------------------
-- TITRE (lettre par lettre)
------------------------------------------------------------------------
local TITLE_SIZE = 104
local SPACING = 4
local chars, widths, total = {}, {}, 0
for _, code in utf8.codes(CONFIG.Title) do
	table.insert(chars, utf8.char(code))
end
for i, ch in chars do
	widths[i] = (ch == " ") and TITLE_SIZE * 0.32 or measure(ch, FONT_TITLE, TITLE_SIZE).X
	total += widths[i] + ((i < #chars) and SPACING or 0)
end

local titleGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C.gold),
	ColorSequenceKeypoint.new(0.42, C.gold),
	ColorSequenceKeypoint.new(0.5, C.goldLight),
	ColorSequenceKeypoint.new(0.58, C.gold),
	ColorSequenceKeypoint.new(1, C.gold),
})

local letters = {}
local cursor = CENTER_X - total / 2
for i, ch in chars do
	local w = widths[i]
	if ch ~= " " then
		local cx = cursor + w / 2
		local tilt = (i % 2 == 0) and 10 or -10

		local shadow = make("TextLabel", {
			AnchorPoint = CENTER,
			Position = UDim2.fromOffset(cx, TITLE_Y + 66),
			Size = UDim2.fromOffset(w + 24, 140),
			Rotation = tilt,
			BackgroundTransparency = 1,
			FontFace = FONT_TITLE,
			TextSize = TITLE_SIZE,
			Text = ch,
			TextColor3 = Color3.fromRGB(18, 6, 30),
			TextTransparency = 1,
			ZIndex = 5,
			Parent = stage,
		})

		local stroke = make("UIStroke", { Color = C.outline, Thickness = 2.5, Transparency = 1 })
		local grad = make("UIGradient", { Rotation = 20, Offset = Vector2.new(-1, 0), Color = titleGradient })
		local label = make("TextLabel", {
			AnchorPoint = CENTER,
			Position = UDim2.fromOffset(cx, TITLE_Y + 60),
			Size = UDim2.fromOffset(w + 24, 140),
			Rotation = tilt,
			BackgroundTransparency = 1,
			FontFace = FONT_TITLE,
			TextSize = TITLE_SIZE,
			Text = ch,
			TextColor3 = C.white,
			TextTransparency = 1,
			ZIndex = 6,
			Parent = stage,
		}, { stroke, grad })

		table.insert(letters, {
			label = label,
			shadow = shadow,
			stroke = stroke,
			grad = grad,
			final = UDim2.fromOffset(cx, TITLE_Y),
			shadowFinal = UDim2.fromOffset(cx, TITLE_Y + 6),
		})
	end
	cursor += w + SPACING
end

local function shimmer()
	for i, l in letters do
		l.grad.Offset = Vector2.new(-1, 0)
		tween(l.grad, 0.9, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, (i - 1) * 0.045)
	end
end

------------------------------------------------------------------------
-- SOUS-TITRE + FILETS DORÉS
------------------------------------------------------------------------
local subW = measure(CONFIG.Subtitle, FONT_UI, 32).X

local subtitle = make("TextLabel", {
	AnchorPoint = CENTER,
	Position = UDim2.fromOffset(CENTER_X, SUB_Y + 20),
	Size = UDim2.fromOffset(subW + 20, 40),
	BackgroundTransparency = 1,
	FontFace = FONT_UI,
	TextSize = 32,
	Text = CONFIG.Subtitle,
	TextColor3 = C.lilac,
	TextTransparency = 1,
	ZIndex = 6,
	Parent = stage,
})

local lineL = make("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromOffset(CENTER_X - subW / 2 - 26, SUB_Y),
	Size = UDim2.fromOffset(0, 2),
	BackgroundColor3 = C.gold,
	BorderSizePixel = 0,
	ZIndex = 6,
	Parent = stage,
}, { make("UIGradient", { Transparency = seq({ { 0, 1 }, { 1, 0.1 } }) }) })

local lineR = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromOffset(CENTER_X + subW / 2 + 26, SUB_Y),
	Size = UDim2.fromOffset(0, 2),
	BackgroundColor3 = C.gold,
	BorderSizePixel = 0,
	ZIndex = 6,
	Parent = stage,
}, { make("UIGradient", { Transparency = seq({ { 0, 0.1 }, { 1, 1 } }) }) })

------------------------------------------------------------------------
-- BARRE DE PROGRESSION
------------------------------------------------------------------------
local track = make("Frame", {
	AnchorPoint = CENTER,
	Position = UDim2.fromOffset(CENTER_X, BAR_Y),
	Size = UDim2.fromOffset(0, 8),
	BackgroundColor3 = Color3.fromRGB(70, 50, 120),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 6,
	Parent = stage,
}, { round() })

local fill = make("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = C.white,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 7,
	Parent = track,
}, {
	round(),
	make("UIGradient", { Color = ColorSequence.new(C.violet, C.gold) }),
})

local sheen = make("Frame", {
	Size = UDim2.fromScale(0.25, 1),
	BackgroundColor3 = C.white,
	BorderSizePixel = 0,
	ZIndex = 8,
	Parent = fill,
}, { make("UIGradient", { Transparency = seq({ { 0, 1 }, { 0.5, 0.35 }, { 1, 1 } }) }) })

local headGlow = make("Frame", {
	AnchorPoint = CENTER,
	Position = UDim2.fromScale(0, 0.5),
	Size = UDim2.fromOffset(38, 38),
	BackgroundColor3 = C.gold,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 8,
	Parent = track,
}, { round() })

local head = make("Frame", {
	AnchorPoint = CENTER,
	Position = UDim2.fromScale(0, 0.5),
	Size = UDim2.fromOffset(14, 14),
	BackgroundColor3 = C.white,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 9,
	Parent = track,
}, { round() })

local status = make("TextLabel", {
	AnchorPoint = CENTER,
	Position = UDim2.fromOffset(CENTER_X, STATUS_Y),
	Size = UDim2.fromOffset(800, 40),
	BackgroundTransparency = 1,
	FontFace = FONT_UI,
	TextSize = 30,
	RichText = true,
	Text = "",
	TextColor3 = C.white,
	TextTransparency = 1,
	ZIndex = 6,
	Parent = stage,
})

local tip = make("TextLabel", {
	AnchorPoint = CENTER,
	Position = UDim2.fromOffset(CENTER_X, TIP_Y),
	Size = UDim2.fromOffset(1400, 36),
	BackgroundTransparency = 1,
	FontFace = FONT_TIP,
	TextSize = 26,
	Text = CONFIG.Tips[1] or "",
	TextColor3 = C.tip,
	TextTransparency = 1,
	ZIndex = 6,
	Parent = stage,
})

------------------------------------------------------------------------
-- EFFETS
------------------------------------------------------------------------
local function shockwave(size, duration, color, thickness)
	local stroke = make("UIStroke", { Color = color, Thickness = thickness, Transparency = 0 })
	local ring = make("Frame", {
		AnchorPoint = CENTER,
		Position = UDim2.fromOffset(CENTER_X, GEM_Y),
		Size = UDim2.fromOffset(80, 80),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = stage,
	}, { round(), stroke })
	tween(ring, duration, { Size = UDim2.fromOffset(size, size) }, Enum.EasingStyle.Quart)
	tween(stroke, duration, { Transparency = 1, Thickness = 1 }, Enum.EasingStyle.Quart)
	task.delay(duration, function()
		ring:Destroy()
	end)
end

local function spark(mult)
	mult = mult or 1
	local angle = math.random() * math.pi * 2
	local dx, dy = math.cos(angle), math.sin(angle)
	local dist = (120 + math.random() * 150) * mult
	local size = math.random(3, 6)
	local p = make("Frame", {
		AnchorPoint = CENTER,
		Position = UDim2.fromOffset(CENTER_X + dx * 60, GEM_Y + dy * 60),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = (math.random() < 0.5) and C.gold or C.cyan,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = stage,
	}, { round() })
	local life = 1 + math.random() * 0.9
	tween(p, life, {
		Position = UDim2.fromOffset(CENTER_X + dx * dist, GEM_Y + dy * dist - 40),
		Size = UDim2.fromOffset(1, 1),
		BackgroundTransparency = 1,
	}, Enum.EasingStyle.Quad)
	task.delay(life, function()
		p:Destroy()
	end)
end

------------------------------------------------------------------------
-- CHARGEMENT RÉEL : ASSETS + GÉNÉRATION DE LA CARTE
------------------------------------------------------------------------
-- La carte est construite par le serveur au lancement : on attend qu'elle
-- soit générée puis entièrement reçue avant d'entrer dans le jeu.
local assetProgress = 0

local function mapProgress(): number
	if os.clock() - startTime > CONFIG.MapTimeout then
		return 1
	end
	if not workspace:GetAttribute("WorldReady") then
		return 0.8 * (workspace:GetAttribute("WorldProgress") or 0)
	end
	if not workspace:GetAttribute("VillageReady") then
		return 0.85
	end
	local expected = workspace:GetAttribute("WorldPartCount") or 0
	local folder = workspace:FindFirstChild("World")
	local received = folder and #folder:GetDescendants() or 0
	local ratio = expected > 0 and math.clamp(received / expected, 0, 1) or 1
	if ratio >= 0.99 then
		return 1
	end
	return 0.85 + 0.15 * ratio
end

task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	local list = {}
	for _, container in { workspace, ReplicatedStorage, Lighting, StarterGui, SoundService } do
		for _, d in container:GetDescendants() do
			if d:IsA("Decal") or d:IsA("Texture") or d:IsA("MeshPart") or d:IsA("SpecialMesh")
				or d:IsA("Sound") or d:IsA("ImageLabel") or d:IsA("ImageButton")
				or d:IsA("Animation") or d:IsA("SurfaceAppearance") then
				table.insert(list, d)
			end
		end
	end

	if #list > 0 then
		local BATCH = 25
		for i = 1, #list, BATCH do
			local last = math.min(i + BATCH - 1, #list)
			local batch = table.move(list, i, last, 1, {})
			pcall(ContentProvider.PreloadAsync, ContentProvider, batch)
			assetProgress = last / #list
		end
	end
	assetProgress = 1
end)

-- Progression réelle = la plus lente des deux (compter les objets reçus
-- coûte cher : on ne le fait que deux fois par seconde).
task.spawn(function()
	while realProgress < 1 do
		realProgress = math.min(assetProgress, mapProgress())
		task.wait(0.5)
	end
end)

------------------------------------------------------------------------
-- BOUCLE D'ANIMATION
------------------------------------------------------------------------
local speed = make("NumberValue", { Value = 1 })
local clock, rayAngle, sparkTimer = 0, 0, 0
local outro

conn = RunService.RenderStepped:Connect(function(dt)
	clock += dt
	local s = speed.Value

	-- étoiles
	local a = starAlpha.Value
	for _, st in stars do
		st.y -= st.drift * dt
		if st.y < -0.02 then
			st.y = 1.02
		end
		st.frame.Position = UDim2.fromScale(st.x, st.y)
		st.frame.BackgroundTransparency = 1 - a * (0.25 + 0.65 * (0.5 + 0.5 * math.sin(clock * st.speed + st.phase)))
	end

	-- halos qui respirent
	for i, h in halos do
		h.scale.Scale = 1 + 0.018 * math.sin(clock * 0.8 + i * 1.3)
	end

	-- rayons
	rayAngle += dt * 5 * s
	for i, r in rays do
		r.frame.Rotation = r.base + rayAngle
		r.frame.Size = UDim2.fromOffset(r.width, 600 + 90 * math.sin(clock * 1.3 + i * 1.7))
	end

	-- anneaux
	for _, ring in rings do
		ring.grad.Rotation = (ring.grad.Rotation + ring.speed * s * dt) % 360
	end

	-- gemme flottante + lueur
	gemHolder.Position = UDim2.fromOffset(CENTER_X, GEM_Y + math.sin(clock * 1.6) * 6)
	outerGlow.BackgroundTransparency = 0.86 + 0.05 * math.sin(clock * 2.2)

	-- étincelles
	if sparksOn then
		sparkTimer += dt
		while sparkTimer > 0.12 do
			sparkTimer -= 0.12
			spark()
		end
	end

	-- progression
	if not exiting then
		local elapsed = os.clock() - startTime
		local goal = math.min(math.max(realProgress, math.min(elapsed * 0.05, 0.2)), elapsed / CONFIG.MinDuration)
		displayed += (goal - displayed) * (1 - math.exp(-dt * 3))

		fill.Size = UDim2.fromScale(displayed, 1)
		head.Position = UDim2.fromScale(displayed, 0.5)
		headGlow.Position = head.Position
		headGlow.Size = UDim2.fromOffset(34 + 6 * math.sin(clock * 5), 34 + 6 * math.sin(clock * 5))
		status.Text = string.format('%s  <font color="#F6C46E">%d %%</font>', CONFIG.Status, math.floor(displayed * 100 + 0.5))

		if introDone and realProgress >= 1 and goal >= 1 and displayed > 0.995 then
			exiting = true
			task.spawn(outro)
		end
	end

	-- reflet qui glisse sur la barre
	sheen.Position = UDim2.fromScale((clock * 0.6) % 1.6 - 0.3, 0)
end)

------------------------------------------------------------------------
-- APPARITION
------------------------------------------------------------------------
local function startTips()
	if #CONFIG.Tips < 2 then
		return
	end
	task.spawn(function()
		local index = 1
		while not exiting do
			task.wait(CONFIG.TipInterval)
			if exiting then
				break
			end
			index = index % #CONFIG.Tips + 1
			tween(tip, 0.4, { TextTransparency = 1, Position = UDim2.fromOffset(CENTER_X, TIP_Y - 10) }, Enum.EasingStyle.Sine).Completed:Wait()
			if exiting then
				break
			end
			tip.Text = CONFIG.Tips[index]
			tip.Position = UDim2.fromOffset(CENTER_X, TIP_Y + 10)
			tween(tip, 0.6, { TextTransparency = 0.15, Position = UDim2.fromOffset(CENTER_X, TIP_Y) })
		end
	end)

	task.spawn(function()
		while not exiting do
			task.wait(4.5)
			if not exiting then
				shimmer()
			end
		end
	end)
end

-- Écran sobre : fond, barre de progression et astuces, sans animation d'entrée.
local function intro()
	cover.BackgroundTransparency = 1
	starAlpha.Value = 1
	track.Size = UDim2.fromOffset(862, 8)
	track.BackgroundTransparency = 0.35
	head.BackgroundTransparency = 0
	headGlow.BackgroundTransparency = 0.65
	status.TextTransparency = 0
	tip.TextTransparency = 0.15

	-- Logo : la gemme et ses anneaux apparaissent, puis le titre lettre par lettre.
	tween(gemScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tween(ringScale, 0.9, { Scale = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	for _, ring in rings do
		tween(ring.stroke, 0.8, { Transparency = 0 }, Enum.EasingStyle.Sine)
	end
	for i, l in letters do
		local delay = 0.3 + (i - 1) * 0.05
		tween(l.label, 0.55, { Position = l.final, TextTransparency = 0, Rotation = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delay)
		tween(l.shadow, 0.55, { Position = l.shadowFinal, TextTransparency = 0.4, Rotation = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delay)
		tween(l.stroke, 0.55, { Transparency = 0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, delay)
	end
	local subDelay = 0.3 + #letters * 0.05 + 0.2
	tween(subtitle, 0.6, { TextTransparency = 0, Position = UDim2.fromOffset(CENTER_X, SUB_Y) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, subDelay)
	tween(lineL, 0.6, { Size = UDim2.fromOffset(150, 2) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, subDelay)
	tween(lineR, 0.6, { Size = UDim2.fromOffset(150, 2) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, subDelay)
	task.delay(subDelay + 0.6, shimmer)

	introDone = true
	startTips()
end

------------------------------------------------------------------------
-- SORTIE : charge, explosion, flash, révélation du jeu
------------------------------------------------------------------------
-- Fin du chargement : fondu rapide, le menu apparaît directement.
outro = function()
	fill.Size = UDim2.fromScale(1, 1)
	head.Position = UDim2.fromScale(1, 0.5)
	headGlow.Position = head.Position
	status.Text = CONFIG.DoneStatus
	status.TextColor3 = C.gold
	tween(flash, 0.25, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
	conn:Disconnect()
	root:Destroy()
	player:SetAttribute("ArcanaLoaded", true)
	tween(flash, 0.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quint).Completed:Wait()
	gui:Destroy()
end

intro()
