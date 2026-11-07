-- Animation de l'Autel Arcane importé (World.Arena.AutelModel), jouée côté
-- client pour rester fluide : cristal et boosters qui flottent et tournent,
-- éclats, anneaux et runes en rotation, lumière pulsée.
local RunService = game:GetService("RunService")

local PERIODE = 8 -- secondes pour un tour complet

local world = workspace:WaitForChild("World", 300)
local arena = world and world:WaitForChild("Arena", 120)
if not arena or not arena:GetAttribute("CustomAltar") then
	return
end
local autel = arena:WaitForChild("AutelModel", 60)
if not autel then
	return
end

-- Les pièces arrivent du serveur peu à peu : on les attend un instant.
local function trouver(nom: string): Instance?
	return autel:FindFirstChild(nom, true) or autel:WaitForChild(nom, 10)
end

-- Pièces lumineuses en néon.
for _, p in ipairs(autel:GetDescendants()) do
	if p:IsA("BasePart") and (p.Name == "cristal" or p.Name == "anneau_a" or p.Name == "anneau_b" or p.Name == "lueur" or p.Name:match("^eclat_")) then
		p.Material = Enum.Material.Neon
	end
	if p:IsA("BasePart") and (p.Name == "anneau_a" or p.Name == "anneau_b") then
		p.LocalTransparencyModifier = 1
	end
end

-- Lumière pulsée dans le cristal.
local cristal = trouver("cristal")
local lumiere: PointLight? = nil
if cristal and cristal:IsA("BasePart") then
	lumiere = Instance.new("PointLight")
	lumiere.Color = Color3.fromRGB(111, 220, 255)
	lumiere.Range = 24
	lumiere.Parent = cristal
end

local function setPivot(o: Instance, cf: CFrame)
	if o:IsA("Model") then
		o:PivotTo(cf)
	elseif o:IsA("BasePart") then
		o.CFrame = cf
	end
end

-- { nom, vitesse de rotation (tours/période), axe "monde" ou "local", amplitude flottement, fréquence flottement }
local config = {
	{ "cristal", 1, "monde", 0.18, 2 },
	{ "eclats", -1, "monde", 0, 0 },
	{ "boosters", 1, "monde", 0.25, 3 },
	{ "runes_air", -0.5, "monde", 0, 0 },
	{ "runes_sol", 0.25, "monde", 0, 0 },
	{ "runes_sol_decal", 0.25, "monde", 0, 0 },
	{ "anneau_a", 1, "local", 0, 0 },
	{ "anneau_b", -1, "local", 0, 0 },
}

-- Le modèle est agrandi pour l'arène : le flottement suit la même échelle.
local scale = autel:GetScale()
local pieces = {}
for _, c in ipairs(config) do
	local o = trouver(c[1])
	if o and (o:IsA("Model") or o:IsA("BasePart")) then
		local base = if o:IsA("Model") then o:GetPivot() else (o :: BasePart).CFrame
		table.insert(pieces, { obj = o, base = base, vit = c[2], axe = c[3], amp = c[4] * scale, freq = c[5] })
	else
		warn("Autel : pièce introuvable → " .. c[1])
	end
end

local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	local w = (t / PERIODE) * math.pi * 2
	for _, p in ipairs(pieces) do
		local a = w * p.vit
		local dy = p.amp * math.sin(w * p.freq)
		local cf
		if p.axe == "monde" then
			cf = CFrame.new(p.base.Position + Vector3.new(0, dy, 0)) * CFrame.Angles(0, a, 0) * p.base.Rotation
		else
			cf = p.base * CFrame.Angles(0, 0, a)
		end
		setPivot(p.obj, cf)
	end
	if lumiere then
		lumiere.Brightness = 2 + 0.8 * math.sin(t * 2)
	end
end)
