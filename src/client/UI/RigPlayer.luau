-- Créatures en voxels animées (membres rigides), à partir des données
-- générées par tools/glb_to_rig.py (ReplicatedStorage.Rigs.<id>).
--
-- Chaque nœud du modèle (corps, tête, pattes, queue...) a une articulation
-- invisible ancrée ; ses cubes y sont soudés. À chaque image, seules les
-- articulations sont déplacées (quelques dizaines de pièces, pas des centaines).
--
-- Trois couches d'animation : la boucle de fond (repos, marche, course), une
-- action ponctuelle par-dessus (attaque, coup reçu, K.O.) et la couche
-- d'effets (braises) qui tourne en permanence.
local RunService = game:GetService("RunService")

local RigPlayer = {}

type Track = { Node: number, Path: string, Times: { number }, Values: { number } }
type Anim = { Loop: boolean, Length: number, Tracks: { Track }, ByNode: { [number]: { [string]: Track } } }

local states = setmetatable({}, { __mode = "k" }) :: { [Model]: any }
local prepared = setmetatable({}, { __mode = "k" }) :: { [any]: { [string]: Anim } }

-- Prépare (une fois par fichier) les pistes d'animation par nœud.
local function animations(data): { [string]: Anim }
	local cached = prepared[data]
	if cached then
		return cached
	end
	local out = {}
	for name, a in pairs(data.Animations or {}) do
		local byNode = {}
		for _, tr in ipairs(a.Tracks) do
			local track = { Node = tr[1], Path = tr[2], Times = tr[3], Values = tr[4] }
			byNode[track.Node] = byNode[track.Node] or {}
			byNode[track.Node][track.Path] = track
		end
		out[name] = { Loop = a.Loop, Length = a.Length or 0, ByNode = byNode, Tracks = a.Tracks }
	end
	prepared[data] = out
	return out
end

-- Valeur d'une piste au temps t (interpolation linéaire, n = 3 ou 4 composantes).
local function sample(track: Track, t: number, n: number): { number }
	local times, values = track.Times, track.Values
	local count = #times
	if t <= times[1] or count == 1 then
		return table.move(values, 1, n, 1, {})
	end
	if t >= times[count] then
		return table.move(values, (count - 1) * n + 1, count * n, 1, {})
	end
	local k = 1
	while k < count and times[k + 1] < t do
		k += 1
	end
	local t0, t1 = times[k], times[k + 1]
	local f = if t1 > t0 then (t - t0) / (t1 - t0) else 0
	local out = table.create(n)
	local a, b = (k - 1) * n, k * n
	if n == 4 then
		-- Quaternions : chemin le plus court, puis normalisation.
		local dot = 0
		for c = 1, 4 do
			dot += values[a + c] * values[b + c]
		end
		local sign = if dot < 0 then -1 else 1
		local len = 0
		for c = 1, 4 do
			out[c] = values[a + c] + (values[b + c] * sign - values[a + c]) * f
			len += out[c] * out[c]
		end
		len = math.sqrt(len)
		if len > 1e-6 then
			for c = 1, 4 do
				out[c] /= len
			end
		end
	else
		for c = 1, n do
			out[c] = values[a + c] + (values[b + c] - values[a + c]) * f
		end
	end
	return out
end

local function rotation(q: { number }): CFrame
	return CFrame.new(0, 0, 0, q[1], q[2], q[3], q[4])
end

-- Transformation locale d'un nœud : repos, puis couches dans l'ordre.
local function localTRS(state, i: number)
	local node = state.Data.Nodes[i]
	local t, r, s = node.T, node.R, node.S
	for _, layer in ipairs(state.Layers) do
		local tracks = layer.Anim and layer.Anim.ByNode[i]
		if tracks then
			if tracks.T then
				t = sample(tracks.T, layer.Time, 3)
			end
			if tracks.R then
				r = sample(tracks.R, layer.Time, 4)
			end
			if tracks.S then
				s = sample(tracks.S, layer.Time, 3)
			end
		end
	end
	return t, r, s
