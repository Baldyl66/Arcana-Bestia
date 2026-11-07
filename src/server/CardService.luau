-- Tirage pondéré et attribution des cartes, partagés par l'autel et le village.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))

local CardService = {}

local random = Random.new()

-- Tire une carte ; `filter` restreint le tirage (élément, rareté...).
function CardService.draw(filter: ((card: any) -> boolean)?)
	local pools: { [string]: { any } } = {}
	for _, card in ipairs(CardsData.Cards) do
		if filter == nil or filter(card) then
			pools[card.Rarity] = pools[card.Rarity] or {}
			table.insert(pools[card.Rarity], card)
		end
	end

	local total = 0
	for _, rarity in ipairs(CardsData.Rarities) do
		if pools[rarity.Id] then
			total += rarity.Weight
		end
	end
	if total == 0 then
		return nil
	end

	local roll = random:NextNumber(0, total)
	local cumulative = 0
	local last = nil
	for _, rarity in ipairs(CardsData.Rarities) do
		local pool = pools[rarity.Id]
		if pool then
			last = pool
			cumulative += rarity.Weight
			if roll <= cumulative then
				return pool[random:NextInteger(1, #pool)]
			end
		end
	end
	return last[random:NextInteger(1, #last)]
end

-- Ajoute la carte au profil et renvoie le résultat affiché au client.
function CardService.grant(profile, card)
	local previous = profile.Cards[card.Id] or 0
	profile.Cards[card.Id] = previous + 1
	local refund = 0
	if previous > 0 then
		refund = CardsData.Economy.DuplicateRefund[card.Rarity] or 0
		profile.Coins += refund
	end
	return {
		card = card,
		isNew = previous == 0,
		count = previous + 1,
		refund = refund,
	}
end

-- Ouvre un booster payant : renvoie la liste des résultats ou nil + raison.
function CardService.openPaid(profile, price: number, count: number, filter: ((card: any) -> boolean)?)
	if profile.Coins < price then
		return nil, "Pas assez de gemmes !"
	end
	profile.Coins -= price
	local results = {}
	for _ = 1, count do
		local card = CardService.draw(filter)
		if card then
			profile.BoostersOpened += 1
			table.insert(results, CardService.grant(profile, card))
		end
	end
	return results
end

return CardService
