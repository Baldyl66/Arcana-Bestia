-- Animation des décors 3D importés (galion, lampadaires), reproduite d'après
-- les fichiers Claude Design : l'import Roblox ne conserve pas correctement
-- les déplacements des os, on les recalcule donc ici à chaque image.
local RunService = game:GetService("RunService")

local PropsFX = {}

local TAU = math.pi * 2
local RANGE = 320

-- Voiles du galion : nom, axe de gonflement, amplitude (comme dans le HTML).
local SAILS = {
	{ "v_grand_1", "x", 0.55 }, { "v_grand_2", "x", 0.45 }, { "v_grand_3", "x", 0.35 },
	{ "v_misaine_1", "x", 0.5 }, { "v_misaine_2", "x", 0.42 }, { "v_misaine_3", "x", 0.3 },
	{ "v_artimon_1", "x", 0.35 }, { "v_foc_1", "z", 0.4 }, { "v_foc_2", "z", 0.32 }, { "v_brigantine", "z", 0.45 },
}
local LANTERNS = { "lanterne_poupe_g", "lanterne_poupe_d", "lanterne_vergue_g", "lanterne_vergue_d", "lanterne_proue" }

type Rig = { Model: Model, Kind: string, Bones: { [string]: Bone }, K: number, Lights: { PointLight }, Seed: number }

local rigs: { Rig } = {}

local function setBone(rig: Rig, name: string, p: { number }, r: { number })
	local b = rig.Bones[name]
	if b then
		local k = rig.K
		b.Transform = CFrame.new(p[1] * k, p[2] * k, p[3] * k) * CFrame.fromEulerAnglesXYZ(r[1], r[2], r[3])
	end
end

local function register(model: Model)
	local kind = model:GetAttribute("ArcanaProp")
	if type(kind) ~= "string" then
		return
	end
	local bones = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Bone") then
			bones[d.Name] = d
		end
	end
	-- Échelle studs / unité du fichier, d'après la position de repos d'un os connu.
	local k = 1
	if kind == "Galion" then
		-- Le galion mesure 14,12 unités de long dans le fichier.
		local _, size = model:GetBoundingBox()
		k = math.max(size.X, size.Z) / 14.12
	elseif kind == "Lampadaire" and bones.flamme then
		local _, size = model:GetBoundingBox()
		k = size.Y / 4.862
	end
	local unit = model:GetAttribute("UnitScale")
	if type(unit) == "number" and unit > 0 then
		k = unit
	end
	local lights = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("PointLight") then
			d:SetAttribute("BaseBrightness", d.Brightness)
			table.insert(lights, d)
		end
	end
	-- Pièces dont la couleur change entre le jour (ambre) et la nuit (arcane).
	local glow = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "flamme_neon" or d.Name == "flamme" or d.Name == "verre") then
			table.insert(glow, d)
		end
	end
	-- Torche : pièces animées sans os (flammes et cristaux), position de repos mémorisée.
	local moving = {}
	if kind == "Torche" then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and (string.sub(d.Name, 1, 7) == "flamme_" or string.sub(d.Name, 1, 7) == "cristal") then
				table.insert(moving, { Part = d, Rest = d.CFrame, Size = d.Size, Flame = string.sub(d.Name, 1, 7) == "flamme_" })
			end
		end
	end
	table.insert(rigs, { Model = model, Kind = kind, Bones = bones, K = k, Lights = lights, Glow = glow, Seed = math.random() * 10,
		Moving = moving, Axis = model:GetPivot() })
end

local function animateGalleon(rig: Rig, t: number)
	-- Animation « Navigation » : cycle de 8 s.
	local w, k = TAU / 8, 1
	setBone(rig, "coque", { 0, 0.07 * k * math.sin(w * 2 * t), 0 }, { 0.045 * k * math.sin(w * t + 1), 0, 0.028 * k * math.sin(w * 2 * t + 0.5) })
	for si, sail in ipairs(SAILS) do
		for r = 1, 2 do
			local d = sail[3] * (r == 1 and 0.14 or 0.22) * math.sin(w * 4 * t + (si - 1) * 0.7 + r * 0.9)
			setBone(rig, sail[1] .. "_" .. r, sail[2] == "x" and { d, 0, 0 } or { 0, 0, d }, { 0, 0, 0 })
		end
	end
	for i = 1, 4 do
		setBone(rig, "drapeau_" .. i, { 0, 0, 0 }, { 0, 0.22 * math.sin(w * 8 * t - i * 0.9), 0.04 * math.sin(w * 8 * t - i) })
	end
	for i, name in ipairs(LANTERNS) do
		setBone(rig, name, { 0, 0, 0 }, { 0.1 * math.sin(w * 2 * t + i - 1), 0, 0.08 * math.sin(w * 2 * t + i) })
	end
	for _, sd in ipairs({ { "g", -1 }, { "d", 1 } }) do
		setBone(rig, "helice_" .. sd[1], { 0, 0, 0 }, { sd[2] * w * 8 * t, 0, 0 })
		setBone(rig, "ailes_" .. sd[1], { 0, 0, 0 }, { sd[2] * 0.22 * math.sin(w * 4 * t), 0, 0.08 * math.sin(w * 4 * t + 1) })
	end
	setBone(rig, "cristal", { 0, 0.08 * math.sin(w * 2 * t), 0 }, { 0, w * t, 0 })
	setBone(rig, "anneau", { 0, 0.05 * math.sin(w * 2 * t + 1), 0 }, { 0.25 * math.sin(w * t), -w * 2 * t, 0.2 * math.cos(w * t) })
