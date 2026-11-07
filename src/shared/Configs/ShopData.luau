-- Boutique Robux : produits (achats répétables) et passes de jeu (permanents).
--
-- Pour activer un achat, crée le produit ou le passe sur le Creator Hub
-- (Créations > ton expérience > Monétisation), puis colle son identifiant
-- dans ProductId / PassId ci-dessous. Tant qu'il vaut 0, le bouton
-- s'affiche mais indique que l'offre arrive bientôt.
local ShopData = {}

ShopData.GemPacks = {
	{ Id = "gems_s", Name = "Bourse de gemmes", Gems = 500, Robux = 49, ProductId = 0 },
	{ Id = "gems_m", Name = "Sacoche de gemmes", Gems = 1200, Robux = 99, ProductId = 0, Tag = "+20 %" },
	{ Id = "gems_l", Name = "Coffre de gemmes", Gems = 2800, Robux = 199, ProductId = 0, Tag = "POPULAIRE" },
	{ Id = "gems_xl", Name = "Trésor du dragon", Gems = 6500, Robux = 399, ProductId = 0, Tag = "MEILLEURE OFFRE" },
}

-- Offre de bienvenue : un seul achat par joueur.
ShopData.Starter = {
	Id = "starter",
	Name = "Pack du jeune dresseur",
	Description = "800 gemmes + 3 boosters, dont une carte Rare garantie.",
	Gems = 800,
	Boosters = 3,
	Robux = 79,
	ProductId = 0,
}

ShopData.Passes = {
	{
		Id = "VIP",
		Name = "Pass VIP",
		Description = "Récompenses quotidiennes doublées et 10 % de gemmes en plus sur chaque achat de gemmes.",
		Robux = 249,
		PassId = 0,
	},
	{
		Id = "Collector",
		Name = "Sac du collectionneur",
		Description = "Un booster gratuit en plus avec chaque récompense quotidienne.",
		Robux = 149,
		PassId = 0,
	},
}

function ShopData.productById(productId: number)
	if productId == 0 then
		return nil
	end
	for _, pack in ipairs(ShopData.GemPacks) do
		if pack.ProductId == productId then
			return pack
		end
	end
	if ShopData.Starter.ProductId == productId then
		return ShopData.Starter
	end
	return nil
end

return ShopData
