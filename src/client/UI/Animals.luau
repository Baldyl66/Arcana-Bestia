-- Animaux de la ferme animés localement : ils broutent ou picorent, puis
-- marchent vers un nouveau point de leur enclos en bougeant les pattes.
-- Les pièces sont non collidables, l'animation reste donc purement visuelle.
local RunService = game:GetService("RunService")

local Animals = {}

local SPEED = { Hen = 3.2, Sheep = 2.6, Cow = 2.2 }
local STRIDE = { Hen = 14, Sheep = 7, Cow = 5 }
local MAX_DISTANCE = 260

type Rig = {
	Model: Model,
	Kind: string,
	Parts: { BasePart },
	Offsets: { CFrame },
	Roles: { string },
	LegSign: { number },
	LegTop: { [number]: CFrame },
	HeadPivot: CFrame,
	Min: Vector2,
	Max: Vector2,
	Root: CFrame,
	Target: Vector3?,
	Wait: number,
	Phase: number,
	Head: number,
	Seed: number,
}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundAt(x: number, z: number, fallback: number): number
	local hit = workspace:Raycast(Vector3.new(x, fallback + 30, z), Vector3.new(0, -80, 0), rayParams)
	return hit and hit.Position.Y or fallback
end

local function build(model: Model): Rig?
	local kind = model:GetAttribute("Animal")
	if type(kind) ~= "string" then
		return nil
	end
	local root = model:GetPivot()
	local rig: Rig = {
		Model = model,
		Kind = kind,
		Parts = {},
		Offsets = {},
		Roles = {},
		LegSign = {},
		LegTop = {},
		HeadPivot = CFrame.new(model:GetAttribute("HeadPivot") or Vector3.zero),
		Min = model:GetAttribute("Min") or Vector2.zero,
		Max = model:GetAttribute("Max") or Vector2.zero,
		Root = root,
		Target = nil,
		Wait = math.random() * 4,
		Phase = math.random() * math.pi * 2,
		Head = 0,
		Seed = math.random() * 100,
	}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local offset = root:ToObjectSpace(p.CFrame)
			local role = p:GetAttribute("Rig") or "Body"
			table.insert(rig.Parts, p)
			table.insert(rig.Offsets, offset)
			table.insert(rig.Roles, role)
			-- Pattes en diagonale synchronisées (avant gauche avec arrière droite).
			local sign = (offset.Position.X >= 0) == (offset.Position.Z >= 0) and 1 or -1
			if kind == "Hen" then
				sign = offset.Position.X >= 0 and 1 or -1
			end
			table.insert(rig.LegSign, sign)
		end
	end
	-- Articulation des pattes : à la hanche, au sommet de la plus haute pièce de patte.
	local hip = 0
	for i, role in ipairs(rig.Roles) do
		if role == "Leg" then
			hip = math.max(hip, rig.Offsets[i].Position.Y + rig.Parts[i].Size.Y / 2)
		end
	end
	for i, role in ipairs(rig.Roles) do
		if role == "Leg" then
			local o = rig.Offsets[i].Position
			rig.LegTop[i] = CFrame.new(o.X, hip, o.Z)
		end
	end
	return rig
end

local function pickTarget(rig: Rig)
	local x = rig.Min.X + math.random() * (rig.Max.X - rig.Min.X)
	local z = rig.Min.Y + math.random() * (rig.Max.Y - rig.Min.Y)
	local from = rig.Root.Position
	local dist = math.min((Vector2.new(x, z) - Vector2.new(from.X, from.Z)).Magnitude, rig.Kind == "Hen" and 10 or 18)
	local dir = (Vector3.new(x, from.Y, z) - from)
	if dir.Magnitude < 1 then
		return
	end
	local goal = from + dir.Unit * dist
	rig.Target = Vector3.new(goal.X, groundAt(goal.X, goal.Z, from.Y), goal.Z)
end

