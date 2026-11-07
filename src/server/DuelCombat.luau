-- Combat de cartes du Colisée, au tour par tour.
-- 1. Sélection : chaque duelliste choisit 3 créatures de sa collection
--    (choix automatique des plus puissantes si le temps s'écoule).
-- 2. Combat : les joueurs jouent chacun leur tour. Le joueur actif choisit
--    une action pour sa créature : Attaque, Garde (soigne un peu et divise
--    par deux les prochains dégâts reçus) ou Coup spécial (dégâts x1,8, une
--    fois par créature). Les affinités d'éléments multiplient les dégâts.
--    Une créature K.O. laisse sa place à la suivante ; le premier à perdre
--    toutes ses créatures perd le duel.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))

local DuelCombat = {}

local DECK_SIZE = 3
local SELECT_TIME = 30
local TURN_TIME = 15
local INTRO_TIME = 6
local RESOLVE_TIME = 2.2
-- Durée des cinématiques d'attaque côté client (+ marge).
local CINEMATIC_TIME = { Attack = 2.9, Special = 3.6 }
local MAX_TURNS = 50
local SPECIAL_POWER = 1.8
local GUARD_HEAL = 0.08
-- Élément fort contre élément (x1,5) ; l'inverse subit x0,75.
local STRONG = { Feu = "Nature", Nature = "Eau", Eau = "Feu", Foudre = "Eau", Ombre = "Lumiere", Lumiere = "Ombre" }

export type Fighter = { Id: string, HP: number, MaxHP: number, Attack: number, Element: string, SpecialUsed: boolean, Guard: boolean }

local battles: { [any]: any } = {}
local activeBattles = 0
local function setCombatFlag()
	workspace:SetAttribute("ColosseumCombat", activeBattles > 0)
end

local function power(card): number
	local rarity = CardsData.RarityById[card.Rarity]
	return card.HP + card.Attack * 2 + (rarity and rarity.Order * 15 or 0)
end

local function fighter(c): Fighter
	return { Id = c.Id, HP = c.HP, MaxHP = c.HP, Attack = c.Attack, Element = c.Element, SpecialUsed = false, Guard = false }
end

local function owned(profile): { any }
	local list = {}
	for id, count in pairs(profile.Cards) do
		local card = CardsData.CardById[id]
		if card and count > 0 then
			table.insert(list, card)
		end
	end
	table.sort(list, function(x, y)
		return power(x) > power(y)
	end)
	return list
end

