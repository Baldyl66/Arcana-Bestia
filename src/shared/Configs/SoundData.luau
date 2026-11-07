-- Sons d'Arcana Bestia. Aucun son « classique » de Roblox (rbxasset://) :
-- uniquement des pistes des catalogues sous licence de Roblox (APM Music,
-- Pro Sound Effects, DistroKid), libres d'utilisation dans le jeu.
-- Pour changer un son : Studio > Toolbox > Audio, écoute, puis colle
-- « rbxassetid://<numéro> » ici. Id = "" : le son est simplement muet.
local SoundData = {}

-- Musiques : fondu enchaîné selon l'écran (voir client/UI/Music).
SoundData.Music = {
	-- « Magical Tale » (APM) : mélodie féerique au célesta, douce et vivante.
	-- Autres pistes calmes à essayer : « Tiny Ripples in the River » (harpe,
	-- 9039607235), « Pastoral Joy B » (1846656266), « As Through A Mist »
	-- (1840524498), « Dream State » (1840547127). Ancien thème, trop dynamique :
	-- « Main Theme » 88915410935193.
	Menu = { Id = "rbxassetid://1842186397", Volume = 0.4 },
	Explore = { Id = "rbxassetid://80451125186395", Volume = 0.3 }, -- « Orchestral Serenity »
	Duel = { Id = "rbxassetid://1848108091", Volume = 0.4 }, -- « Fight For A Tomorrow » (APM)
}

-- Effets (UIKit.playSound et Ambience). Pitch : vitesse de lecture.
SoundData.Effects = {
	-- Interface
	-- Petit coup de bois sec (Pro Sound Effects), joué plus aigu pour les clics.
	-- Variante à essayer : « Smaltra UI click » rbxassetid://114782931135220.
	Click = { Id = "rbxassetid://9125654847", Volume = 0.35, Pitch = 1.5 },
	Prompt = { Id = "rbxassetid://9125654847", Volume = 0.4, Pitch = 1.1 },
	Reward = { Id = "rbxassetid://1839881844", Volume = 0.5 }, -- jingle court (APM)
	-- Carnet
	BookOpen = { Id = "rbxassetid://9118835414", Volume = 0.6 }, -- grimoire en cuir qui s'ouvre
	PageTurn = { Id = "rbxassetid://9118835637", Volume = 0.5 },
	-- Boosters et cartes
	Reveal = { Id = "rbxassetid://9118883081", Volume = 0.5 }, -- souffle brûlant (éclat de la carte)
	-- Combat
	Swoosh = { Id = "rbxassetid://9114157694", Volume = 0.6 }, -- whoosh Doppler
	Charge = { Id = "rbxassetid://9119467152", Volume = 0.6 }, -- esprits en rafale (spécial)
	Hit = { Id = "rbxassetid://9113572282", Volume = 0.8 }, -- impact lourd
	Burst = { Id = "rbxassetid://9118883081", Volume = 0.6 }, -- éclat élémentaire
	-- Monde
	Splash = { Id = "", Volume = 0.6 },
	Hurt = { Id = "rbxassetid://9113572282", Volume = 0.5, Pitch = 1.2 },
}

-- Ambiances 3D : Center (x, z) et hauteur Y, rayon d'écoute en studs.
-- Night / Day : ne joue que la nuit (18 h - 6 h) ou le jour.
SoundData.Ambient = {
	{ Name = "Ville", Id = "", Center = Vector2.new(0, 0), Y = 10, Radius = 260, Volume = 0.35, Day = true },
	{ Name = "VilleNuit", Id = "", Center = Vector2.new(0, 0), Y = 10, Radius = 260, Volume = 0.35, Night = true },
	{ Name = "Marche", Id = "", Center = Vector2.new(0, 138), Y = 8, Radius = 60, Volume = 0.5, Day = true },
	{ Name = "Fontaine", Id = "", Center = Vector2.new(0, 138), Y = 4, Radius = 30, Volume = 0.5 },
	{ Name = "Forge", Id = "", Center = Vector2.new(-138, -36), Y = 6, Radius = 40, Volume = 0.6 },
	{ Name = "Jardin", Id = "", Center = Vector2.new(91, 140), Y = 6, Radius = 35, Volume = 0.5, Day = true },
	{ Name = "Colisee", Id = "", Center = Vector2.new(142, 0), Y = 12, Radius = 70, Volume = 0.5 },
	{ Name = "Autel", Id = "", Center = Vector2.new(0, 0), Y = 10, Radius = 60, Volume = 0.4 },
	{ Name = "Vent", Id = "", Center = Vector2.new(0, 0), Y = 170, Radius = 700, Volume = 0.5 },
}

return SoundData