end

-- Palettes du HTML : « ambre » le jour, « arcane » (bleu) la nuit.
local DAY = { Flame = Color3.fromRGB(255, 175, 70), Glass = Color3.fromRGB(255, 225, 170), Light = Color3.fromRGB(255, 190, 110) }
local NIGHT = { Flame = Color3.fromRGB(70, 200, 255), Glass = Color3.fromRGB(200, 244, 255), Light = Color3.fromRGB(127, 216, 255) }
local Lighting = game:GetService("Lighting")
local nightMix = 0

local function updateNight(dt: number)
	local clock = Lighting.ClockTime
	-- Transition douce au crépuscule (17h30-19h) et à l'aube (5h-6h30).
	local target
	if clock >= 19 or clock <= 5 then
		target = 1
	elseif clock > 17.5 then
		target = (clock - 17.5) / 1.5
	elseif clock < 6.5 then
		target = (6.5 - clock) / 1.5
	else
		target = 0
	end
	nightMix += (target - nightMix) * math.clamp(dt * 2, 0, 1)
end

local function animateLamp(rig: Rig, t: number)
	-- Animation « Lueur » : la flamme flotte et tourne (cycle de 4 s).
	local D = 4
	setBone(rig, "flamme", { 0, 0.03 * math.sin(t * TAU / D * 2), 0 }, { 0, t * TAU / D, 0 })
	local f = 1 + 0.08 * math.sin(t * 13) + 0.05 * math.sin(t * 7.3)
	for _, light in ipairs(rig.Lights) do
		-- La nuit, la lueur est plus forte (comme le mode nuit du HTML).
		light.Brightness = (light:GetAttribute("BaseBrightness") or light.Brightness) * f * (1 + nightMix * 0.8)
		light.Color = DAY.Light:Lerp(NIGHT.Light, nightMix)
	end
	for _, part in ipairs((rig :: any).Glow or {}) do
		part.Color = part.Name == "verre" and DAY.Glass:Lerp(NIGHT.Glass, nightMix) or DAY.Flame:Lerp(NIGHT.Flame, nightMix)
	end
end

-- Torche : flammes qui ondulent et tournent autour de l'axe, cristaux qui flottent.
local function animateTorch(rig: any, t: number)
	local axis: CFrame = rig.Axis
	local h = rig.Model:GetExtentsSize().Y
	for i, m in ipairs(rig.Moving) do
		local local0 = axis:ToObjectSpace(m.Rest)
		if m.Flame then
			local sy = 1 + 0.18 * math.sin(t * 9 + i * 1.7) + 0.08 * math.sin(t * 15.3 + i)
			local sx = 1 + 0.08 * math.sin(t * 11 + i * 2.3)
			m.Part.Size = Vector3.new(m.Size.X * sx, m.Size.Y * sy, m.Size.Z * sx)
			local spin = CFrame.Angles(0, t * 1.8 + i * 0.4, 0)
			local sway = CFrame.Angles(0.06 * math.sin(t * 6 + i), 0, 0.06 * math.cos(t * 7 + i))
			m.Part.CFrame = axis * spin * sway * local0 * CFrame.new(0, m.Size.Y * (sy - 1) / 2, 0)
		else
			local bob = CFrame.new(0, h * 0.012 * math.sin(t * 2 + i), 0)
			m.Part.CFrame = axis * bob * CFrame.Angles(0, t * 0.6, 0) * local0
		end
	end
	local f = 1 + 0.15 * math.sin(t * 13) + 0.1 * math.sin(t * 7.3)
	for _, light in ipairs(rig.Lights) do
		light.Brightness = (light:GetAttribute("BaseBrightness") or light.Brightness) * f
	end
