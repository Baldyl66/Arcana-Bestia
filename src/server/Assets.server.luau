-- Rend visibles par les joueurs les modèles 3D importés dans ServerStorage
-- qui sont affichés côté client (booster, Anima), avec leurs animations importées.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CLIENT_MODELS = { "BoosterModel" }

-- Séquences d'animation importées pour un modèle : on repère celle qui porte
-- un nom propre à ce modèle, et on prend toutes ses voisines (même import).
local SIGNATURES = { BoosterModel = "Ouverture" }

local function copySequences(name: string, target: Model)
	local saves = ServerStorage:FindFirstChild("RBX_ANIMSAVES")
	local signature = SIGNATURES[name]
	if not (saves and signature) then
		return
	end
	for _, d in ipairs(saves:GetDescendants()) do
		if d:IsA("KeyframeSequence") and string.find(d.Name, signature, 1, true) and d.Parent then
			for _, sibling in ipairs(d.Parent:GetChildren()) do
				if sibling:IsA("KeyframeSequence") then
					sibling:Clone().Parent = target
				end
			end
			return
		end
	end
end

local function hasSequences(model: Instance): boolean
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("KeyframeSequence") then
			return true
		end
	end
	return false
end

for _, name in ipairs(CLIENT_MODELS) do
	-- Le modèle peut être rangé dans ServerStorage (on le recopie) ou déjà
	-- dans ReplicatedStorage : dans les deux cas on y joint ses animations.
	local target = ReplicatedStorage:FindFirstChild(name)
	if not target then
		local source = ServerStorage:FindFirstChild(name)
		if source then
			target = source:Clone()
			target.Parent = ReplicatedStorage
		end
	end
	if target and target:IsA("Model") and not hasSequences(target) then
		copySequences(name, target)
	end
	if target then
		local names = {}
		for _, d in ipairs(target:GetDescendants()) do
			if d:IsA("KeyframeSequence") then
				table.insert(names, d.Name)
			end
		end
		print(string.format("[Assets] %s : %d animation(s) jointe(s) %s", name, #names, table.concat(names, ", ")))
	end
end

-- Anima 3D (modèles Claude Design, ex. « flamichat ») : rangés dans ReplicatedStorage.Animas
-- ou ServerStorage.Animas. Leurs clips s'appellent « <id>_<Clip> » (flamichat_Repos…) :
-- l'import de Studio les met dans RBX_ANIMSAVES, côté serveur, on les joint au modèle
-- pour que Arena3D (client) puisse les jouer.
local function copyAnimaSequences(target: Model)
	local saves = ServerStorage:FindFirstChild("RBX_ANIMSAVES")
	if not saves then
		return
	end
	local prefix = string.lower(target.Name) .. "_"
	for _, d in ipairs(saves:GetDescendants()) do
		if d:IsA("KeyframeSequence") and string.find(string.lower(d.Name), prefix, 1, true) then
			d:Clone().Parent = target
		end
	end
end

local animas = ReplicatedStorage:FindFirstChild("Animas")
local serverAnimas = ServerStorage:FindFirstChild("Animas")
if serverAnimas then
	if not animas then
		animas = Instance.new("Folder")
		animas.Name = "Animas"
		animas.Parent = ReplicatedStorage
	end
	for _, m in ipairs(serverAnimas:GetChildren()) do
		if not animas:FindFirstChild(m.Name) then
			m:Clone().Parent = animas
		end
	end
end
for _, m in ipairs(animas and animas:GetChildren() or {}) do
	if m:IsA("Model") then
		if not hasSequences(m) then
			copyAnimaSequences(m)
		end
		local names = {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("KeyframeSequence") then
				table.insert(names, d.Name)
			end
		end
		print(string.format("[Assets] Anima %s : %d animation(s) %s", m.Name, #names, table.concat(names, ", ")))
	end
end
