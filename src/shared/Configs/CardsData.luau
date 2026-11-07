local CardsData = {}

-- Ordre d'affichage et poids de tirage (en pourcentage).
CardsData.Rarities = {
	{ Id = "Commun", Label = "Commun", Weight = 55, Color = Color3.fromRGB(215, 215, 225) },
	{ Id = "PeuCommun", Label = "Peu commun", Weight = 26, Color = Color3.fromRGB(100, 225, 130) },
	{ Id = "Rare", Label = "Rare", Weight = 12, Color = Color3.fromRGB(80, 165, 255) },
	{ Id = "Epique", Label = "Épique", Weight = 5.5, Color = Color3.fromRGB(195, 95, 255) },
	{ Id = "Legendaire", Label = "Légendaire", Weight = 1.5, Color = Color3.fromRGB(255, 195, 55) },
}

CardsData.RarityById = {}
for index, rarity in ipairs(CardsData.Rarities) do
	rarity.Order = index
	CardsData.RarityById[rarity.Id] = rarity
end

CardsData.Elements = {
	Feu = { Label = "Feu", Color = Color3.fromRGB(255, 120, 60), Dark = Color3.fromRGB(110, 25, 15) },
	Eau = { Label = "Eau", Color = Color3.fromRGB(70, 165, 255), Dark = Color3.fromRGB(15, 40, 110) },
	Nature = { Label = "Nature", Color = Color3.fromRGB(95, 205, 110), Dark = Color3.fromRGB(15, 70, 35) },
	Foudre = { Label = "Foudre", Color = Color3.fromRGB(255, 220, 70), Dark = Color3.fromRGB(120, 80, 10) },
	Ombre = { Label = "Ombre", Color = Color3.fromRGB(150, 95, 225), Dark = Color3.fromRGB(25, 12, 55) },
	Lumiere = { Label = "Lumière", Color = Color3.fromRGB(255, 240, 185), Dark = Color3.fromRGB(170, 120, 35) },
}

