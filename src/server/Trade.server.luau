-- Échange de cartes et de gemmes entre deux joueurs du même serveur.
--
-- Lieu : « Le Comptoir des Échanges », sur la Grand-Place : trois tables,
-- chacune avec deux cercles face à face. Deux joueurs sur les deux cercles
-- d'une même table = l'échange s'ouvre. Quitter son cercle l'annule.
--
-- Déroulé : chacun compose son offre → « Prêt » des deux côtés (les offres se
-- verrouillent, compte à rebours) → « Confirmer » des deux côtés → échange.
--
-- Protection contre les arnaques :
--   • toute modification d'une offre annule le « Prêt » et la confirmation
--     des deux joueurs (impossible de changer l'offre au dernier moment) ;
--   • compte à rebours obligatoire entre le verrouillage et la confirmation ;
--   • au moment de l'échange, le serveur revérifie que chacun possède encore
--     ce qu'il donne, puis applique tout d'un bloc et sauvegarde aussitôt ;
--   • l'échange est annulé si un joueur part, s'éloigne ou lance un duel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local DuelCombat = require(script.Parent:WaitForChild("DuelCombat"))
local RateLimit = require(script.Parent:WaitForChild("RateLimit"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TradeAction: RemoteFunction = Remotes:WaitForChild("TradeAction")
local TradeEvent: RemoteEvent = Remotes:WaitForChild("TradeEvent")

local LOCK_COUNTDOWN = 3
local PAD_RADIUS = 2.8 -- distance au centre du cercle pour « être dessus »
local LEAVE_RADIUS = 5 -- au-delà, on a quitté la table
local ZONE_CENTER = Vector2.new(-70, 182) -- Grand-Place, côté ouest
local MAX_STACKS = 8
local MAX_GEMS = 100000
local LOG_SIZE = 20

type Offer = { Cards: { [string]: number }, Gems: number }
type Session = {
	A: Player, B: Player,
	Offers: { [Player]: Offer },
	Ready: { [Player]: boolean },
	Confirmed: { [Player]: boolean },
	Stage: string, -- "Edit" | "Locked" | "Done"
	LockedAt: number,
	Version: number,
}

local sessions: { [Player]: Session } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function partnerOf(s: Session, p: Player): Player
	return s.A == p and s.B or s.A
end

local function copyOffer(o: Offer)
	local cards = {}
	for id, n in pairs(o.Cards) do
		cards[id] = n
	end
	return { Cards = cards, Gems = o.Gems }
end

-- État envoyé à chacun, de son point de vue.
local function push(s: Session)
	for _, p in ipairs({ s.A, s.B }) do
		local other = partnerOf(s, p)
		local left = s.Stage == "Locked" and math.max(0, LOCK_COUNTDOWN - (os.clock() - s.LockedAt)) or 0
		TradeEvent:FireClient(p, "State", {
			Stage = s.Stage,
			Version = s.Version,
			Countdown = left,
			Partner = { Name = other.DisplayName, UserId = other.UserId },
			Mine = copyOffer(s.Offers[p]),
			Theirs = copyOffer(s.Offers[other]),
			MyReady = s.Ready[p] == true,
			TheirReady = s.Ready[other] == true,
			MyConfirm = s.Confirmed[p] == true,
			TheirConfirm = s.Confirmed[other] == true,
		})
	end
end

local function close(s: Session, reason: string)
	if s.Stage == "Done" then
		return
	end
	s.Stage = "Done"
	for _, p in ipairs({ s.A, s.B }) do
		sessions[p] = nil
		if p.Parent then
			TradeEvent:FireClient(p, "Closed", { Reason = reason })
		end
	end
end

-- Une offre a changé : plus personne n'est prêt ni n'a confirmé.
local function unlock(s: Session)
	s.Stage = "Edit"
	s.Ready = {}
	s.Confirmed = {}
	s.Version += 1
end

local function stackCount(o: Offer): number
	local n = 0
	for _ in pairs(o.Cards) do
		n += 1
	end
	return n
end

local function owns(profile, o: Offer): boolean
	if profile.Coins < o.Gems then
		return false
	end
	for id, n in pairs(o.Cards) do
		if (profile.Cards[id] or 0) < n then
			return false
		end
	end
	return true
end

local function describe(o: Offer): string
	local parts = {}
	for id, n in pairs(o.Cards) do
		local card = CardsData.CardById[id]
		table.insert(parts, (card and card.Name or id) .. (n > 1 and (" ×" .. n) or ""))
	end
	if o.Gems > 0 then
		table.insert(parts, o.Gems .. " gemmes")
	end
	return #parts > 0 and table.concat(parts, ", ") or "rien"
end

local function log(profile, entry)
	profile.TradeLog = profile.TradeLog or {}
	table.insert(profile.TradeLog, entry)
	while #profile.TradeLog > LOG_SIZE do
		table.remove(profile.TradeLog, 1)
	end
end

local function execute(s: Session)
	local pa, pb = DataService.Get(s.A), DataService.Get(s.B)
	local oa, ob = s.Offers[s.A], s.Offers[s.B]
	if not (pa and pb) then
		close(s, "Profil indisponible : échange annulé.")
		return
	end
	if not owns(pa, oa) or not owns(pb, ob) then
		close(s, "Un des joueurs ne possède plus ce qu'il proposait : échange annulé.")
		return
	end
	-- Tout d'un bloc (aucune attente entre les deux côtés).
	local function give(from, to, o: Offer)
		from.Coins -= o.Gems
		to.Coins += o.Gems
		for id, n in pairs(o.Cards) do
			from.Cards[id] -= n
			if from.Cards[id] <= 0 then
				from.Cards[id] = nil
			end
			to.Cards[id] = (to.Cards[id] or 0) + n
		end
	end
	give(pa, pb, oa)
	give(pb, pa, ob)
	local now = os.time()
	log(pa, { Time = now, With = s.B.UserId, Gave = copyOffer(oa), Got = copyOffer(ob) })
	log(pb, { Time = now, With = s.A.UserId, Gave = copyOffer(ob), Got = copyOffer(oa) })
	print(string.format("[Trade] %s (%d) ⇄ %s (%d) : %s ⇄ %s", s.A.Name, s.A.UserId, s.B.Name, s.B.UserId, describe(oa), describe(ob)))
	s.Stage = "Done"
	for _, p in ipairs({ s.A, s.B }) do
		sessions[p] = nil
		DataService.MarkChanged(p)
		task.spawn(DataService.SaveNow, p)
		local other = partnerOf(s, p)
		TradeEvent:FireClient(p, "Done", { Got = copyOffer(s.Offers[other]), Gave = copyOffer(s.Offers[p]), Partner = other.DisplayName })
	end
end

local handlers = {}

-- Ouvre l'échange entre les deux joueurs installés à une table.
local function startSession(a: Player, b: Player, tableIndex: number)
	local s: Session = {
		A = a, B = b,
		Offers = { [a] = { Cards = {}, Gems = 0 }, [b] = { Cards = {}, Gems = 0 } },
		Ready = {}, Confirmed = {}, Stage = "Edit", LockedAt = 0, Version = 1,
	}
	;(s :: any).Table = tableIndex
	sessions[a], sessions[b] = s, s
	push(s)
end

function handlers.SetCard(player: Player, data)
	local s = sessions[player]
	local profile = DataService.Get(player)
	if not (s and profile) or type(data) ~= "table" or type(data.Id) ~= "string" or type(data.Count) ~= "number" then
		return { ok = false }
	end
	if not CardsData.CardById[data.Id] then
		return { ok = false }
	end
	local count = math.floor(data.Count)
	local owned = profile.Cards[data.Id] or 0
	if count < 0 or count > owned then
		return { ok = false, reason = "Tu n'as pas assez d'exemplaires." }
	end
	local offer = s.Offers[player]
	if count > 0 and not offer.Cards[data.Id] and stackCount(offer) >= MAX_STACKS then
		return { ok = false, reason = "Maximum " .. MAX_STACKS .. " créatures différentes par échange." }
	end
	offer.Cards[data.Id] = count > 0 and count or nil
	unlock(s)
	push(s)
	return { ok = true }
end

function handlers.SetGems(player: Player, amount)
	local s = sessions[player]
	local profile = DataService.Get(player)
	if not (s and profile) or type(amount) ~= "number" then
		return { ok = false }
	end
	local gems = math.clamp(math.floor(amount), 0, math.min(profile.Coins, MAX_GEMS))
	s.Offers[player].Gems = gems
	unlock(s)
	push(s)
	return { ok = true }
end

function handlers.Ready(player: Player, value)
	local s = sessions[player]
	if not s then
		return { ok = false }
	end
	if value then
		s.Ready[player] = true
		if s.Ready[s.A] and s.Ready[s.B] then
			s.Stage = "Locked"
			s.LockedAt = os.clock()
			s.Confirmed = {}
			-- Rafraîchit le compte à rebours une fois terminé.
			local version = s.Version
			task.delay(LOCK_COUNTDOWN + 0.05, function()
				if s.Stage == "Locked" and s.Version == version then
					push(s)
				end
			end)
		end
	else
		s.Ready[player] = nil
		s.Confirmed = {}
		s.Stage = "Edit"
	end
	push(s)
	return { ok = true }
end

function handlers.Confirm(player: Player)
	local s = sessions[player]
	if not s or s.Stage ~= "Locked" then
		return { ok = false, reason = "Les deux joueurs doivent d'abord être prêts." }
	end
	if os.clock() - s.LockedAt < LOCK_COUNTDOWN then
		return { ok = false, reason = "Vérifie bien l'offre avant de confirmer..." }
	end
	s.Confirmed[player] = true
	if s.Confirmed[s.A] and s.Confirmed[s.B] then
		execute(s)
	else
		push(s)
	end
	return { ok = true }
end

function handlers.Cancel(player: Player)
	local s = sessions[player]
	if s then
		close(s, player.DisplayName .. " a annulé l'échange.")
	end
	return { ok = true }
end

TradeAction.OnServerInvoke = function(player, kind, arg)
	if type(kind) ~= "string" or not handlers[kind] or not RateLimit.safeArg(arg) then
		return { ok = false }
	end
	if not RateLimit.allow(player, "Trade", 5, 10) then
		return { ok = false, reason = "Doucement !" }
	end
	local ok, result = pcall(handlers[kind], player, arg)
	if not ok then
		warn("[Trade] " .. kind .. " :", result)
		return { ok = false, reason = "Une erreur est survenue." }
	end
	return result
end

-------------------------------------------------------------------------------
-- Le Comptoir des Échanges : trois tables, deux cercles chacune.
-------------------------------------------------------------------------------
local zone = Instance.new("Model")
zone.Name = "ComptoirDesEchanges"
local function part(props): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end
local function deco(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end
local GOLD = Color3.fromRGB(220, 175, 80)
local ARCANE = Color3.fromRGB(150, 110, 255)
local tables = {}

local function groundAt(x: number, z: number): number
	local hit = workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -120, 0))
	return hit and hit.Position.Y or 0
end

local function buildZone()
	local y = groundAt(ZONE_CENTER.X, ZONE_CENTER.Y)
	local base = Vector3.new(ZONE_CENTER.X, y, ZONE_CENTER.Y)
	-- Dallage commun et arche d'enseigne.
	part({ Name = "Dallage", Size = Vector3.new(48, 0.3, 20), CFrame = CFrame.new(base + Vector3.new(0, 0.15, 0)), Material = Enum.Material.Slate,
		Color = Color3.fromRGB(150, 140, 155), Parent = zone })
	for _, x in ipairs({ -23, 23 }) do
		part({ Name = "Pilier", Size = Vector3.new(1.4, 12, 1.4), CFrame = CFrame.new(base + Vector3.new(x, 6, -9)), Material = Enum.Material.Limestone,
			Color = Color3.fromRGB(200, 190, 175), Parent = zone })
	end
	local arch = deco(part({ Name = "Enseigne", Size = Vector3.new(48, 2.2, 0.6), CFrame = CFrame.new(base + Vector3.new(0, 12.4, -9)), Material = Enum.Material.Wood,
		Color = Color3.fromRGB(70, 45, 28), Parent = zone }))
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.Parent = arch
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "LE COMPTOIR DES ÉCHANGES"
		label.TextScaled = true
		label.Font = Enum.Font.Fantasy
		label.TextColor3 = Color3.fromRGB(255, 215, 130)
		label.Parent = gui
	end
	for i, x in ipairs({ -15, 0, 15 }) do
		local c = base + Vector3.new(x, 0, 0)
		-- Table ronde en bois, plateau doré, cristal flottant au-dessus.
		part({ Name = "Pied", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 1.2, 1.2), CFrame = CFrame.new(c + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 75, 45), Parent = zone })
		part({ Name = "Plateau", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 5, 5), CFrame = CFrame.new(c + Vector3.new(0, 3.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(150, 105, 65), Parent = zone })
		deco(part({ Name = "Lisere", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, 5.2, 5.2), CFrame = CFrame.new(c + Vector3.new(0, 3.38, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Metal, Color = GOLD, Parent = zone }))
		local crystal = deco(part({ Name = "Cristal", Size = Vector3.new(0.9, 1.6, 0.9), CFrame = CFrame.new(c + Vector3.new(0, 5.6, 0)) * CFrame.Angles(0, math.rad(45), 0),
			Material = Enum.Material.Neon, Color = ARCANE, Transparency = 0.2, Parent = zone }))
		local light = Instance.new("PointLight")
		light.Color = ARCANE
		light.Range = 12
		light.Brightness = 1.2
		light.Parent = crystal
		-- Numéro de la table.
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(120, 30)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
		tag.MaxDistance = 60
		tag.Adornee = crystal
		tag.Parent = crystal
		local tl = Instance.new("TextLabel")
		tl.BackgroundTransparency = 1
		tl.Size = UDim2.fromScale(1, 1)
		tl.Text = "Table " .. i
		tl.TextScaled = true
		tl.Font = Enum.Font.GothamBold
		tl.TextColor3 = Color3.fromRGB(255, 215, 130)
		tl.TextStrokeTransparency = 0.4
		tl.Parent = tag
		-- Deux cercles face à face.
		local pads = {}
		for _, dz in ipairs({ -5, 5 }) do
			local pos = c + Vector3.new(0, 0.32, dz)
			local pad = deco(part({ Name = "Cercle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 4.4, 4.4),
				CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Neon, Color = ARCANE, Transparency = 0.35, Parent = zone }))
			deco(part({ Name = "Creux", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.09, 3.6, 3.6),
				CFrame = CFrame.new(pos + Vector3.new(0, 0.005, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Slate,
				Color = Color3.fromRGB(150, 140, 155), Parent = zone }))
			table.insert(pads, { Part = pad, Pos = pos })
		end
		tables[i] = { Pads = pads, Center = c }
	end
	zone.Parent = workspace:WaitForChild("World")
end

local function onPad(player: Player, pad, radius: number): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	local d = root.Position - pad.Pos
	return Vector2.new(d.X, d.Z).Magnitude < radius and math.abs(d.Y) < 8
end

local waitingNotified: { [Player]: number } = {}

task.spawn(function()
	while not workspace:GetAttribute("VillageReady") do
		task.wait(1)
	end
	buildZone()
	while true do
		task.wait(0.4)
		for i, t in ipairs(tables) do
			local occupants = {}
			for k, pad in ipairs(t.Pads) do
				for _, p in ipairs(Players:GetPlayers()) do
					if onPad(p, pad, PAD_RADIUS) then
						occupants[k] = p
						break
					end
				end
				-- Cercle vert quand il est occupé.
				pad.Part.Color = occupants[k] and Color3.fromRGB(110, 230, 150) or ARCANE
			end
			local a, b = occupants[1], occupants[2]
			if a and b and a ~= b and not sessions[a] and not sessions[b] then
				if not (DuelCombat.isFighting(a) or DuelCombat.isFighting(b)) and DataService.Get(a) and DataService.Get(b) then
					startSession(a, b, i)
				end
			elseif (a or b) and not (a and b) then
				-- Seul à la table : petit message, pas plus d'une fois toutes les 20 s.
				local p = a or b
				if not sessions[p] and os.clock() - (waitingNotified[p] or 0) > 20 then
					waitingNotified[p] = os.clock()
					TradeEvent:FireClient(p, "Waiting", { Table = i })
				end
			end
		end
	end
end)

-- Surveillance : départ, sortie de la table, duel.
Players.PlayerRemoving:Connect(function(player)
	local s = sessions[player]
	if s then
		close(s, player.DisplayName .. " a quitté la partie.")
	end
	waitingNotified[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(1)
		local seen = {}
		for _, s in pairs(sessions) do
			if not seen[s] then
				seen[s] = true
				local t = tables[(s :: any).Table]
				local stillA = t and (onPad(s.A, t.Pads[1], LEAVE_RADIUS) or onPad(s.A, t.Pads[2], LEAVE_RADIUS))
				local stillB = t and (onPad(s.B, t.Pads[1], LEAVE_RADIUS) or onPad(s.B, t.Pads[2], LEAVE_RADIUS))
				if not (stillA and stillB) then
					close(s, (stillA and s.B or s.A).DisplayName .. " a quitté la table : échange annulé.")
				elseif DuelCombat.isFighting(s.A) or DuelCombat.isFighting(s.B) then
					close(s, "Un duel a commencé : échange annulé.")
				end
			end
		end
	end
end)