-- Les 3 créatures les plus puissantes de la collection (choix par défaut).
function DuelCombat.deckFor(profile): { Fighter }
	local list = owned(profile)
	local deck = {}
	for i = 1, math.min(DECK_SIZE, #list) do
		table.insert(deck, fighter(list[i]))
	end
	return deck
end

-- Équipe choisie : identifiants valides, distincts, possédés.
local function deckFromPick(profile, ids): { Fighter }?
	if type(ids) ~= "table" then
		return nil
	end
	local list = owned(profile)
	local need = math.min(DECK_SIZE, #list)
	if #ids ~= need then
		return nil
	end
	local seen, deck = {}, {}
	for _, id in ipairs(ids) do
		local card = type(id) == "string" and CardsData.CardById[id]
		if not card or seen[id] or (profile.Cards[id] or 0) <= 0 then
			return nil
		end
		seen[id] = true
		table.insert(deck, fighter(card))
	end
	return deck
end

local function multiplier(attacker: string, defender: string): number
	if STRONG[attacker] == defender then
		return 1.5
	elseif STRONG[defender] == attacker then
		return 0.75
	end
	return 1
end

local function active(deck: { Fighter }): (Fighter?, number)
	for i, f in ipairs(deck) do
		if f.HP > 0 then
			return f, i
		end
	end
	return nil, 0
end

local function snapshot(deck: { Fighter })
	local out = {}
	for i, f in ipairs(deck) do
		out[i] = { Id = f.Id, HP = f.HP, MaxHP = f.MaxHP, SpecialUsed = f.SpecialUsed, Guard = f.Guard }
	end
	return out
end

-- Adversaire d'entraînement : une table qui imite un joueur.
function DuelCombat.newBot(name: string)
	return { IsBot = true, DisplayName = name, UserId = 0, Name = name }
end
local function isBot(p): boolean
	return type(p) == "table" and p.IsBot == true
end

-- Équipe du bot : pour chaque créature du joueur, une créature de même rareté.
function DuelCombat.botDeck(playerDeck: { Fighter }): { Fighter }
	local deck = {}
	for _, f in ipairs(playerDeck) do
		local mine = CardsData.CardById[f.Id]
		local pool = {}
		for _, c in ipairs(CardsData.Cards) do
			if mine and c.Rarity == mine.Rarity then
				table.insert(pool, c)
			end
		end
		local c = #pool > 0 and pool[math.random(1, #pool)] or CardsData.Cards[math.random(1, #CardsData.Cards)]
		table.insert(deck, fighter(c))
	end
	return deck
end

-- Choix du bot : coup spécial pour achever ou de temps en temps, garde
-- quand sa créature est affaiblie, attaque sinon.
local function botChoice(mine: Fighter?, target: Fighter?): string
	if not (mine and target) then
		return "Attack"
	end
	local mult = multiplier(mine.Element, target.Element)
	if not mine.SpecialUsed and (target.HP <= mine.Attack * mult * SPECIAL_POWER or math.random() < 0.25) then
		return "Special"
	end
	if mine.HP < mine.MaxHP * 0.35 and not mine.Guard and math.random() < 0.45 then
		return "Defend"
	end
	return "Attack"
end

function DuelCombat.isFighting(player): boolean
	return battles[player] ~= nil
end

-- Démarre un duel. `profileB` vaut nil pour un bot (équipe calquée sur
-- celle du joueur). `fire(player, kind, data)` envoie au client ;
-- `onEnd(winner?, loser?, reason)` est appelé une seule fois à la fin.
function DuelCombat.start(a, b, profileA, profileB, fire: (any, string, any) -> (), onEnd: (any?, any?, string) -> ())
	local battle = { Players = { a, b }, Decks = {}, Profiles = { [a] = profileA, [b] = profileB }, Phase = "Select", Over = false, Turn = 0 }
	local rawFire = fire
	fire = function(p, kind, data)
		if not isBot(p) then
			rawFire(p, kind, data)
		end
	end
	battles[a], battles[b] = battle, battle
	activeBattles += 1
	setCombatFlag()
	local function other(p)
		return p == a and b or a
	end
	local function finish(winner, loser, reason: string)
		if battle.Over then
			return
		end
		battle.Over = true
		battles[a], battles[b] = nil, nil
		activeBattles = math.max(0, activeBattles - 1)
		setCombatFlag()
		for _, p in ipairs({ a, b }) do
			if isBot(p) or p.Parent then
				fire(p, "Result", { Outcome = winner == nil and "Draw" or (winner == p and "Win" or "Lose"), Reason = reason })
			end
		end
		onEnd(winner, loser, reason)
	end
	battle.Finish = finish
	battle.Fire = fire

	-- 1. Sélection des équipes.
	for _, p in ipairs({ a, b }) do
		local profile = battle.Profiles[p]
		if profile then
			local o = other(p)
			local cards = {}
			for _, card in ipairs(owned(profile)) do
				table.insert(cards, { Id = card.Id, Count = profile.Cards[card.Id] })
			end
			fire(p, "Select", {
				Cards = cards,
				Size = math.min(DECK_SIZE, #cards),
				Time = SELECT_TIME,
				Opp = { Name = o.DisplayName, UserId = o.UserId },
				Training = isBot(o),
			})
		end
	end

	task.spawn(function()
		local deadline = os.clock() + SELECT_TIME
		local function ready(p)
			return battle.Decks[p] ~= nil or battle.Profiles[p] == nil
		end
		while not battle.Over and os.clock() < deadline and not (ready(a) and ready(b)) do
			task.wait(0.1)
		end
		if battle.Over then
			return
		end
		for _, p in ipairs({ a, b }) do
			if not battle.Decks[p] and battle.Profiles[p] then
				battle.Decks[p] = DuelCombat.deckFor(battle.Profiles[p])
			end
		end
		for _, p in ipairs({ a, b }) do
			if not battle.Decks[p] then
				battle.Decks[p] = DuelCombat.botDeck(battle.Decks[other(p)])
			end
		end
		battle.Phase = "Intro"

		for _, p in ipairs({ a, b }) do
			local o = other(p)
			fire(p, "Start", {
				Me = { Name = p.DisplayName, UserId = p.UserId, Deck = snapshot(battle.Decks[p]) },
				Opp = { Name = o.DisplayName, UserId = o.UserId, Deck = snapshot(battle.Decks[o]) },
				IntroTime = INTRO_TIME,
			})
		end
		task.wait(INTRO_TIME)

		-- 2. Combat au tour par tour : premier joueur tiré au sort.
		battle.Phase = "Fight"
		local current = math.random() < 0.5 and a or b
		while not battle.Over do
			battle.Turn += 1
			battle.Current = current
			battle.Choice = nil
			local opponent = other(current)
			local mine = active(battle.Decks[current])
			local target = active(battle.Decks[opponent])
			-- La garde ne dure que jusqu'au prochain tour de son propriétaire.
			if mine then
				mine.Guard = false
			end
			for _, p in ipairs({ a, b }) do
				local me, mi = active(battle.Decks[p])
				local _, oi = active(battle.Decks[other(p)])
				fire(p, "Turn", {
					Turn = battle.Turn,
					Time = TURN_TIME,
					Mine = p == current,
					ActiveName = current.DisplayName,
					MyActive = mi,
					OppActive = oi,
					CanSpecial = p == current and me ~= nil and not me.SpecialUsed,
					Me = snapshot(battle.Decks[p]),
					Opp = snapshot(battle.Decks[other(p)]),
				})
			end
			if isBot(current) then
				task.delay(math.random(12, 25) / 10, function()
					if not battle.Over and battle.Current == current and not battle.Choice then
						battle.Choice = botChoice(mine, target)
					end
				end)
			end
			local deadline2 = os.clock() + TURN_TIME
			while not battle.Over and os.clock() < deadline2 and not battle.Choice do
				task.wait(0.1)
			end
			if battle.Over then
				return
			end

			-- Résolution de l'action du joueur actif.
			local action = battle.Choice or "Attack"
			local event = { From = current.UserId, Action = action, Damage = 0, Mult = 1, Timeout = battle.Choice == nil }
			if mine and target then
				if action == "Defend" then
					local heal = math.floor(mine.MaxHP * GUARD_HEAL + 0.5)
					mine.HP = math.min(mine.MaxHP, mine.HP + heal)
					mine.Guard = true
					event.Heal = heal
				else
					local mult = multiplier(mine.Element, target.Element)
					local dmg = mine.Attack * mult * (action == "Special" and SPECIAL_POWER or 1) * (0.9 + math.random() * 0.2)
					if action == "Special" then
						mine.SpecialUsed = true
					end
					if target.Guard then
						dmg *= 0.5
						event.Blocked = true
						target.Guard = false
					end
					event.Damage = math.max(1, math.floor(dmg + 0.5))
					event.Mult = mult
					target.HP = math.max(0, target.HP - event.Damage)
					event.KO = target.HP <= 0
				end
			end
			for _, p in ipairs({ a, b }) do
				fire(p, "Resolve", { Events = { event }, Me = snapshot(battle.Decks[p]), Opp = snapshot(battle.Decks[other(p)]) })
			end
			task.wait((CINEMATIC_TIME[action] or RESOLVE_TIME) + (event.KO and 1 or 0))

			local aliveA, aliveB = active(battle.Decks[a]) ~= nil, active(battle.Decks[b]) ~= nil
			if not aliveA then
				finish(b, a, b.DisplayName .. " remporte le duel !")
			elseif not aliveB then
				finish(a, b, a.DisplayName .. " remporte le duel !")
			elseif battle.Turn >= MAX_TURNS then
				-- Trop long : victoire aux points de vie restants.
				local function total(deck)
					local s = 0
					for _, f in ipairs(deck) do
						s += f.HP / f.MaxHP
					end
					return s
				end
				local ta, tb = total(battle.Decks[a]), total(battle.Decks[b])
				if math.abs(ta - tb) < 0.01 then
					finish(nil, nil, "Égalité au temps !")
				elseif ta > tb then
					finish(a, b, "Victoire aux points pour " .. a.DisplayName .. " !")
				else
					finish(b, a, "Victoire aux points pour " .. b.DisplayName .. " !")
				end
			end
			current = opponent
		end
	end)
end

-- Équipe choisie pendant la phase de sélection.
function DuelCombat.pick(player, ids): (boolean, string?)
	local battle = battles[player]
	if not battle or battle.Over or battle.Phase ~= "Select" then
		return false, "La sélection est terminée."
	end
	if battle.Decks[player] then
		return false, "Équipe déjà validée."
	end
	local deck = deckFromPick(battle.Profiles[player], ids)
	if not deck then
		return false, "Choisis " .. DECK_SIZE .. " créatures différentes."
	end
	battle.Decks[player] = deck
	local o = battle.Players[1] == player and battle.Players[2] or battle.Players[1]
	-- Prévient l'adversaire que l'équipe est prête (sans la dévoiler).
	battle.Fire(o, "OppReady", {})
	return true
end

function DuelCombat.choose(player, action: string): (boolean, string?)
	local battle = battles[player]
	if not battle or battle.Over or battle.Phase ~= "Fight" then
		return false, "Aucun combat en cours."
	end
	if battle.Current ~= player then
		return false, "Ce n'est pas ton tour."
	end
	if action ~= "Attack" and action ~= "Defend" and action ~= "Special" then
		return false, "Action inconnue."
	end
	if battle.Choice then
		return false, "Action déjà choisie."
	end
	if action == "Special" then
		local f = active(battle.Decks[player])
		if not f or f.SpecialUsed then
			return false, "Coup spécial déjà utilisé par cette créature."
		end
	end
	battle.Choice = action
	return true
end

-- Abandon (départ, sortie de l'arène) : l'autre joueur gagne.
function DuelCombat.forfeit(player, reason: string)
	local battle = battles[player]
	if battle and not battle.Over then
		local opponent = battle.Players[1] == player and battle.Players[2] or battle.Players[1]
		battle.Finish(opponent, player, reason)
	end
end

return DuelCombat