end

-- Pose complète : repère (en mètres, repère du modèle) et échelle de chaque nœud.
local function pose(state): ({ CFrame }, { number })
	local nodes = state.Data.Nodes
	local frames, scales = {}, {}
	local function solve(i: number)
		if frames[i] then
			return
		end
		local node = nodes[i]
		local t, r, s = localTRS(state, i)
		local ps, pf = 1, CFrame.identity
		if node.Parent > 0 then
			solve(node.Parent)
			ps, pf = scales[node.Parent], frames[node.Parent]
		end
		local own = math.min(s[1], s[2], s[3])
		frames[i] = pf * CFrame.new(t[1] * ps, t[2] * ps, t[3] * ps) * rotation(r)
		scales[i] = ps * own
	end
	for i = 1, #nodes do
		solve(i)
	end
	return frames, scales
end

local function apply(state)
	local frames, scales = pose(state)
	local base = state.Root.CFrame * state.Offset
	local k = state.K
	for i, joint in pairs(state.Joints) do
		local f = frames[i]
		joint.CFrame = base * CFrame.new(f.Position * k) * f.Rotation
		-- Échelle animée (griffures, braises) : visible ou caché.
		local visible = scales[i] > 0.3
		if visible ~= state.Visible[i] then
			state.Visible[i] = visible
			for _, p in ipairs(state.Parts[i]) do
				p.Transparency = if visible then p:GetAttribute("BaseT") or 0 else 1
			end
		end
	end
end

-- Taille à l'écran : plus grande dimension ≈ size × SIZE_FACTOR studs.
local SIZE_FACTOR = 2.4
-- Seuls les petits blocs lumineux (yeux, braises, pointes de flammes) restent
-- en Neon ; les grandes masses de flammes passent en mat (sinon tout éblouit).
local NEON_MAX_VOXELS = 2

-- Construit le modèle à la taille voulue.
function RigPlayer.build(data, size: number): Model
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Transparency = 1
	root.Size = Vector3.one * 0.2
	root.Parent = model
	model.PrimaryPart = root

	local state = { Data = data, Root = root, Joints = {}, Parts = {}, Visible = {}, Layers = {}, Speed = 1 }
	state.Anims = animations(data)
	state.Layers = {
		{ Anim = state.Anims.repos, Name = "repos", Time = 0, Loop = true }, -- fond
		{ Anim = state.Anims.effet_braises, Name = "effet_braises", Time = 0, Loop = true }, -- effets
		{ Anim = nil, Name = nil, Time = 0, Loop = false }, -- action
	}

	-- Boîte englobante de la pose de repos (en mètres) pour l'échelle et le centre.
	local rest = { Data = data, Layers = {} }
	local frames, scales = pose(rest)
	local vox = data.Voxel or 0.1
	local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
	for i, node in ipairs(data.Nodes) do
		if scales[i] > 0.3 then
			for _, b in ipairs(node.Boxes) do
				for _, corner in ipairs({ Vector3.new(b[1], b[2], b[3]), Vector3.new(b[1] + b[4], b[2] + b[5], b[3] + b[6]) }) do
					local w = frames[i] * (corner * vox * scales[i])
					minV, maxV = minV:Min(w), maxV:Max(w)
				end
			end
		end
	end
	local extent = maxV - minV
	local k = size * SIZE_FACTOR / math.max(extent.X, extent.Y, extent.Z, 1e-3)
	state.K = k
	state.Offset = CFrame.new(-(minV + maxV) / 2 * k)
	model:SetAttribute("HalfHeight", extent.Y * k / 2)

	-- Articulations et cubes soudés.
	for i, node in ipairs(data.Nodes) do
		if #node.Boxes > 0 then
			local joint = Instance.new("Part")
			joint.Name = node.Name
			joint.Anchored = true
			joint.CanCollide = false
			joint.CanQuery = false
			joint.CanTouch = false
			joint.Transparency = 1
			joint.Size = Vector3.one * 0.1
			joint.CFrame = root.CFrame * state.Offset * CFrame.new(frames[i].Position * k) * frames[i].Rotation
			joint.Parent = model
			local parts = {}
			for _, b in ipairs(node.Boxes) do
				local entry = data.Palette[b[7]]
				local p = Instance.new("Part")
				p.Anchored = false
				p.Massless = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.TopSurface = Enum.SurfaceType.Smooth
				p.BottomSurface = Enum.SurfaceType.Smooth
				p.Size = Vector3.new(b[4], b[5], b[6]) * vox * k
				p.Color = entry[1]
				local small = b[4] * b[5] * b[6] <= NEON_MAX_VOXELS
				p.Material = if entry[2] and small then Enum.Material.Neon else Enum.Material.SmoothPlastic
				p.Transparency = entry[3] or 0
				p:SetAttribute("BaseT", p.Transparency)
				p.CFrame = joint.CFrame * CFrame.new((Vector3.new(b[1], b[2], b[3]) + Vector3.new(b[4], b[5], b[6]) / 2) * vox * k)
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = joint
				weld.Part1 = p
				weld.Parent = p
				p.Parent = joint
				table.insert(parts, p)
			end
			state.Joints[i] = joint
			state.Parts[i] = parts
			state.Visible[i] = true
		end
	end
	model:SetAttribute("Rig", true)
	states[model] = state
	apply(state)
	return model
