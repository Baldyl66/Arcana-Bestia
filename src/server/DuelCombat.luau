-- Combat de cartes du Colisée, au tour par tour.
-- 1. Sélection : chaque duelliste choisit 3 créatures de sa collection
--    (choix automatique des plus puissantes si le temps s'écoule).
-- 2. Combat : les joueurs jouent chacun leur tour. Le joueur actif choisit :
--    • Attaque (+1 énergie) ;
--    • Garde (+2 énergie, soigne un peu, divise par deux le prochain coup) ;
--    • Capacité unique de la créature (coûte de l'énergie, voir CardsData) ;
--    • Changer de créature (prend le tour).
--    Statuts : brûlure/poison (dégâts en début de tour), étourdi/gelé (tour
--    sauté), affaibli/rage (attaque modifiée), bouclier, miroir.
--    Les affinités d'éléments multiplient les dégâts. Une créature K.O. laisse
--    sa place à la suivante ; le premier à perdre toutes ses créatures perd.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))

local DuelCombat = {}

local DECK_SIZE = 3
local SELECT_TIME = 30
local TURN_TIME = 15
-- VS (~3 s) + entrée 3D des duellistes et de leurs Anima (~8,5 s).
local INTRO_TIME = 12
-- Temps laissé au client pour jouer chaque événement (cinématiques comprises).
local EVENT_TIME = { Attack = 2.9, Ability = 3.6, AbilitySelf = 2.2, Defend = 2.2, Switch = 1.8, Tick = 1.5, Stunned = 1.7 }
local MAX_TURNS = 60
local RULES = CardsData.Combat
-- Élément fort contre élément (x1,5) ; l'inverse subit x0,75.
local STRONG = { Feu = "Nature", Nature = "Eau", Eau = "Feu", Foudre = "Eau", Ombre = "Lumiere", Lumiere = "Ombre" }

export type Fighter = {
	Id: string, HP: number, MaxHP: number, Attack: number, Element: string, Guard: boolean,
	Shield: number, Burn: number, Poison: number, Stun: number, Freeze: number, Weak: number, Rage: number, Reflect: boolean,
}

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
	return { Id = c.Id, HP = c.HP, MaxHP = c.HP, Attack = c.Attack, Element = c.Element, Guard = false,
		Shield = 0, Burn = 0, Poison = 0, Stun = 0, Freeze = 0, Weak = 0, Rage = 0, Reflect = false }
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

-- Créature au combat : index choisi (battle.Active) si encore debout,
-- sinon la première encore en vie.
local function firstAlive(deck: { Fighter }): (Fighter?, number)
	for i, f in ipairs(deck) do
		if f.HP > 0 then
			return f, i
		end
	end
	return nil, 0
end

local function snapshot(deck: { Fighter }, activeIndex: number?)
	local out = {}
	for i, f in ipairs(deck) do
		out[i] = { Id = f.Id, HP = f.HP, MaxHP = f.MaxHP, Guard = f.Guard, Active = i == activeIndex, Shield = f.Shield,
			Burn = f.Burn, Poison = f.Poison, Stun = f.Stun, Freeze = f.Freeze, Weak = f.Weak, Rage = f.Rage, Reflect = f.Reflect }
	end
	return out
end

local function attackOf(f: Fighter): number
	local atk = f.Attack
	if f.Weak > 0 then
		atk *= RULES.WeakFactor
	end
	if f.Rage > 0 then
		atk *= RULES.RageFactor
	end
	return atk
end

local function round(x: number): number
	return math.floor(x + 0.5)
end

-- Un coup : garde, bouclier, miroir. Renvoie le détail pour le client.
local function strike(attacker: Fighter, target: Fighter, power: number, pierce: boolean?, execute: boolean?)
	local mult = multiplier(attacker.Element, target.Element)
	local dmg = attackOf(attacker) * mult * power * (0.9 + math.random() * 0.2)
	local hit = { Mult = mult }
	if execute and target.HP < target.MaxHP * RULES.ExecuteThreshold then
		dmg *= 2
		hit.Execute = true
	end
	if not pierce and target.Guard then
		dmg *= 0.5
		hit.Blocked = true
		target.Guard = false
	end
	local damage = math.max(1, round(dmg))
	if not pierce and target.Shield > 0 then
		local absorbed = math.min(target.Shield, damage)
		target.Shield -= absorbed
		damage -= absorbed
		hit.Absorbed = absorbed
	end
	if not pierce and target.Reflect and damage > 0 then
		target.Reflect = false
		local back = math.max(1, round(damage * RULES.ReflectFactor))
		attacker.HP = math.max(0, attacker.HP - back)
		hit.Reflected = back
	end
	target.HP = math.max(0, target.HP - damage)
	hit.Damage = damage
	return hit
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

