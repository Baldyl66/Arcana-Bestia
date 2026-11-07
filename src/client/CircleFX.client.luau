-- Cercle des Arcanes : anime localement les cristaux des piliers et les
-- pierres runiques en lévitation (lent flottement, rotation, orbite).
local RunService = game:GetService("RunService")

while not workspace:GetAttribute("WorldReady") do
	workspace:GetAttributeChangedSignal("WorldReady"):Wait()
end
local world = workspace:WaitForChild("World")
local circle = world:WaitForChild("Colosseum", 30)
if not circle then
	return
end

local items = {}
for _, d in ipairs(circle:GetDescendants()) do
	if d:IsA("BasePart") and d:GetAttribute("Floating") then
		local children = {}
		for _, child in ipairs(d:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(children, { Part = child, Offset = d.CFrame:ToObjectSpace(child.CFrame) })
			end
		end
		table.insert(items, { Part = d, Base = d.CFrame, Orbit = d:GetAttribute("Orbit") == true, Phase = math.random() * math.pi * 2,
			Children = children })
	end
end
local center = circle:GetPivot().Position

local RANGE = 260
RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - center).Magnitude > RANGE then
		return
	end
	local t = os.clock()
	for _, it in ipairs(items) do
		local cf
		if it.Orbit then
			-- Orbite lente autour du cercle, avec un léger flottement.
			local rel = it.Base.Position - Vector3.new(center.X, it.Base.Position.Y, center.Z)
			local angle = t * 0.08
			local rotated = CFrame.Angles(0, angle, 0):VectorToWorldSpace(rel)
			local pos = Vector3.new(center.X, it.Base.Position.Y, center.Z) + rotated + Vector3.new(0, math.sin(t * 0.9 + it.Phase) * 0.8, 0)
			cf = CFrame.new(pos) * it.Base.Rotation * CFrame.Angles(0, t * 0.4 + it.Phase, 0)
		else
			cf = it.Base * CFrame.new(0, math.sin(t * 1.2 + it.Phase) * 0.5, 0) * CFrame.Angles(0, t * 0.8, 0)
		end
		it.Part.CFrame = cf
		for _, child in ipairs(it.Children) do
			child.Part.CFrame = cf * child.Offset
		end
	end
end)