end

function RigPlayer.isRig(model: Model?): boolean
	return model ~= nil and states[model] ~= nil
end

function RigPlayer.has(model: Model?, name: string): boolean
	local state = model and states[model]
	return state ~= nil and state.Anims[name] ~= nil
end

-- Joue une animation : en boucle (fond) ou ponctuelle (action, par-dessus).
function RigPlayer.play(model: Model?, name: string, speed: number?): boolean
	local state = model and states[model]
	local anim = state and state.Anims[name]
	if not anim then
		return false
	end
	local layer = if anim.Loop then state.Layers[1] else state.Layers[3]
	layer.Anim, layer.Name, layer.Time, layer.Loop = anim, name, 0, anim.Loop
	layer.Speed = speed or 1
	return true
end

-- Arrête une animation : le fond revient au repos, l'action s'efface.
function RigPlayer.stop(model: Model?, name: string)
	local state = model and states[model]
	if not state then
		return
	end
	if state.Layers[1].Name == name then
		local layer = state.Layers[1]
		layer.Anim, layer.Name, layer.Time, layer.Speed = state.Anims.repos, "repos", 0, 1
	end
	if state.Layers[3].Name == name then
		state.Layers[3].Anim, state.Layers[3].Name = nil, nil
	end
end

RunService.RenderStepped:Connect(function(dt)
	for model, state in pairs(states) do
		if model.Parent and state.Root.Parent then
			state.Placed = true
			for _, layer in ipairs(state.Layers) do
				if layer.Anim then
					layer.Time += dt * (layer.Speed or 1)
					if layer.Time >= layer.Anim.Length then
						if layer.Loop then
							layer.Time = if layer.Anim.Length > 0 then layer.Time % layer.Anim.Length else 0
						elseif layer == state.Layers[3] then
							-- Action terminée (sauf le K.O., qui reste sur sa dernière pose).
							if layer.Name ~= "ko" then
								layer.Anim, layer.Name = nil, nil
							else
								layer.Time = layer.Anim.Length
							end
						end
					end
				end
			end
			apply(state)
		elseif not model.Parent and state.Placed then
			-- Retiré de la scène après y avoir été : on l'oublie.
			states[model] = nil
		end
	end
end)

return RigPlayer