-- Choix du bot : capacité quand l'énergie le permet et qu'elle est utile,
-- changement si l'affinité est mauvaise, garde quand il est affaibli.
local function botChoice(battle, me): string
	local deck = battle.Decks[me]
	local mine = deck[battle.Active[me]]
	local foe = battle.Players[1] == me and battle.Players[2] or battle.Players[1]
	local target = battle.Decks[foe][battle.Active[foe]]
	if not (mine and target) then
		return "Attack"
	end
	local energy = battle.Energy[me]
	local ability = CardsData.CardById[mine.Id].Ability
	local mult = multiplier(mine.Element, target.Element)
	-- Mauvaise affinité : chercher une créature plus adaptée sur le banc.
	if mult < 1 and math.random() < 0.5 then
		for i, f in ipairs(deck) do
			if f.HP > 0 and i ~= battle.Active[me] and multiplier(f.Element, target.Element) > 1 then
				return "Switch:" .. i
			end
		end
	end
	if energy >= ability.Cost then
		local selfOnly = ability.Power == nil
		local hurt = mine.HP < mine.MaxHP * 0.5
		if (selfOnly and hurt) or (not selfOnly and (math.random() < 0.7 or target.HP <= attackOf(mine) * mult * ability.Power * (ability.Hits or 1))) then
			return "Ability"
		end
	end
	if mine.HP < mine.MaxHP * 0.3 and not mine.Guard and math.random() < 0.3 then
		return "Defend"
	end
	-- Garde de temps en temps pour recharger l'énergie de la capacité.
	if energy + 2 >= ability.Cost and energy < ability.Cost and math.random() < 0.25 then
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
-- `spectate(kind, data)` (facultatif) reçoit le duel vu du côté de `a`, pour les spectateurs.
function DuelCombat.start(a, b, profileA, profileB, fire: (any, string, any) -> (), onEnd: (any?, any?, string) -> (), spectate: ((string, any) -> ())?)
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
		if spectate then
			task.spawn(spectate, "End", { Reason = reason, WinnerId = winner and winner.UserId })
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
		battle.Active, battle.Energy = {}, {}
		for _, p in ipairs({ a, b }) do
			local _, index = firstAlive(battle.Decks[p])
			battle.Active[p] = index
			battle.Energy[p] = RULES.EnergyStart
		end

		local function activeOf(p): Fighter?
			return battle.Decks[p][battle.Active[p]]
		end
		-- Si la créature active est K.O., la suivante en vie prend sa place.
		local function refreshActive(p)
			local f = activeOf(p)
			if not f or f.HP <= 0 then
				local _, index = firstAlive(battle.Decks[p])
				battle.Active[p] = index
			end
		end
		local function state(p)
			local o = other(p)
			return {
				Me = snapshot(battle.Decks[p], battle.Active[p]),
				Opp = snapshot(battle.Decks[o], battle.Active[o]),
				MyEnergy = battle.Energy[p],
				OppEnergy = battle.Energy[o],
			}
		end
		-- Envoie un événement aux deux joueurs puis laisse le temps de le jouer.
		local function broadcast(event, duration: number)
			for _, p in ipairs({ a, b }) do
				local data = state(p)
				data.Events = { event }
				fire(p, "Resolve", data)
			end
			if spectate then
				local data = state(a)
				data.Events = { event }
				task.spawn(spectate, "Resolve", data)
			end
			task.wait(duration + ((event.KO or event.SelfKO) and 1 or 0))
			refreshActive(a)
			refreshActive(b)
		end

		for _, p in ipairs({ a, b }) do
			local o = other(p)
			fire(p, "Start", {
				Me = { Name = p.DisplayName, UserId = p.UserId, Deck = snapshot(battle.Decks[p], battle.Active[p]) },
				Opp = { Name = o.DisplayName, UserId = o.UserId, Deck = snapshot(battle.Decks[o], battle.Active[o]) },
				MyEnergy = battle.Energy[p],
				OppEnergy = battle.Energy[o],
				IntroTime = INTRO_TIME,
			})
		end
		if spectate then
			local data = state(a)
			data.MeInfo = { Name = a.DisplayName, UserId = a.UserId }
			data.OppInfo = { Name = b.DisplayName, UserId = b.UserId }
			task.spawn(spectate, "Start", data)
		end
		task.wait(INTRO_TIME)

		local function checkEnd(): boolean
			local aliveA, aliveB = firstAlive(battle.Decks[a]) ~= nil, firstAlive(battle.Decks[b]) ~= nil
			if not aliveA and not aliveB then
				finish(nil, nil, "Double K.O. : égalité !")
			elseif not aliveA then
				finish(b, a, b.DisplayName .. " remporte le duel !")
			elseif not aliveB then
				finish(a, b, a.DisplayName .. " remporte le duel !")
			elseif battle.Turn >= MAX_TURNS then
				-- Trop long : victoire aux points de vie restants.
				local function total(deck)
					local sum = 0
					for _, f in ipairs(deck) do
						sum += f.HP / f.MaxHP
					end
					return sum
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
			return battle.Over
		end

		-- 2. Combat au tour par tour : premier joueur tiré au sort.
		battle.Phase = "Fight"
		local current = math.random() < 0.5 and a or b
		while not battle.Over do
			battle.Turn += 1
			battle.Current = current
			battle.Choice = nil
			local opponent = other(current)
			local mine = activeOf(current)

			-- Début de tour : la garde tombe, brûlure et poison font effet.
			if mine then
				mine.Guard = false
				for _, kind in ipairs({ "Burn", "Poison" }) do
					if mine[kind] > 0 and mine.HP > 0 then
						mine[kind] -= 1
						local dmg = math.max(1, round(mine.MaxHP * (kind == "Burn" and RULES.BurnDamage or RULES.PoisonDamage)))
						mine.HP = math.max(0, mine.HP - dmg)
						broadcast({ From = current.UserId, Action = "Tick", Status = kind, Damage = dmg, SelfKO = mine.HP <= 0 }, EVENT_TIME.Tick)
					end
				end
			end
			if checkEnd() then
				return
			end
			mine = activeOf(current)
			local target = activeOf(opponent)

			-- Étourdi ou gelé : le tour est perdu.
			local skipped = false
			if mine and (mine.Stun > 0 or mine.Freeze > 0) then
				local kind = mine.Freeze > 0 and "Freeze" or "Stun"
				mine[kind] -= 1
				skipped = true
				broadcast({ From = current.UserId, Action = "Stunned", Status = kind }, EVENT_TIME.Stunned)
			end

			if not skipped then
				for _, p in ipairs({ a, b }) do
					local data = state(p)
					data.Turn = battle.Turn
					data.Time = TURN_TIME
					data.Mine = p == current
					data.ActiveName = current.DisplayName
					fire(p, "Turn", data)
				end
				if isBot(current) then
					task.delay(math.random(12, 25) / 10, function()
						if not battle.Over and battle.Current == current and not battle.Choice then
							battle.Choice = botChoice(battle, current)
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
				local duration = EVENT_TIME.Attack
				local energy = battle.Energy[current]
				if action:sub(1, 7) == "Switch:" then
					local index = tonumber(action:sub(8))
					event.Action = "Switch"
					event.FromIndex = battle.Active[current]
					event.ToIndex = index
					battle.Active[current] = index
					duration = EVENT_TIME.Switch
				elseif mine and target and action == "Defend" then
					local heal = round(mine.MaxHP * RULES.GuardHeal)
					mine.HP = math.min(mine.MaxHP, mine.HP + heal)
					mine.Guard = true
					event.Heal = heal
					battle.Energy[current] = math.min(RULES.EnergyMax, energy + RULES.EnergyDefend)
					duration = EVENT_TIME.Defend
				elseif mine and target and action == "Ability" then
					local ability = CardsData.CardById[mine.Id].Ability
					battle.Energy[current] = math.max(0, energy - ability.Cost)
					event.Ability = ability.Name
					event.Effects = {}
					if ability.Power then
						event.Hits = {}
						for _ = 1, ability.Hits or 1 do
							if target.HP <= 0 or mine.HP <= 0 then
								break
							end
							local hit = strike(mine, target, ability.Power, ability.Pierce, ability.Execute)
							table.insert(event.Hits, hit.Damage)
							event.Damage += hit.Damage
							event.Mult = hit.Mult
							event.Blocked = event.Blocked or hit.Blocked
							event.Execute = event.Execute or hit.Execute
							event.Absorbed = (event.Absorbed or 0) + (hit.Absorbed or 0)
							event.Reflected = (event.Reflected or 0) + (hit.Reflected or 0)
						end
						if ability.Drain and event.Damage > 0 and mine.HP > 0 then
							local heal = round(event.Damage * ability.Drain)
							mine.HP = math.min(mine.MaxHP, mine.HP + heal)
							event.Heal = heal
						end
						if target.HP > 0 then
							for _, kind in ipairs({ "Burn", "Poison", "Stun", "Freeze", "Weak" }) do
								if ability[kind] then
									target[kind] = math.max(target[kind], ability[kind])
									table.insert(event.Effects, kind)
								end
							end
						end
						duration = EVENT_TIME.Ability + math.max(0, #event.Hits - 1) * 0.35
					else
						duration = EVENT_TIME.AbilitySelf
					end
					if ability.Cleanse then
						mine.Burn, mine.Poison, mine.Weak = 0, 0, 0
						table.insert(event.Effects, "Cleanse")
					end
					if ability.Heal then
						local heal = round(mine.MaxHP * ability.Heal)
						mine.HP = math.min(mine.MaxHP, mine.HP + heal)
						event.Heal = (event.Heal or 0) + heal
					end
					if ability.Shield then
						mine.Shield = math.max(mine.Shield, round(mine.MaxHP * ability.Shield))
						event.Shield = mine.Shield
						table.insert(event.Effects, "Shield")
					end
					if ability.Rage then
						-- +1 : le décompte de fin de ce tour-ci ne doit pas la consommer.
						mine.Rage = math.max(mine.Rage, ability.Rage + 1)
						table.insert(event.Effects, "Rage")
					end
					if ability.Reflect then
						mine.Guard = true
						mine.Reflect = true
						table.insert(event.Effects, "Reflect")
					end
				elseif mine and target then
					event.Action = "Attack"
					local hit = strike(mine, target, 1)
					event.Damage, event.Mult, event.Blocked = hit.Damage, hit.Mult, hit.Blocked
					event.Absorbed, event.Reflected = hit.Absorbed, hit.Reflected
					battle.Energy[current] = math.min(RULES.EnergyMax, energy + RULES.EnergyAttack)
				end
				event.KO = target ~= nil and target.HP <= 0
				event.SelfKO = mine ~= nil and mine.HP <= 0
				broadcast(event, duration)
			end

			-- Fin du tour : affaiblissement et rage s'estompent.
			if mine then
				mine.Weak = math.max(0, mine.Weak - 1)
				mine.Rage = math.max(0, mine.Rage - 1)
			end
			if checkEnd() then
				return
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
	if battle.Choice then
		return false, "Action déjà choisie."
	end
	if type(action) ~= "string" then
		return false, "Action inconnue."
	end
	local deck = battle.Decks[player]
	local mine = deck[battle.Active[player]]
	if action == "Ability" then
		local ability = mine and CardsData.CardById[mine.Id].Ability
		if not ability or battle.Energy[player] < ability.Cost then
			return false, "Pas assez d'énergie."
		end
	elseif action:sub(1, 7) == "Switch:" then
		local index = tonumber(action:sub(8))
		local f = index and deck[index]
		if not f or f.HP <= 0 or index == battle.Active[player] then
			return false, "Cette créature ne peut pas entrer."
		end
	elseif action ~= "Attack" and action ~= "Defend" then
		return false, "Action inconnue."
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