local function step(rig: Rig, dt: number, now: number, parts: { BasePart }, cframes: { CFrame })
	local walking = false
	if rig.Target then
		local pos = rig.Root.Position
		local flat = Vector3.new(rig.Target.X - pos.X, 0, rig.Target.Z - pos.Z)
		local dist = flat.Magnitude
		if dist < 0.3 then
			rig.Target = nil
			rig.Wait = rig.Kind == "Hen" and 1 + math.random() * 3 or 3 + math.random() * 7
		else
			walking = true
			local look = rig.Root.LookVector
			local desired = flat.Unit
			-- Rotation progressive vers la destination avant d'avancer franchement.
			local turned = look:Lerp(desired, math.clamp(dt * 3, 0, 1))
			local facing = Vector3.new(turned.X, 0, turned.Z).Unit
			local speed = SPEED[rig.Kind] * math.clamp(look:Dot(desired), 0.15, 1)
			local move = math.min(speed * dt, dist)
			local newPos = pos + facing * move
			local y = pos.Y + (rig.Target.Y - pos.Y) * math.clamp(move / dist, 0, 1)
			newPos = Vector3.new(newPos.X, y, newPos.Z)
			rig.Root = CFrame.lookAt(newPos, newPos + facing)
			rig.Phase += dt * STRIDE[rig.Kind] * (speed / SPEED[rig.Kind])
		end
	else
		rig.Wait -= dt
		if rig.Wait <= 0 then
			pickTarget(rig)
		end
	end

	-- Tête : broute (moutons, vaches) ou picore (poules) à l'arrêt.
	local headPitch, headYaw = 0, 0
	if walking then
		rig.Head += (0 - rig.Head) * math.clamp(dt * 4, 0, 1)
		headPitch = rig.Head + math.sin(rig.Phase * 2) * 0.05
	elseif rig.Kind == "Hen" then
		local peck = math.max(0, math.sin(now * 7 + rig.Seed)) ^ 6
		headPitch = peck * 0.9
		headYaw = math.sin(now * 0.9 + rig.Seed) * 0.4
	else
		local grazing = math.sin(now * 0.25 + rig.Seed) > -0.3
		rig.Head += ((grazing and 0.75 or -0.05) - rig.Head) * math.clamp(dt * 1.5, 0, 1)
		headPitch = rig.Head + (grazing and math.sin(now * 3 + rig.Seed) * 0.04 or 0)
		headYaw = grazing and 0 or math.sin(now * 0.6 + rig.Seed) * 0.35
	end
	local headCf = rig.HeadPivot * CFrame.Angles(-headPitch, headYaw, 0) * rig.HeadPivot:Inverse()

	local swing = walking and math.sin(rig.Phase) or 0
	local bob = walking and math.abs(math.sin(rig.Phase)) * (rig.Kind == "Hen" and 0.12 or 0.08) or math.sin(now * 1.5 + rig.Seed) * 0.02
	local body = rig.Root * CFrame.new(0, bob, 0)
	if rig.Kind == "Hen" and walking then
		body *= CFrame.Angles(0, 0, math.sin(rig.Phase) * 0.08)
	end

	for i, p in ipairs(rig.Parts) do
		local role = rig.Roles[i]
		local offset = rig.Offsets[i]
		local cf
		if role == "Head" then
			cf = body * headCf * offset
		elseif role == "Leg" then
			-- Rotation autour du haut de la patte.
			local top = rig.LegTop[i]
			local angle = swing * rig.LegSign[i] * (rig.Kind == "Hen" and 0.6 or 0.45)
			cf = rig.Root * top * CFrame.Angles(angle, 0, 0) * top:Inverse() * offset
		else
			cf = body * offset
		end
		table.insert(parts, p)
		table.insert(cframes, cf)
	end
end

function Animals.start()
	local rigs: { Rig } = {}
	local known: { [Model]: boolean } = {}

	local function scan()
		local world = workspace:FindFirstChild("World")
		if not world then
			return
		end
		for _, inst in ipairs(world:GetDescendants()) do
			if inst:IsA("Model") and inst:GetAttribute("Animal") and not known[inst] then
				known[inst] = true
				local rig = build(inst)
				if rig then
					table.insert(rigs, rig)
				end
				local folder = inst.Parent
				if folder then
					rayParams.FilterDescendantsInstances = { folder }
				end
			end
		end
	end

	while not workspace:GetAttribute("VillageReady") do
		task.wait(1)
	end
	task.wait(1)
	scan()

	RunService.Heartbeat:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera or #rigs == 0 then
			return
		end
		local camPos = camera.CFrame.Position
		local now = os.clock()
		local parts, cframes = {}, {}
		for _, rig in ipairs(rigs) do
			if rig.Model.Parent and (rig.Root.Position - camPos).Magnitude < MAX_DISTANCE then
				step(rig, math.min(dt, 0.1), now, parts, cframes)
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return Animals