CardsData.Economy = {
	StartingCoins = 500,
	BoosterPrice = 100,
	CardsPerBooster = 3,
	DailyReward = 250,
	DailyCooldown = 20 * 60 * 60,
	-- Récompenses de connexion : un palier par jour consécutif, puis la
	-- série recommence au jour 1 (ou dès qu'un jour est manqué).
	DailyRewards = {
		{ Coins = 100, Label = "100 ◆" },
		{ Coins = 150, Label = "150 ◆" },
		{ Coins = 200, Label = "200 ◆" },
		{ Booster = true, Label = "1 booster" },
		{ Coins = 300, Label = "300 ◆" },
		{ Coins = 400, Label = "400 ◆" },
		{ Coins = 500, MinRarity = 3, Label = "500 ◆ + Rare+" },
	},
	PassiveIncome = 15,
	PassiveInterval = 60,
	DuplicateRefund = {
		Commun = 10,
		PeuCommun = 20,
		Rare = 40,
		Epique = 80,
		Legendaire = 200,
	},
}

CardsData.Cards = {
	{ Id = "flamichat", Name = "Flamichat", Element = "Feu", Rarity = "Commun", HP = 80, Attack = 25,
		Description = "Un petit compagnon de feu rapide et joueur." },
	{ Id = "gouttelin", Name = "Gouttelin", Element = "Eau", Rarity = "Commun", HP = 85, Attack = 20,
		Description = "Il naît dans la rosée du matin et s'évapore quand il a peur." },
	{ Id = "mousseron", Name = "Mousseron", Element = "Nature", Rarity = "Commun", HP = 95, Attack = 18,
		Description = "Un champignon timide qui libère des spores apaisantes." },
	{ Id = "etincelot", Name = "Étincelot", Element = "Foudre", Rarity = "Commun", HP = 70, Attack = 30,
		Description = "Il crépite d'énergie et ne tient jamais en place." },
	{ Id = "aquatortue", Name = "Aquatortue", Element = "Eau", Rarity = "PeuCommun", HP = 120, Attack = 20,
		Description = "Une tortue solide qui maîtrise les courants." },
	{ Id = "ronceloup", Name = "Ronceloup", Element = "Nature", Rarity = "PeuCommun", HP = 110, Attack = 32,
		Description = "Un loup dont le pelage est fait de ronces vivantes." },
	{ Id = "cendrebouc", Name = "Cendrebouc", Element = "Feu", Rarity = "PeuCommun", HP = 115, Attack = 30,
		Description = "Ses cornes rougeoient comme des braises au crépuscule." },
	{ Id = "pyrogriff", Name = "Pyrogriff", Element = "Feu", Rarity = "Rare", HP = 145, Attack = 42,
		Description = "Un gardien aérien qui embrase ses ailes." },
	{ Id = "voltigeai", Name = "Voltigeai", Element = "Foudre", Rarity = "Rare", HP = 130, Attack = 46,
		Description = "Un oiseau d'orage qui chevauche les éclairs." },
	{ Id = "abyssalor", Name = "Abyssalor", Element = "Eau", Rarity = "Rare", HP = 160, Attack = 38,
		Description = "Une murène colossale qui hante les lacs profonds." },
	{ Id = "umbrelune", Name = "Umbrelune", Element = "Ombre", Rarity = "Epique", HP = 175, Attack = 50,
		Description = "Une créature nocturne venue des profondeurs." },
	{ Id = "sylvaroc", Name = "Sylvaroc", Element = "Nature", Rarity = "Epique", HP = 210, Attack = 40,
		Description = "Un golem de pierre et de racines, aussi vieux que la forêt." },
	{ Id = "tonnerrhin", Name = "Tonnerrhin", Element = "Foudre", Rarity = "Epique", HP = 185, Attack = 54,
		Description = "Chacun de ses pas fait gronder le ciel." },
	{ Id = "solaryx", Name = "Solaryx", Element = "Lumiere", Rarity = "Legendaire", HP = 200, Attack = 60,
		Description = "Une créature solaire extrêmement rare." },
	{ Id = "nyxaria", Name = "Nyxaria", Element = "Ombre", Rarity = "Legendaire", HP = 190, Attack = 66,
		Description = "La reine des éclipses, dont le regard éteint les étoiles." },

	-- Communs
	{ Id = "lucioline", Name = "Lucioline", Element = "Lumiere", Rarity = "Commun", HP = 75, Attack = 24,
		Description = "Une luciole curieuse qui guide les voyageurs égarés." },
	{ Id = "ombrelin", Name = "Ombrelin", Element = "Ombre", Rarity = "Commun", HP = 78, Attack = 26,
		Description = "Il se cache dans l'ombre des autres et imite leurs gestes." },
	{ Id = "braisille", Name = "Braisille", Element = "Feu", Rarity = "Commun", HP = 72, Attack = 28,
		Description = "Une salamandre minuscule qui dort dans les cheminées." },
	{ Id = "galetor", Name = "Galetor", Element = "Nature", Rarity = "Commun", HP = 100, Attack = 16,
		Description = "Un petit tatou de mousse qui roule le long des sentiers." },
	-- Peu communs
	{ Id = "marelame", Name = "Marelame", Element = "Eau", Rarity = "PeuCommun", HP = 105, Attack = 30,
		Description = "Un espadon des marées dont l'épée fend les vagues." },
	{ Id = "orageon", Name = "Orageon", Element = "Foudre", Rarity = "PeuCommun", HP = 100, Attack = 34,
		Description = "Un bélier dont la laine accumule l'électricité des orages." },
	{ Id = "aurelion", Name = "Aurélion", Element = "Lumiere", Rarity = "PeuCommun", HP = 112, Attack = 28,
		Description = "Un lionceau doré dont la crinière brille à l'aube." },
	{ Id = "spectrombre", Name = "Spectrombre", Element = "Ombre", Rarity = "PeuCommun", HP = 98, Attack = 35,
		Description = "Un renard fantôme qui traverse les murs les nuits de brume." },
	-- Rares
	{ Id = "florhydre", Name = "Florhydre", Element = "Nature", Rarity = "Rare", HP = 150, Attack = 40,
		Description = "Une hydre fleurie : chaque tête coupée repousse en bouton." },
	{ Id = "seraphel", Name = "Séraphel", Element = "Lumiere", Rarity = "Rare", HP = 140, Attack = 44,
		Description = "Un cerf ailé qui veille sur les sanctuaires oubliés." },
	{ Id = "nocturbe", Name = "Nocturbe", Element = "Ombre", Rarity = "Rare", HP = 135, Attack = 47,
		Description = "Un hibou géant dont les plumes absorbent la lumière." },
	-- Épiques
	{ Id = "magmorex", Name = "Magmorex", Element = "Feu", Rarity = "Epique", HP = 195, Attack = 52,
		Description = "Un dragon de lave qui sommeille sous les volcans." },
	{ Id = "glacimar", Name = "Glacimar", Element = "Eau", Rarity = "Epique", HP = 205, Attack = 46,
		Description = "Un léviathan des mers gelées au chant envoûtant." },
	-- Légendaires
	{ Id = "fulguron", Name = "Fulguron", Element = "Foudre", Rarity = "Legendaire", HP = 185, Attack = 70,
		Description = "Le seigneur des tempêtes, né du premier éclair du monde." },
	{ Id = "gaiandre", Name = "Gaïandre", Element = "Nature", Rarity = "Legendaire", HP = 240, Attack = 56,
		Description = "La gardienne millénaire des forêts, sur son dos pousse un bois entier." },
}

-------------------------------------------------------------------------------
-- Combat : énergie, statuts et capacité unique de chaque créature.
-------------------------------------------------------------------------------
CardsData.Combat = {
	EnergyMax = 5,
	EnergyStart = 1,
	EnergyAttack = 1, -- gagnée en attaquant
	EnergyDefend = 2, -- gagnée en gardant
	GuardHeal = 0.05, -- soin de la garde (part des PV max)
	BurnDamage = 0.08, -- par tour, part des PV max
	PoisonDamage = 0.07,
	WeakFactor = 0.7, -- attaque affaiblie
	RageFactor = 1.4, -- attaque enragée
	ReflectFactor = 0.5, -- part des dégâts renvoyés par le miroir
	ExecuteThreshold = 0.4, -- sous 40 % de PV, l'exécution double les dégâts
}

-- Libellés et icônes des statuts (affichés sous la barre de vie).
CardsData.Statuses = {
	Burn = { Label = "Brûlure", Icon = "🔥", Color = Color3.fromRGB(255, 130, 60) },
	Poison = { Label = "Poison", Icon = "☠", Color = Color3.fromRGB(150, 220, 90) },
	Stun = { Label = "Étourdi", Icon = "⚡", Color = Color3.fromRGB(255, 225, 80) },
	Freeze = { Label = "Gelé", Icon = "❄", Color = Color3.fromRGB(150, 220, 255) },
	Weak = { Label = "Affaibli", Icon = "▼", Color = Color3.fromRGB(190, 140, 255) },
	Rage = { Label = "Rage", Icon = "▲", Color = Color3.fromRGB(255, 90, 90) },
	Shield = { Label = "Bouclier", Icon = "◈", Color = Color3.fromRGB(120, 200, 255) },
	Reflect = { Label = "Miroir", Icon = "◇", Color = Color3.fromRGB(200, 240, 255) },
}

--[[ Capacité de chaque créature. Champs (tous facultatifs sauf Name/Cost) :
	Power   : multiplicateur de dégâts (absent = pas d'attaque)
	Hits    : nombre de coups (Power par coup)
	Pierce  : ignore la garde, le bouclier et le miroir
	Execute : dégâts doublés si la cible est sous le seuil d'exécution
	Drain   : part des dégâts rendue en PV
	Burn / Poison / Stun / Freeze / Weak : tours infligés à la cible
	Rage    : tours d'attaque augmentée pour soi
	Shield  : bouclier pour soi (part des PV max)
	Heal    : soin pour soi (part des PV max)
	Cleanse : retire brûlure, poison et affaiblissement de soi
	Reflect : garde + miroir pour soi ]]
local ABILITIES = {
	-- Communs
	flamichat = { Name = "Griffe ardente", Cost = 2, Power = 1.0, Burn = 2 },
	gouttelin = { Name = "Bulle protectrice", Cost = 2, Shield = 0.3 },
	mousseron = { Name = "Nuage de spores", Cost = 2, Power = 0.6, Poison = 3 },
	etincelot = { Name = "Décharge", Cost = 3, Power = 0.8, Stun = 1 },
	lucioline = { Name = "Lueur apaisante", Cost = 2, Heal = 0.3, Cleanse = true },
	ombrelin = { Name = "Mimétisme", Cost = 2, Power = 0.8, Weak = 2 },
	braisille = { Name = "Étincelle", Cost = 2, Power = 0.9, Burn = 2 },
	galetor = { Name = "Carapace roulée", Cost = 2, Shield = 0.35 },
	-- Peu communs
	aquatortue = { Name = "Carapace miroir", Cost = 2, Reflect = true },
	ronceloup = { Name = "Double morsure", Cost = 2, Power = 0.75, Hits = 2 },
	cendrebouc = { Name = "Charge incandescente", Cost = 3, Power = 1.3, Burn = 2 },
	marelame = { Name = "Lame des marées", Cost = 3, Power = 1.4, Pierce = true },
	orageon = { Name = "Laine statique", Cost = 3, Power = 0.7, Stun = 1 },
	aurelion = { Name = "Rugissement d'aube", Cost = 2, Power = 0.8, Rage = 2 },
	spectrombre = { Name = "Traversée spectrale", Cost = 2, Power = 1.1, Drain = 0.5 },
	-- Rares
	pyrogriff = { Name = "Ailes embrasées", Cost = 3, Power = 1.5, Burn = 3 },
	voltigeai = { Name = "Cascade d'éclairs", Cost = 3, Power = 0.6, Hits = 3 },
	abyssalor = { Name = "Étreinte abyssale", Cost = 3, Power = 1.3, Drain = 0.6 },
	florhydre = { Name = "Repousse", Cost = 3, Heal = 0.45, Cleanse = true },
	seraphel = { Name = "Bénédiction", Cost = 3, Shield = 0.35, Cleanse = true },
	nocturbe = { Name = "Vol nocturne", Cost = 3, Power = 1.2, Execute = true },
	-- Épiques
	umbrelune = { Name = "Éclipse", Cost = 3, Power = 1.4, Weak = 2 },
	sylvaroc = { Name = "Racines millénaires", Cost = 3, Shield = 0.45, Heal = 0.1 },
	tonnerrhin = { Name = "Piétinement orageux", Cost = 4, Power = 1.3, Stun = 1 },
	magmorex = { Name = "Éruption", Cost = 4, Power = 1.8, Burn = 3 },
	glacimar = { Name = "Chant glacial", Cost = 4, Power = 1.2, Freeze = 1 },
	-- Légendaires
	solaryx = { Name = "Supernova", Cost = 4, Power = 2.2, Pierce = true },
	nyxaria = { Name = "Nuit éternelle", Cost = 4, Power = 1.6, Drain = 0.5, Weak = 2 },
	fulguron = { Name = "Jugement de foudre", Cost = 4, Power = 0.75, Hits = 3 },
	gaiandre = { Name = "Floraison sacrée", Cost = 4, Heal = 0.4, Shield = 0.25, Cleanse = true },
}

-- Texte court décrivant une capacité (bouton, collection).
function CardsData.abilityText(ability): string
	local parts = {}
	if ability.Power then
		local hits = ability.Hits or 1
		table.insert(parts, string.format("%s%d%% ATQ", hits > 1 and (hits .. "×") or "", math.floor(ability.Power * 100 + 0.5)))
	end
	if ability.Pierce then table.insert(parts, "perce la garde") end
	if ability.Execute then table.insert(parts, "×2 si PV < 40%") end
	if ability.Drain then table.insert(parts, string.format("vol %d%%", ability.Drain * 100)) end
	if ability.Burn then table.insert(parts, "brûlure " .. ability.Burn .. "t") end
	if ability.Poison then table.insert(parts, "poison " .. ability.Poison .. "t") end
	if ability.Stun then table.insert(parts, "étourdit") end
	if ability.Freeze then table.insert(parts, "gèle") end
	if ability.Weak then table.insert(parts, "affaiblit " .. ability.Weak .. "t") end
	if ability.Rage then table.insert(parts, "rage " .. ability.Rage .. "t") end
	if ability.Shield then table.insert(parts, string.format("bouclier %d%%", ability.Shield * 100)) end
	if ability.Heal then table.insert(parts, string.format("soin %d%%", ability.Heal * 100)) end
	if ability.Cleanse then table.insert(parts, "purifie") end
	if ability.Reflect then table.insert(parts, "garde + renvoie ½") end
	return table.concat(parts, " · ")
end

CardsData.CardById = {}
for _, card in ipairs(CardsData.Cards) do
	CardsData.CardById[card.Id] = card
	card.Ability = ABILITIES[card.Id] or { Name = "Coup puissant", Cost = 3, Power = 1.6 }
end

return CardsData
