-- Pose « livre contre la poitrine » quand un joueur tient le Carnet.
-- Les articulations des bras (R15) sont pliées à chaque image, par-dessus
-- les animations (marche, repos) : bras droit replié qui tient le livre,
-- main gauche qui le soutient. Appliqué à tous les joueurs visibles, pour que
-- chacun voie la pose des autres (Transform n'est pas répliqué).
--
-- Pour remplacer cette pose par une vraie animation : la jouer à l'équipement
-- du Carnet et supprimer ce script.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TOOL_NAME = "Carnet"
local BLEND = 8 -- vitesse d'entrée / sortie de la pose

-- Rotations ajoutées à chaque articulation (degrés : X = vers l'avant,
-- Z = vers l'intérieur du corps, Y = torsion).
local POSE = {
	RightShoulder = { "RightUpperArm", 38, 0, -14 },
	RightElbow = { "RightLowerArm", 78, 0, 0 },
	RightWrist = { "RightHand", 0, 0, 0 },
	-- Valeurs trouvées par recherche dans Studio : la main gauche vient se
	-- placer sous le livre, devant la poitrine.
	LeftShoulder = { "LeftUpperArm", 0, 0, 30 },
	LeftElbow = { "LeftLowerArm", -60, 0, 0 },
}

local weights: { [Model]: number } = {}

local function motors(character: Model)
	local list = {}
	for name, def in pairs(POSE) do
		local part = character:FindFirstChild(def[1])
		local motor = part and part:FindFirstChild(name)
		-- Ancien rig (Motor6D) ou nouvelles articulations Roblox (AnimationConstraint).
		if motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
			local x, y, z = math.rad(def[2]), math.rad(def[3]), math.rad(def[4])
			table.insert(list, { Motor = motor, Rot = CFrame.Angles(x, y, z) })
		end
	end
	return list
end

RunService.Stepped:Connect(function(_, dt)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local holding = character:FindFirstChild(TOOL_NAME) ~= nil
			local w = weights[character] or 0
			w = math.clamp(w + (holding and dt or -dt) * BLEND, 0, 1)
			weights[character] = w > 0 and w or nil
			if w > 0 then
				local e = w * w * (3 - 2 * w)
				for _, m in ipairs(motors(character)) do
					m.Motor.Transform = m.Motor.Transform:Lerp(m.Rot, e)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		weights[player.Character] = nil
	end
end)
