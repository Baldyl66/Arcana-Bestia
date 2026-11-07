-- Conversations des PNJ du village : chaque PNJ propose des choix qui
-- déclenchent une action validée par le serveur.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local CardsData = require(Configs:WaitForChild("CardsData"))
local VillageData = require(Configs:WaitForChild("VillageData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local NpcDialogues = {}

type Context = {
	Dialogue: any,
	Invoke: (action: string, arg: any?) -> any,
	ShowResults: (results: { any }) -> (),
	Toast: (text: string, color: Color3?) -> (),
}

local function goodbye(ctx: Context)
	return { Text = "Au revoir", Callback = function()
		ctx.Dialogue:Close()
	end }
end

local talkTo

local function elya(ctx: Context, npc)
	local shop = VillageData.Shop
	local function main(text: string)
		ctx.Dialogue:Open(npc, text, {
			{ Text = string.format("Lot de %d boosters  •  %d ◆", shop.BundleCount, shop.BundlePrice), Style = "Gold", Callback = function()
				local result = ctx.Invoke("BuyBundle")
				if result and result.ok then
					ctx.Dialogue:Close()
					ctx.ShowResults(result.results)
				else
					ctx.Dialogue:SetText((result and result.reason) or "Hmm, la transaction a échoué.")
				end
			end },
			{ Text = string.format("Booster élémentaire  •  %d ◆", shop.ElementPrice), Style = "Primary", Callback = function()
				local choices = {}
				for id, element in pairs(CardsData.Elements) do
					table.insert(choices, { Text = element.Label, Callback = function()
						local result = ctx.Invoke("BuyElement", id)
						if result and result.ok then
							ctx.Dialogue:Close()
							ctx.ShowResults(result.results)
						else
							ctx.Dialogue:SetText((result and result.reason) or "Hmm, la transaction a échoué.")
						end
					end })
				end
				table.sort(choices, function(a, b)
					return a.Text < b.Text
				end)
				table.insert(choices, { Text = "Retour", Callback = function()
					main(npc.Greeting)
				end })
				ctx.Dialogue:SetText("Choisis l'élément : la créature tirée sera forcément de ce type !")
				ctx.Dialogue:SetChoices(choices)
			end },
			goodbye(ctx),
		})
	end
	main(npc.Greeting)
end

local function borin(ctx: Context, npc, info)
	local dupes = info.Duplicates or {}
	local parts = {}
	for _, rarity in ipairs(CardsData.Rarities) do
		if (dupes[rarity.Id] or 0) > 0 then
			table.insert(parts, string.format("%s x%d", rarity.Label, dupes[rarity.Id]))
		end
	end
	local summary = #parts > 0 and ("Tes doublons : " .. table.concat(parts, ", ") .. ".")
		or "Tu n'as aucun doublon pour l'instant. Reviens après avoir ouvert quelques boosters !"

	local choices = {
		{ Text = string.format("Vendre tous mes doublons (x%.1f)", VillageData.SellBonus), Style = "Gold", Callback = function()
			local result = ctx.Invoke("SellDuplicates")
			if result and result.ok then
				ctx.Toast(string.format("Doublons vendus : +%d ◆", result.amount), UIKit.Colors.Gold)
				talkTo(ctx, "Borin")
			else
				ctx.Dialogue:SetText((result and result.reason) or "Le creuset refuse de coopérer...")
			end
		end },
	}
	local cost = VillageData.FusionCost
	for index, rarity in ipairs(CardsData.Rarities) do
		local nextRarity = CardsData.Rarities[index + 1]
		if nextRarity then
			local have = dupes[rarity.Id] or 0
			table.insert(choices, {
				Text = string.format("Fusion : %d %s en 1 %s  (%d/%d)", cost, rarity.Label, nextRarity.Label, math.min(have, cost), cost),
				Style = have >= cost and "Primary" or "Ghost",
				Dimmed = have < cost,
				Callback = function()
					local result = ctx.Invoke("Fuse", rarity.Id)
					if result and result.ok then
						ctx.Dialogue:Close()
						ctx.ShowResults(result.results)
					else
						ctx.Dialogue:SetText((result and result.reason) or "La fusion a échoué.")
					end
				end,
			})
		end
	end
	table.insert(choices, goodbye(ctx))
	ctx.Dialogue:Open(npc, npc.Greeting .. "\n" .. summary, choices)
end

local function orin(ctx: Context, npc, info)
	local function show(quests, text: string)
		local choices = {}
		local ready, done = 0, 0
		for _, quest in ipairs(quests) do
			if quest.Claimed then
				done += 1
			end
			local label, style, dimmed
			if quest.Claimed then
				label = string.format("Terminée : %s", quest.Text)
				style, dimmed = "Ghost", true
			elseif quest.Done then
				ready += 1
				label = string.format("Réclamer : %s  (+%d ◆)", quest.Text, quest.Reward)
				style = "Gold"
			else
				label = string.format("%s  %d/%d  (+%d ◆)", quest.Text, quest.Progress, quest.Goal, quest.Reward)
				style = "Ghost"
			end
			table.insert(choices, { Text = label, Style = style, Dimmed = dimmed, Callback = function()
				if quest.Claimed then
					ctx.Dialogue:SetText("Tu as déjà accompli cette épreuve. Je suis fier de toi.")
				elseif not quest.Done then
					ctx.Dialogue:SetText(string.format("« %s » : encore un effort, tu en es à %d sur %d.", quest.Text, quest.Progress, quest.Goal))
				else
					local result = ctx.Invoke("ClaimQuest", quest.Id)
					if result and result.ok then
						ctx.Toast(string.format("Quête accomplie : +%d ◆", result.amount), UIKit.Colors.Gold)
						show(result.quests, "Magnifique ! Voici ta récompense, tu l'as bien méritée.")
					else
						ctx.Dialogue:SetText((result and result.reason) or "...")
					end
				end
			end })
		end
		-- Les quêtes à réclamer en premier, les terminées à la fin.
		local order = { Gold = 1, Ghost = 2 }
		table.sort(choices, function(a, b)
			local ra = (order[a.Style] or 3) + (a.Dimmed and 2 or 0)
			local rb = (order[b.Style] or 3) + (b.Dimmed and 2 or 0)
			return ra < rb
		end)
		table.insert(choices, goodbye(ctx))
		ctx.Dialogue:Open(npc, string.format("%s\nÉpreuves accomplies : %d / %d%s", text, done, #quests,
			ready > 0 and string.format("  •  %d récompense(s) t'attend(ent) !", ready) or ""), choices)
	end
	show(info.Quests or {}, npc.Greeting)
end

local function selene(ctx: Context, npc)
	ctx.Dialogue:Open(npc, npc.Greeting, {
		{ Text = string.format("Booster mystique (Épique+)  •  %d ◆", VillageData.MysticPrice), Style = "Gold", Callback = function()
			local result = ctx.Invoke("BuyMystic")
			if result and result.ok then
				ctx.Dialogue:Close()
				ctx.ShowResults(result.results)
			else
				ctx.Dialogue:SetText((result and result.reason) or "Les cristaux restent silencieux...")
			end
		end },
		{ Text = "Qu'est-ce que cet endroit ?", Callback = function()
			ctx.Dialogue:SetText("Brumeval d'en bas. Nos ancêtres s'y sont cachés pendant la Grande Éclipse. Les cristaux attirent les bêtes rares : mes boosters ne contiennent que des Épiques et des Légendaires.")
		end },
		goodbye(ctx),
	})
end

local function varek(ctx: Context, npc)
	local function main(text: string)
		ctx.Dialogue:Open(npc, text, {
			{ Text = "Défier un joueur", Style = "Gold", Callback = function()
				local result = ctx.Invoke("DuelList")
				if not (result and result.ok) then
					ctx.Dialogue:SetText((result and result.reason) or "L'arène est fermée pour le moment.")
					return
				end
				if #result.players == 0 then
					ctx.Dialogue:SetText("Aucun autre dresseur n'est disponible pour le moment. Reviens quand l'arène sera plus animée !")
					return
				end
				local choices = {}
				for index, other in ipairs(result.players) do
					if index > 9 then
						break
					end
					table.insert(choices, { Text = other.Name, Style = "Primary", Callback = function()
						local invite = ctx.Invoke("DuelInvite", other.UserId)
						ctx.Dialogue:SetText((invite and (invite.message or invite.reason)) or "Le défi n'a pas pu être envoyé.")
					end })
				end
				table.insert(choices, { Text = "Retour", Callback = function()
					main(npc.Greeting)
				end })
				ctx.Dialogue:SetText("Qui veux-tu défier ? Ton adversaire recevra ton invitation et aura 20 secondes pour répondre.")
				ctx.Dialogue:SetChoices(choices)
			end },
			{ Text = "S'entraîner contre un bot", Style = "Primary", Callback = function()
				local result = ctx.Invoke("TrainingStart")
				if not (result and result.ok) then
					ctx.Dialogue:SetText((result and result.reason) or "L'entraînement n'a pas pu commencer.")
				end
			end },
			{ Text = "Comment se déroule un duel ?", Callback = function()
				ctx.Dialogue:SetText("Choisis trois créatures de ta collection, puis affrontez-vous chacun votre tour : Attaque et Garde remplissent ta jauge d'énergie ◆, que tu dépenses pour la capacité unique de ta créature : brûlure, poison, gel, bouclier, vol de vie... Tu peux aussi changer de créature pour profiter des éléments : Feu bat Nature, Nature bat Eau, Eau bat Feu. Entraîne-toi d'abord contre mon mannequin !")
			end },
			goodbye(ctx),
		})
	end
	main(npc.Greeting)
end

local function pip(ctx: Context, npc, info)
	ctx.Dialogue:Open(npc, npc.Greeting .. "\n" .. (info.Hint or ""), {
		{ Text = "Redis-moi où il est", Style = "Primary", Callback = function()
			talkTo(ctx, "Pip")
		end },
		{ Text = "Merci Pip !", Callback = function()
			ctx.Dialogue:Close()
		end },
	})
end

-- Quartiers ----------------------------------------------------------------

local function rhea(ctx: Context, npc)
	local info = ctx.Invoke("RheaInfo") or {}
	local status = info.done and "Tu as déjà relevé le défi aujourd'hui. Reviens demain, soldat !"
		or string.format("Défi du jour : remporte un entraînement et gagne %d ◆.", info.reward or VillageData.DailyDuelReward)
	ctx.Dialogue:Open(npc, npc.Greeting .. "\n" .. status, {
		{ Text = "Lancer l'entraînement", Style = "Gold", Callback = function()
			local result = ctx.Invoke("TrainingStart")
			if result and result.ok then
				ctx.Dialogue:Close()
			else
				ctx.Dialogue:SetText((result and result.reason) or "L'entraînement n'a pas pu commencer.")
			end
		end },
		{ Text = "Un conseil de combat ?", Callback = function()
			local tips = {
				"Garde quand ta capacité coûte cher : ça rapporte deux ◆ d'énergie d'un coup.",
				"Une créature faible contre l'adversaire ? Change-la ! Le bouton CHANGER montre qui est fort ou faible.",
				"Les étourdissements et le gel font sauter un tour entier. Garde-les pour un adversaire qui charge sa capacité.",
				"Le miroir de Tessaro renvoie la moitié du prochain coup : parfait contre les grosses attaques.",
				"Les coups qui percent ignorent la garde ET les boucliers.",
			}
			ctx.Dialogue:SetText(tips[math.random(1, #tips)])
		end },
		goodbye(ctx),
	})
end

local function oswin(ctx: Context, npc)
	local function show(text: string)
		local result = ctx.Invoke("StallList")
		if not (result and result.ok) then
			ctx.Dialogue:Open(npc, (result and result.reason) or "Mon étal est fermé pour l'instant.", { goodbye(ctx) })
			return
		end
		local choices = {}
		for _, item in ipairs(result.items) do
			local card = CardsData.CardById[item.Id]
			local rarity = CardsData.RarityById[card.Rarity]
			table.insert(choices, {
				Text = item.Sold and string.format("%s  •  VENDU", card.Name) or string.format("%s (%s)  •  %d ◆", card.Name, rarity.Label, item.Price),
				Style = item.Sold and "Ghost" or (rarity.Order >= 4 and "Gold" or "Primary"),
				Callback = function()
					if item.Sold then
						ctx.Dialogue:SetText("Celle-là est partie ! Reviens demain, mon étal change chaque jour.")
						return
					end
					local buy = ctx.Invoke("StallBuy", item.Id)
					if buy and buy.ok then
						ctx.Dialogue:Close()
						ctx.ShowResults(buy.results)
					else
						ctx.Dialogue:SetText((buy and buy.reason) or "La vente a échoué.")
					end
				end,
			})
		end
		table.insert(choices, goodbye(ctx))
		ctx.Dialogue:Open(npc, text, choices)
	end
	show(npc.Greeting .. "\nVoici l'étal du jour :")
end

local function maelis(ctx: Context, npc)
	local function show(text: string)
		local result = ctx.Invoke("SetsInfo") or {}
		local choices = {}
		for _, s in ipairs(result.sets or {}) do
			local complete = s.Owned >= s.Total
			local el = CardsData.Elements[s.Element]
			table.insert(choices, {
				Text = s.Claimed and string.format("%s  •  %d/%d  ✓", s.Label, s.Owned, s.Total)
					or string.format("%s  •  %d/%d%s", s.Label, s.Owned, s.Total, complete and ("  →  " .. (result.reward or 0) .. " ◆") or ""),
				Style = (complete and not s.Claimed) and "Gold" or "Ghost",
				Callback = function()
					if s.Claimed then
						ctx.Dialogue:SetText(string.format("La collection %s est déjà inscrite dans les archives. Bravo !", el.Label))
						return
					end
					local claim = ctx.Invoke("ClaimSet", s.Element)
					if claim and claim.ok then
						ctx.Toast(string.format("Collection %s complète : +%d ◆ !", el.Label, claim.gems), UIKit.Colors.Gold)
						show(string.format("Magnifique ! Toutes les créatures %s sont désormais archivées.", el.Label))
					else
						ctx.Dialogue:SetText((claim and claim.reason) or "Les archives sont fermées.")
					end
				end,
			})
		end
		table.insert(choices, goodbye(ctx))
		ctx.Dialogue:Open(npc, text, choices)
	end
	show(npc.Greeting)
end

local function gaelle(ctx: Context, npc)
	ctx.Dialogue:Open(npc, npc.Greeting, {
		{ Text = "Prendre le panier du jour", Style = "Gold", Callback = function()
			local result = ctx.Invoke("FarmBasket")
			if result and result.ok then
				ctx.Toast(string.format("Panier de Gaëlle : +%d ◆ !", result.gems), UIKit.Colors.Gold)
				ctx.Dialogue:SetText(string.format("Tiens, %d gemmes trouvées dans le foin ! Reviens demain, il y aura un nouveau panier.", result.gems))
			else
				ctx.Dialogue:SetText((result and result.reason) or "Le panier n'est pas encore prêt.")
			end
		end },
		goodbye(ctx),
	})
end

local function odile(ctx: Context, npc)
	local stories = {
		"On raconte que Nyxalith, la reine des éclipses, n'apparaît qu'aux dresseurs qui ont ouvert cent boosters... mais ce ne sont peut-être que des histoires.",
		"Quand j'étais petite, un Ignarax s'était posé sur le toit de la chapelle. Toute la ville avait accouru avec des seaux !",
		"Les cristaux de Sélène chantent plus fort la nuit. Les vieux disent que c'est là que les créatures rares se montrent.",
		"Le Cercle des Arcanes a été gravé bien avant les remparts. Ses six piliers retiennent la magie des éléments.",
	}
	local tips = {
		"Échange tes doublons au Comptoir des Échanges, sur la Grand-Place : installez-vous chacun sur un cercle de la même table.",
		"Oswin, aux entrepôts, vend chaque jour trois créatures choisies. Passe le voir !",
		"Maelis, aux archives du donjon, récompense ceux qui réunissent toutes les créatures d'un élément.",
		"Gaëlle, à la ferme, offre un panier de gemmes chaque jour. Il serait dommage de l'oublier !",
		"Approche-toi du Cercle des Arcanes pendant un duel : tu pourras le regarder en direct.",
	}
	ctx.Dialogue:Open(npc, npc.Greeting, {
		{ Text = "Raconte-moi une histoire", Style = "Primary", Callback = function()
			ctx.Dialogue:SetText(stories[math.random(1, #stories)])
		end },
		{ Text = "Un conseil ?", Callback = function()
			ctx.Dialogue:SetText(tips[math.random(1, #tips)])
		end },
		goodbye(ctx),
	})
end

function talkTo(ctx: Context, npcId: string)
	local npc = VillageData.Npcs[npcId]
	if npc == nil then
		return
	end
	local result = ctx.Invoke("Talk", npcId)
	local info = (result and result.ok and result.info) or {}
	if npcId == "Elya" then
		elya(ctx, npc)
	elseif npcId == "Borin" then
		borin(ctx, npc, info)
	elseif npcId == "Orin" then
		orin(ctx, npc, info)
	elseif npcId == "Pip" then
		pip(ctx, npc, info)
	elseif npcId == "Selene" then
		selene(ctx, npc)
	elseif npcId == "Varek" then
		varek(ctx, npc)
	elseif npcId == "Rhea" then
		rhea(ctx, npc)
	elseif npcId == "Oswin" then
		oswin(ctx, npc)
	elseif npcId == "Maelis" then
		maelis(ctx, npc)
	elseif npcId == "Gaelle" then
		gaelle(ctx, npc)
	elseif npcId == "Odile" then
		odile(ctx, npc)
	end
end

NpcDialogues.talkTo = talkTo

return NpcDialogues
