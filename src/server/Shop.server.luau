-- Achats Robux : traitement sécurisé des reçus (une seule fois par achat)
-- et avantages des passes de jeu, exposés en attributs du joueur.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local CardsData = require(Configs:WaitForChild("CardsData"))
local ShopData = require(Configs:WaitForChild("ShopData"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local CardService = require(script.Parent:WaitForChild("CardService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PurchaseGranted: RemoteEvent = Remotes:WaitForChild("PurchaseGranted")

local MAX_RECEIPTS = 50

-- Passes de jeu : vérifiés à l'arrivée et à chaque achat en cours de partie.
local function refreshPasses(player: Player)
	for _, pass in ipairs(ShopData.Passes) do
		local owned = false
		if pass.PassId ~= 0 then
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.PassId)
			owned = ok and result == true
		end
		player:SetAttribute(pass.Id, owned)
	end
end

Players.PlayerAdded:Connect(refreshPasses)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(refreshPasses, player)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	for _, pass in ipairs(ShopData.Passes) do
		if pass.PassId == passId then
			player:SetAttribute(pass.Id, true)
			PurchaseGranted:FireClient(player, { Kind = "Pass", Name = pass.Name, Gems = 0, Results = {} })
		end
	end
end)

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService.WaitFor(player, 10)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receipts = profile.Receipts
	-- Reçu déjà traité (nouvelle tentative de Roblox) : on confirme sans redonner.
	if table.find(receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = ShopData.productById(receipt.ProductId)
	if not product then
		warn("[Shop] Produit inconnu :", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local gems = product.Gems or 0
	if player:GetAttribute("VIP") and product ~= ShopData.Starter then
		gems = math.floor(gems * 1.1)
	end
	profile.Coins += gems
	local results = {}
	for index = 1, product.Boosters or 0 do
		-- Le premier booster du pack de départ est au moins Rare.
		local card = CardService.draw(index == 1 and function(c)
			return CardsData.RarityById[c.Rarity].Order >= 2
		end or nil)
		if card then
			profile.BoostersOpened += 1
			table.insert(results, CardService.grant(profile, card))
		end
	end
	if product == ShopData.Starter then
		profile.StarterBought = true
	end
	table.insert(receipts, receipt.PurchaseId)
	while #receipts > MAX_RECEIPTS do
		table.remove(receipts, 1)
	end

	-- Sauvegarde immédiate : un achat ne doit jamais être perdu.
	DataService.Save(player)
	DataService.MarkChanged(player)
	PurchaseGranted:FireClient(player, { Kind = "Product", Name = product.Name, Gems = gems, Results = results })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
