-- Profils joueurs persistants (DataStore), avec repli en mémoire si l'API
-- n'est pas disponible (Studio sans "Enable Studio Access to API Services").
--
-- Fiabilité :
--   • verrou de session : un profil n'est ouvert que par un serveur à la fois
--     (sinon deux serveurs pourraient sauvegarder chacun leur version et
--     dupliquer cartes ou gemmes, par exemple autour d'un échange) ;
--   • UpdateAsync partout, avec plusieurs essais en cas d'échec ;
--   • sauvegarde automatique des profils modifiés, sauvegarde immédiate
--     possible (achats, échanges), libération du verrou au départ ;
--   • on n'écrase jamais une sauvegarde qu'on n'a pas réussi à lire.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
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
	TradeLog: { any },
	DailyDuelDay: number,
	StallDay: number,
	StallBought: { [string]: boolean },
	SetsClaimed: { [string]: boolean },
	FarmDay: number,
}

local DataService = {}

local STORE_NAME = "ArcanaBestia_Profiles_v1"
local FORMAT_VERSION = 2
local AUTOSAVE_INTERVAL = 60
local LOCK_TTL = 300 -- un verrou plus vieux que ça est considéré abandonné
local LOAD_TRIES = 6
local SAVE_TRIES = 3
local MAX_COINS = 10_000_000
local MAX_COPIES = 9999

-- Identifiant de ce serveur (JobId vide dans Studio).
local SESSION = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))

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
local dirty: { [Player]: boolean } = {}
local saving: { [Player]: boolean } = {}
local changedEvent = Instance.new("BindableEvent")
DataService.Changed = changedEvent.Event

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local studioApiWarningShown = false
local function studioBlocked(err: any): boolean
	local text = tostring(err)
	if RunService:IsStudio() and (string.find(text, "StudioAccessToApisNotAllowed", 1, true) or string.find(text, "API access is not enabled", 1, true)) then
		if not studioApiWarningShown then
			warn("[DataService] Accès DataStore désactivé dans Studio ; profils conservés en mémoire.")
			studioApiWarningShown = true
		end
		return true
	end
	return false
end

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
		TradeLog = {},
		DailyDuelDay = 0,
		StallDay = 0,
		StallBought = {},
		SetsClaimed = {},
		FarmDay = 0,
	}
end

-- Valeurs saines : types attendus, cartes existantes, bornes.
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
	local cards = {}
	for id, count in pairs(profile.Cards) do
		if CardsData.CardById[id] and type(count) == "number" and count >= 1 then
			cards[id] = math.min(MAX_COPIES, math.floor(count))
		end
	end
	profile.Cards = cards
	profile.Coins = math.clamp(math.floor(profile.Coins), 0, MAX_COINS)
	return profile
end

-- Ancien format : le profil directement ; nouveau : { Version, Profile, Lock }.
local function unwrap(stored: any): (any, any)
	if type(stored) ~= "table" then
		return nil, nil
	end
	if stored.Version and type(stored.Profile) == "table" then
		return stored.Profile, stored.Lock
	end
	return stored, nil
end

local function lockFree(lock: any): boolean
	return type(lock) ~= "table" or lock.Session == SESSION or os.time() - (tonumber(lock.Time) or 0) > LOCK_TTL
end

function DataService.Load(player: Player)
	local data = nil
	local loaded = store == nil
	if store then
		for attempt = 1, LOAD_TRIES do
			local busy = false
			local ok, err = pcall(function()
				store:UpdateAsync(keyFor(player), function(stored)
					local profile, lock = unwrap(stored)
					-- Profil ouvert par un autre serveur : on attend (sauf au dernier essai,
					-- où le verrou est repris pour ne pas bloquer le joueur indéfiniment).
					if not lockFree(lock) and attempt < LOAD_TRIES then
						busy = true
						return nil
					end
					data = profile
					return { Version = FORMAT_VERSION, Profile = profile or defaultProfile(), Lock = { Session = SESSION, Time = os.time() } }
				end)
			end)
			if ok and not busy then
				loaded = true
				break
			end
			if not ok and studioBlocked(err) then
				loaded = true
				break
			end
			if not ok then
				warn("[DataService] Échec du chargement (essai " .. attempt .. ") :", err)
			end
			if player.Parent == nil then
				return
			end
			task.wait(busy and 5 or attempt)
		end
	end
	if player.Parent == nil then
		return
	end
	profiles[player] = reconcile(data)
	-- Ne jamais écraser une sauvegarde qu'on n'a pas réussi à lire.
	canSave[player] = store ~= nil and loaded
	if store and not loaded then
		warn("[DataService] Profil de " .. player.Name .. " non chargé : la progression de cette session ne sera pas sauvegardée.")
	end
	changedEvent:Fire(player)
end

-- Sauvegarde ; release = libère le verrou (départ du joueur).
-- Renvoie true si la sauvegarde a réussi.
function DataService.Save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not (store and profile and canSave[player]) then
		return store == nil -- pas de DataStore : rien à faire, ce n'est pas un échec
	end
	-- Une seule sauvegarde à la fois par joueur.
	while saving[player] do
		task.wait(0.1)
	end
	saving[player] = true
	dirty[player] = nil
	local stolen = false
	local success = false
	for attempt = 1, SAVE_TRIES do
		local ok, err = pcall(function()
			store:UpdateAsync(keyFor(player), function(stored)
				local _, lock = unwrap(stored)
				if type(lock) == "table" and lock.Session ~= SESSION and os.time() - (tonumber(lock.Time) or 0) <= LOCK_TTL then
					-- Un autre serveur a repris ce profil : on n'écrit surtout pas.
					stolen = true
					return nil
				end
				return { Version = FORMAT_VERSION, Profile = profile, Lock = (not release) and { Session = SESSION, Time = os.time() } or nil }
			end)
		end)
		if ok then
			success = not stolen
			break
		end
		if studioBlocked(err) then
			break
		end
		warn("[DataService] Échec de la sauvegarde (essai " .. attempt .. ") :", err)
		task.wait(attempt)
	end
	saving[player] = nil
	if stolen then
		canSave[player] = false
		warn("[DataService] Profil de " .. player.Name .. " ouvert sur un autre serveur : sauvegarde bloquée.")
		if player.Parent then
			player:Kick("Ta partie est ouverte sur un autre serveur. Reconnecte-toi.")
		end
	elseif not success then
		dirty[player] = true
	end
	return success
end

-- Sauvegarde tout de suite (achat, échange) ; renvoie true si c'est fait.
function DataService.SaveNow(player: Player): boolean
	return DataService.Save(player)
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
	local profile = profiles[player]
	if profile then
		profile.Coins = math.clamp(math.floor(profile.Coins), 0, MAX_COINS)
	end
	dirty[player] = true
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
	DataService.Save(player, true)
	profiles[player] = nil
	canSave[player] = nil
	dirty[player] = nil
end)

-- Sauvegarde automatique des profils modifiés (et rafraîchissement du verrou).
task.spawn(function()
	local beats = 0
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		beats += 1
		for player in pairs(profiles) do
			-- Toutes les 2 minutes au moins, même sans changement, pour garder le verrou.
			if dirty[player] or beats % 2 == 0 then
				task.spawn(DataService.Save, player)
			end
		end
	end
end)

game:BindToClose(function()
	local pending = 0
	for player in pairs(profiles) do
		pending += 1
		task.spawn(function()
			DataService.Save(player, true)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

return DataService
