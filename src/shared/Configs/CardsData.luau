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

CardsData.CardById = {}
for _, card in ipairs(CardsData.Cards) do
	CardsData.CardById[card.Id] = card
end

return CardsData
