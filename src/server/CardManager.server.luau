local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local OpenBooster: RemoteFunction = Remotes:WaitForChild("OpenBooster")
local GetProfile: RemoteFunction = Remotes:WaitForChild("GetProfile")
local ClaimDaily: RemoteFunction = Remotes:WaitForChild("ClaimDaily")
local ProfileChanged: RemoteEvent = Remotes:WaitForChild("ProfileChanged")

local Economy = CardsData.Economy
local OPEN_COOLDOWN = 0.75

local CardService = require(script.Parent:WaitForChild("CardService"))
local lastOpenAt: { [Player]: number } = {}

GetProfile.OnServerInvoke = function(player)
	DataService.WaitFor(player)
	return DataService.Snapshot(player)
end

OpenBooster.OnServerInvoke = function(player)
	local profile = DataService.Get(player)
	if profile == nil then
		return { ok = false, reason = "Profil en cours de chargement..." }
	end

	local now = os.clock()
	if now - (lastOpenAt[player] or 0) < OPEN_COOLDOWN then
		return { ok = false, reason = "Doucement !" }
	end
	if profile.Coins < Economy.BoosterPrice then
		return { ok = false, reason = "Pas assez de gemmes !" }
	end
	lastOpenAt[player] = now

	-- Un booster contient 3 créatures (compte pour un seul booster ouvert).
	profile.Coins -= Economy.BoosterPrice
	profile.BoostersOpened += 1
	local results = {}
	for _ = 1, Economy.CardsPerBooster or 3 do
		local card = CardService.draw()
		if card then
			table.insert(results, CardService.grant(profile, card))
		end
	end
	if #results == 0 then
		return { ok = false, reason = "Erreur de tirage." }
	end
	return { ok = true, results = results, profile = DataService.Snapshot(player) }
end

ClaimDaily.OnServerInvoke = function(player)
	local profile = DataService.Get(player)
	if profile == nil then
		return { ok = false, reason = "Profil en cours de chargement..." }
	end
	local today = DataService.Today()
	if profile.LastClaimDay >= today then
		return { ok = false, reason = "Récompense déjà récupérée aujourd'hui. Reviens demain !" }
	end

	local rewards = Economy.DailyRewards
	local day = 1
	if profile.LastClaimDay == today - 1 then
		day = (profile.LoginStreak % #rewards) + 1
	end
	local reward = rewards[day]
	profile.LastClaimDay = today
	profile.LoginStreak = day

	local results = {}
	local coins = (reward.Coins or 0) * (player:GetAttribute("VIP") and 2 or 1)
	profile.Coins += coins
	-- Sac du collectionneur : un booster offert en plus chaque jour.
	if player:GetAttribute("Collector") then
		local card = CardService.draw()
		if card then
			profile.BoostersOpened += 1
			table.insert(results, CardService.grant(profile, card))
		end
	end
	if reward.Booster then
		local card = CardService.draw()
		if card then
			profile.BoostersOpened += 1
			table.insert(results, CardService.grant(profile, card))
		end
	end
	if reward.MinRarity then
		local card = CardService.draw(function(c)
			return CardsData.RarityById[c.Rarity].Order >= reward.MinRarity
		end)
		if card then
			table.insert(results, CardService.grant(profile, card))
		end
	end

	return {
		ok = true,
		day = day,
		coins = coins,
		results = results,
		profile = DataService.Snapshot(player),
	}
end

DataService.Changed:Connect(function(player)
	ProfileChanged:FireClient(player, DataService.Snapshot(player))
end)

-- Revenu passif pour récompenser le temps de jeu.
task.spawn(function()
	while true do
		task.wait(Economy.PassiveInterval)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = DataService.Get(player)
			if profile then
				profile.Coins += Economy.PassiveIncome
				DataService.MarkChanged(player)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastOpenAt[player] = nil
end)
