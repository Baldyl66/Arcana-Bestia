-- Profils joueurs persistants (DataStore), avec repli en mémoire si l'API
-- n'est pas disponible (Studio sans "Enable Studio Access to API Services").
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local VillageData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("VillageData"))

export type Profile = {
	Coins: number,
	Cards: { [string]: number },
	LastDaily: number,
	BoostersOpened: number,
	Quests: { [string]: boolean },
	Visited: { [string]: boolean },
	Talked: { [string]: boolean },
	Treasures: number,
	TutorialSeen: boolean,
	LoginStreak: number,
	LastClaimDay: number,
	Receipts: { string },
	StarterBought: boolean,
}

local DataService = {}

local STORE_NAME = "ArcanaBestia_Profiles_v1"
local AUTOSAVE_INTERVAL = 120

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore indisponible, sauvegarde désactivée :", result)
	end
end

local profiles: { [Player]: Profile } = {}
local canSave: { [Player]: boolean } = {}
local changedEvent = Instance.new("BindableEvent")
DataService.Changed = changedEvent.Event

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local studioApiWarningShown = false

local function defaultProfile(): Profile
	return {
		Coins = CardsData.Economy.StartingCoins,
		Cards = {},
		LastDaily = 0,
		BoostersOpened = 0,
		Quests = {},
		Visited = {},
		Talked = {},
		Treasures = 0,
		TutorialSeen = false,
		LoginStreak = 0,
		LastClaimDay = 0,
		Receipts = {},
		StarterBought = false,
	}
end

local function reconcile(data: any): Profile
	local profile = defaultProfile()
	if type(data) ~= "table" then
		return profile
	end
	for key, value in pairs(profile) do
		if type(data[key]) == type(value) then
			profile[key] = data[key]
		end
	end
	-- Ignore les cartes qui n'existent plus dans la configuration.
	local cards = {}
	for id, count in pairs(profile.Cards) do
		if CardsData.CardById[id] and type(count) == "number" and count > 0 then
			cards[id] = math.floor(count)
		end
	end
	profile.Cards = cards
	return profile
end

function DataService.Load(player: Player)
	local data = nil
	local loaded = store == nil
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(store.GetAsync, store, keyFor(player))
			if ok then
				data = result
				loaded = true
				break
			end
			local errorText = tostring(result)
			if RunService:IsStudio() and string.find(errorText, "StudioAccessToApisNotAllowed", 1, true) then
				if not studioApiWarningShown then
					warn("[DataService] Accès DataStore désactivé dans Studio ; profils conservés en mémoire.")
					studioApiWarningShown = true
				end
				loaded = true
				break
			end
			warn("[DataService] Échec du chargement (essai " .. attempt .. ") :", errorText)
			task.wait(attempt)
		end
	end
	if player.Parent == nil then
		return
	end
	profiles[player] = reconcile(data)
	-- Ne jamais écraser une sauvegarde qu'on n'a pas réussi à lire.
	canSave[player] = store ~= nil and loaded
	changedEvent:Fire(player)
end

function DataService.Save(player: Player)
	local profile = profiles[player]
	if not (store and profile and canSave[player]) then
		return
	end
	local ok, err = pcall(store.SetAsync, store, keyFor(player), profile)
	if not ok then
		warn("[DataService] Échec de la sauvegarde :", err)
	end
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

function DataService.WaitFor(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 15)
	while profiles[player] == nil and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.MarkChanged(player: Player)
	changedEvent:Fire(player)
end

-- Numéro du jour (UTC) utilisé pour les récompenses de connexion.
function DataService.Today(): number
	return math.floor(os.time() / 86400)
end

function DataService.Snapshot(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return nil
	end
	local cards = {}
	for id, count in pairs(profile.Cards) do
		cards[id] = count
	end
	local today = DataService.Today()
	local continues = profile.LastClaimDay == today - 1
	local nextDay = continues and (profile.LoginStreak % #CardsData.Economy.DailyRewards) + 1 or 1
	return {
		Coins = profile.Coins,
		Cards = cards,
		BoostersOpened = profile.BoostersOpened,
		DailyAvailable = profile.LastClaimDay < today,
		DailyStreak = (continues or profile.LastClaimDay == today) and profile.LoginStreak or 0,
		DailyNext = profile.LastClaimDay == today and (profile.LoginStreak % #CardsData.Economy.DailyRewards) + 1 or nextDay,
		QuestsReady = VillageData.readyCount(profile),
		TutorialSeen = profile.TutorialSeen,
		StarterBought = profile.StarterBought,
	}
end

Players.PlayerAdded:Connect(DataService.Load)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(DataService.Load, player)
end

Players.PlayerRemoving:Connect(function(player)
	DataService.Save(player)
	profiles[player] = nil
	canSave[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for player in pairs(profiles) do
			task.spawn(DataService.Save, player)
		end
	end
end)

game:BindToClose(function()
	local pending = 0
	for player in pairs(profiles) do
		pending += 1
		task.spawn(function()
			DataService.Save(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

return DataService