end

-- Arène des Champions : formules du fichier Claude Design.
-- Terme : { canal, amplitude, n, k_phase, phase0 } -> A·sin(n·ω·t + k·i + p0) ;
-- amplitude "spin" -> n·ω·t.
local ARENA_GROUPS = {
	{ Prefix = "banniere_", From = 1, Count = 24, Offset = 0,
		Repos = { { "ry", 0.16, 2, 0.7, 0 }, { "rz", 0.05, 2, 0.7, 1.2 } }, Combat = { { "ry", 0.42, 6, 0.7, 0 }, { "rz", 0.12, 6, 0.7, 1.2 } } },
	{ Prefix = "banniere_", From = 25, Count = 4, Offset = 24,
		Repos = { { "rx", 0.06, 2, 1.1, 0 } }, Combat = { { "rx", 0.2, 6, 1.1, 0 } } },
	{ Prefix = "voile_", From = 1, Count = 24, Offset = 0,
		Repos = { { "dy", 0.5, 1, 0.6, 0 } }, Combat = { { "dy", 1.2, 2, 0.6, 0 } } },
	{ Prefix = "flamme_", From = 1, Count = 18, Offset = 0,
		Repos = { { "dy", 0.06, 4, 1.3, 0 }, { "rx", 0.05, 6, 1.0, 0 }, { "rz", 0.05, 8, 2.0, 0 }, { "ry", "spin", 1 } },
		Combat = { { "dy", 0.15, 8, 1.3, 0 }, { "rx", 0.12, 12, 1.0, 0 }, { "rz", 0.12, 16, 2.0, 0 }, { "ry", "spin", 2 } } },
}
local CLIP_PERIOD = { Repos = 8, Combat = 4 }
local HERSE_H = 11
local herseOpen = 1 -- 1 = herses levées (on peut entrer), 0 = baissées

local function animateArena(rig: Rig, t: number, dt: number)
	local combat = workspace:GetAttribute("ColosseumCombat") == true
	local clip = combat and "Combat" or "Repos"
	local w = TAU / CLIP_PERIOD[clip]
	for _, g in ipairs(ARENA_GROUPS) do
		for n = g.From, g.From + g.Count - 1 do
			local i = n - g.Offset
			local o = { dx = 0, dy = 0, dz = 0, rx = 0, ry = 0, rz = 0 }
			for _, term in ipairs(g[clip]) do
				if term[2] == "spin" then
					o[term[1]] += term[3] * w * t
				else
					o[term[1]] += term[2] * math.sin(term[3] * w * t + term[4] * i + term[5])
				end
			end
			setBone(rig, g.Prefix .. n, { o.dx, o.dy, o.dz }, { o.rx, o.ry, o.rz })
		end
	end
	-- Herses : levées hors combat, elles descendent (3 s, comme « Ouverture_portes »
	-- à l'envers) et vibrent pendant un combat.
	herseOpen = math.clamp(herseOpen + (combat and -dt or dt) / 3, 0, 1)
	local e = herseOpen * herseOpen * (3 - 2 * herseOpen)
	for i, name in ipairs({ "herse_ouest", "herse_est" }) do
		local shakeY = combat and 0.08 * math.sin(24 * TAU / 4 * t) or 0
		local shakeX = combat and 0.04 * math.sin(32 * TAU / 4 * t) or 0
		setBone(rig, name, { shakeX, HERSE_H * e + shakeY, 0 }, { 0, 0, 0 })
	end
end

function PropsFX.start()
	while not workspace:GetAttribute("VillageReady") do
		task.wait(1)
	end
	task.wait(1)
	local world = workspace:WaitForChild("World")
	for _, d in ipairs(world:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("ArcanaProp") then
			register(d)
		end
	end
	RunService.RenderStepped:Connect(function(dt)
		updateNight(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local camPos = camera.CFrame.Position
		local now = os.clock()
		for _, rig in ipairs(rigs) do
			if rig.Model.Parent and (rig.Model:GetPivot().Position - camPos).Magnitude < RANGE then
				if rig.Kind == "Galion" then
					animateGalleon(rig, now)
				elseif rig.Kind == "Arene" then
					animateArena(rig, now, dt)
				elseif rig.Kind == "Torche" then
					animateTorch(rig, now + rig.Seed)
				else
					animateLamp(rig, now + rig.Seed)
				end
			end
		end
	end)
end

return PropsFX
