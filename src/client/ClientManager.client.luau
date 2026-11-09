-- Point d'entrée client : relie le menu d'accueil, le HUD, les panneaux,
-- l'ouverture de boosters et les contrôles (clavier, tactile, manette).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIFolder = script.Parent:WaitForChild("UI")
local UIKit = require(UIFolder:WaitForChild("UIKit"))
local MainMenu = require(UIFolder:WaitForChild("MainMenu"))
local HUD = require(UIFolder:WaitForChild("HUD"))
local Hotbar = require(UIFolder:WaitForChild("Hotbar"))
Hotbar.Init()
local Reveal = require(UIFolder:WaitForChild("Reveal"))
local Panels = require(UIFolder:WaitForChild("Panels"))
local Dialogue = require(UIFolder:WaitForChild("Dialogue"))
local NpcDialogues = require(UIFolder:WaitForChild("NpcDialogues"))
local WorldFX = require(UIFolder:WaitForChild("WorldFX"))
local Animals = require(UIFolder:WaitForChild("Animals"))
local BoosterFX = require(UIFolder:WaitForChild("BoosterFX"))
local PropsFX = require(UIFolder:WaitForChild("PropsFX"))
local Tutorial = require(UIFolder:WaitForChild("Tutorial"))
local DailyRewards = require(UIFolder:WaitForChild("DailyRewards"))
local DuelInvite = require(UIFolder:WaitForChild("DuelInvite"))
local Shop = require(UIFolder:WaitForChild("Shop"))
local DuelScreen = require(UIFolder:WaitForChild("DuelScreen"))
local Trade = require(UIFolder:WaitForChild("Trade"))
local Spectator = require(UIFolder:WaitForChild("Spectator"))
local Music = require(UIFolder:WaitForChild("Music"))
local BoosterMenu = require(UIFolder:WaitForChild("BoosterMenu"))
local WorldMap = require(UIFolder:WaitForChild("WorldMap"))
local BookController = require(script.Parent:WaitForChild("BookController"))
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local OpenBooster: RemoteFunction = Remotes:WaitForChild("OpenBooster")
local GetProfile: RemoteFunction = Remotes:WaitForChild("GetProfile")
local ClaimDaily: RemoteFunction = Remotes:WaitForChild("ClaimDaily")
local ProfileChanged: RemoteEvent = Remotes:WaitForChild("ProfileChanged")
local NpcAction: RemoteFunction = Remotes:WaitForChild("NpcAction")
local Notify: RemoteEvent = Remotes:WaitForChild("Notify")
local DuelEvent: RemoteEvent = Remotes:WaitForChild("DuelEvent")
local PurchaseGranted: RemoteEvent = Remotes:WaitForChild("PurchaseGranted")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = UIKit.new("ScreenGui", {
	Name = "ArcanaUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
	Parent = playerGui,
})

-- Supprime l'ancienne interface (v0.1) si elle traîne encore dans le place.
local function removeLegacyUI(child: Instance)
	if child.Name == "BoosterUI" and child:IsA("ScreenGui") then
		child:Destroy()
	end
end
for _, child in ipairs(playerGui:GetChildren()) do
	removeLegacyUI(child)
end
playerGui.ChildAdded:Connect(removeLegacyUI)

local state = "Menu" -- "Menu" | "Game"

-- L'invite de l'autel n'apparaît qu'en jeu, pas derrière le menu.
local function updatePrompts()
	for _, prompt in ipairs(workspace:GetDescendants()) do
		if prompt:IsA("ProximityPrompt") then
			prompt.Enabled = state == "Game"
		end
	end
end
workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		descendant.Enabled = state == "Game"
	end
end)
local profile = nil
local requesting = false

-------------------------------------------------------------------------------
-- Contrôles du personnage
-------------------------------------------------------------------------------
local controls = nil
task.spawn(function()
	local ok, playerModule = pcall(function()
		local scripts = player:WaitForChild("PlayerScripts", 10)
		local module = scripts and scripts:WaitForChild("PlayerModule", 10)
		if not module then
			error("PlayerModule introuvable dans PlayerScripts")
		end
		return require(module)
	end)
	if ok and playerModule then
		controls = playerModule:GetControls()
		if state ~= "Game" then
			controls:Disable()
		end
	else
		warn("[ClientManager] Contrôles Roblox indisponibles :", playerModule)
	end
end)

local function setControlsEnabled(enabled: boolean)
	if controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

local function setCoreGui(enabled: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, enabled)
		-- Sac à dos Roblox remplacé par la barre d'objets d'Arcana.
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	Hotbar.SetVisible(enabled)
end

-------------------------------------------------------------------------------
-- Secousse de caméra
-------------------------------------------------------------------------------
local shakeUntil, shakeIntensity = 0, 0
RunService:BindToRenderStep("ArcanaShake", Enum.RenderPriority.Camera.Value + 2, function()
	local now = os.clock()
	if now < shakeUntil and UIKit.Settings.Shake then
		local fade = (shakeUntil - now)
		local i = shakeIntensity * math.min(fade * 2, 1)
		local camera = workspace.CurrentCamera
		camera.CFrame *= CFrame.Angles(
			math.rad((math.random() - 0.5) * i * 2),
			math.rad((math.random() - 0.5) * i * 2),
			math.rad((math.random() - 0.5) * i)
		)
	end
end)

local function shake(intensity: number, duration: number)
	shakeIntensity = intensity
	shakeUntil = os.clock() + duration
end

-------------------------------------------------------------------------------
-- Interface
-------------------------------------------------------------------------------
local menu, hud, reveal, dialogue
local revealQueue = {}
local currentNpc: string? = nil
local collectionPanel, settingsPanel, helpPanel
local panels = {}
local tutorialPanel
local dailyPanel
local shopPanel
local boosterMenu
local mapPanel
local tradeUI

-------------------------------------------------------------------------------
-- Course : Maj (maintenir), L3 (bascule) ou bouton tactile « Courir ».
-------------------------------------------------------------------------------
local WALK_SPEED, RUN_SPEED = 20, 32
local sprinting = false

local function setSprint(on: boolean)
	sprinting = on
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = on and RUN_SPEED or WALK_SPEED
	end
	local camera = workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Custom then
		TweenService:Create(camera, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { FieldOfView = on and 80 or 70 }):Play()
	end
end

local function sprintAction(_, inputState: Enum.UserInputState, input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		-- Clavier : courir tant que la touche est maintenue.
		if inputState == Enum.UserInputState.Begin then
			setSprint(true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			setSprint(false)
		end
	elseif inputState == Enum.UserInputState.Begin then
		-- Manette et tactile : bascule.
		setSprint(not sprinting)
	end
	return Enum.ContextActionResult.Pass
end

local function bindSprint(enabled: boolean)
	if enabled then
		ContextActionService:BindAction("ArcanaSprint", sprintAction, true,
			Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
		ContextActionService:SetTitle("ArcanaSprint", "Courir")
		ContextActionService:SetPosition("ArcanaSprint", UDim2.new(1, -170, 1, -75))
	else
		ContextActionService:UnbindAction("ArcanaSprint")
		setSprint(false)
	end
end

player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = sprinting and RUN_SPEED or WALK_SPEED
end)

local function closePanels()
	for _, panel in ipairs(panels) do
		panel:Close()
	end
end

local function openPanel(panel)
	for _, other in ipairs(panels) do
		if other ~= panel then
			other:Close()
		end
	end
	panel:Open()
end

local function anyPanelOpen(): boolean
	for _, panel in ipairs(panels) do
		if panel.IsOpen then
			return true
		end
	end
	return false
end

local function refocus()
	-- Après fermeture d'un panneau, on rend la main au jeu ou au menu.
	if state == "Menu" and menu.Ready then
		UIKit.focus(menu.PlayButton)
	else
		GuiService.SelectedObject = nil
	end
end

local function setProfile(newProfile)
	if newProfile == nil then
		return
	end
	local previousReady = profile and profile.QuestsReady
	profile = newProfile
	hud:SetProfile(profile)
	if tradeUI then
		tradeUI:Refresh()
	end
	if shopPanel then
		shopPanel:SetProfile(profile)
	end
	if dailyPanel then
		dailyPanel:SetProfile(profile)
	end
	if previousReady and (newProfile.QuestsReady or 0) > previousReady then
		hud:Toast("Épreuve accomplie !", UIKit.Colors.Gold)
	end
	collectionPanel:SetProfile(profile)
	if boosterMenu then
		boosterMenu:SetProfile(profile)
	end
	BookController.SetProfile(profile)
end

local function toast(text: string, color: Color3?)
	hud:Toast(text, color)
end

-- Achat d'un booster (3 cartes) auprès du serveur ; renvoie le résultat ou nil.
local function requestBooster()
	if requesting or profile == nil then
		return nil
	end
	if profile.Coins < CardsData.Economy.BoosterPrice then
		toast("Pas assez de gemmes ! Reviens plus tard ou récupère ton cadeau.", UIKit.Colors.Danger)
		return nil
	end
	requesting = true
	local ok, result = pcall(OpenBooster.InvokeServer, OpenBooster)
	requesting = false
	if not ok or type(result) ~= "table" or not result.ok then
		toast((ok and type(result) == "table" and result.reason) or "Le booster n'a pas pu être ouvert.", UIKit.Colors.Danger)
		return nil
	end
	setProfile(result.profile)
	return result
end

-- L'autel ouvre le menu du booster (booster 3D, ouverture, 3 cartes).
local function openBooster()
	if state ~= "Game" or reveal.Busy or not boosterMenu then
		return
	end
	if boosterMenu.IsOpen then
		return
	end
	openPanel(boosterMenu)
end

-- Révèle une liste de cartes l'une après l'autre (lots, fusion...).
local function showResults(results: { any })
	if #results == 0 then
		return
	end
	revealQueue = table.clone(results)
	local first = table.remove(revealQueue, 1)
	reveal:Reset()
	task.spawn(reveal.Play, reveal, first)
end

local function claimDaily()
	local ok, result = pcall(ClaimDaily.InvokeServer, ClaimDaily)
	if ok and type(result) == "table" and result.ok then
		-- Les gemmes partent du bouton du panneau, ou du centre de l'écran (carnet).
		local button = dailyPanel.ClaimButton
		local from = if dailyPanel.IsOpen then button.AbsolutePosition + button.AbsoluteSize / 2 else workspace.CurrentCamera.ViewportSize / 2
		dailyPanel:SetProfile(result.profile)
		dailyPanel:Close()
		if result.coins > 0 then
			hud:FlyGems(from, result.coins)
		end
		setProfile(result.profile)
		if result.coins > 0 then
			toast(string.format("Récompense du jour %d : +%d ◆", result.day, result.coins), UIKit.Colors.Gold)
		end
		if #result.results > 0 then
			task.delay(0.6, function()
				showResults(result.results)
			end)
		end
	else
		toast((ok and type(result) == "table" and result.reason) or "Réessaie dans un instant.", UIKit.Colors.Danger)
	end
end

local function waitForCharacter(): Model
	return player.Character or player.CharacterAdded:Wait()
end

local function enterGame()
	if state == "Game" or not menu.Ready then
		return
	end
	state = "Game"
	closePanels()
	menu:Hide()

	local character = waitForCharacter()
	local humanoid = character:WaitForChild("Humanoid")
	local camera = workspace.CurrentCamera
	camera.CameraSubject = humanoid
	camera.CameraType = Enum.CameraType.Custom

	setControlsEnabled(true)
	setCoreGui(true)
	updatePrompts()
	GuiService.SelectedObject = nil
	hud:Show()
	bindSprint(true)
	Music.play("Explore")
	toast("Bienvenue dans le Sanctuaire !", UIKit.Colors.Gold)
	task.delay(0.8, function()
		if state ~= "Game" or not profile then
			return
		end
		if not profile.TutorialSeen then
			openPanel(tutorialPanel)
		elseif profile.DailyAvailable then
			openPanel(dailyPanel)
		end
	end)
end

local function backToMenu()
	if state == "Menu" then
		return
	end
	state = "Menu"
	closePanels()
	if reveal.IsOpen then
		reveal:Close()
	end
	dialogue:Close()
	setControlsEnabled(false)
	setCoreGui(false)
	updatePrompts()
	bindSprint(false)
	hud:Hide()
	menu:Show()
	Music.play("Menu")
end

menu = MainMenu.new(gui, {
	Play = enterGame,
	Collection = function()
		openPanel(collectionPanel)
	end,
	Settings = function()
		openPanel(settingsPanel)
	end,
	Help = function()
		openPanel(helpPanel)
	end,
})

hud = HUD.new(gui, {
	Collection = function()
		openPanel(collectionPanel)
	end,
	Help = function()
		openPanel(tutorialPanel)
	end,
	Menu = backToMenu,
	Daily = function()
		openPanel(dailyPanel)
	end,
	Shop = function()
		openPanel(shopPanel)
	end,
	Map = function()
		openPanel(mapPanel)
	end,
})

reveal = Reveal.new(gui, {
	OpenAgain = function()
		revealQueue = {}
		openBooster()
	end,
	Closed = function()
		if #revealQueue > 0 then
			local nextResult = table.remove(revealQueue, 1)
			task.delay(0.3, function()
				reveal:Reset()
				reveal:Play(nextResult)
			end)
		else
			refocus()
		end
	end,
	Shake = shake,
})

dialogue = Dialogue.new(gui)
dialogue.OnClose = function()
	currentNpc = nil
	refocus()
end

local npcContext = {
	Dialogue = dialogue,
	Invoke = function(action: string, arg: any?)
		local ok, result = pcall(NpcAction.InvokeServer, NpcAction, action, arg)
		if not ok or type(result) ~= "table" then
			return { ok = false, reason = "Le villageois ne t'entend pas..." }
		end
		if result.profile then
			setProfile(result.profile)
		end
		return result
	end,
	ShowResults = showResults,
	Toast = function(text: string, color: Color3?)
		hud:Toast(text, color)
	end,
}

local function talkTo(npcId: string)
	if state ~= "Game" or reveal.IsOpen then
		return
	end
	closePanels()
	currentNpc = npcId
	task.spawn(NpcDialogues.talkTo, npcContext, npcId)
end

collectionPanel = Panels.collection(gui)
settingsPanel = Panels.settings(gui, function()
	UIKit.refreshScale()
end)
helpPanel = Panels.help(gui)
for _, panel in ipairs({ collectionPanel, settingsPanel, helpPanel }) do
	panel.OnClose = refocus
end

tutorialPanel = Tutorial.new(gui, function()
	refocus()
	if profile and not profile.TutorialSeen then
		profile.TutorialSeen = true
		task.spawn(NpcAction.InvokeServer, NpcAction, "TutorialDone")
		-- Après le tout premier tutoriel, on enchaîne sur la récompense du jour.
		if profile.DailyAvailable then
			task.delay(0.4, function()
				if state == "Game" then
					openPanel(dailyPanel)
				end
			end)
		end
	end
end)
dailyPanel = DailyRewards.new(gui, claimDaily)
dailyPanel.OnClose = refocus
shopPanel = Shop.new(gui, function(text: string, color: Color3?)
	hud:Toast(text, color)
end)
shopPanel.OnClose = refocus
shopPanel:SetProfile(profile)
mapPanel = WorldMap.panel(gui, function(id: string)
	local ok, result = pcall(NpcAction.InvokeServer, NpcAction, "Teleport", id)
	if ok and type(result) == "table" and result.ok then
		mapPanel:Close()
		hud:Toast("Téléportation : " .. tostring(result.message), UIKit.Colors.Gold)
	else
		hud:Toast((ok and type(result) == "table" and result.reason) or "Téléportation impossible.", UIKit.Colors.Danger)
	end
end)
mapPanel.OnClose = refocus
boosterMenu = BoosterMenu.new(gui, { Open = requestBooster, Shake = shake })
boosterMenu:SetProfile(profile)
-- Écran du booster épuré : HUD, barre d'objets et invites de l'autel masqués.
do
	local baseOpen = boosterMenu.Open
	function boosterMenu:Open()
		baseOpen(self)
		hud:Hide()
		setCoreGui(false)
		game:GetService("ProximityPromptService").Enabled = false
	end
end
boosterMenu.OnClose = function()
	game:GetService("ProximityPromptService").Enabled = true
	if state == "Game" then
		hud:Show()
		setCoreGui(true)
	end
	refocus()
end
panels = { collectionPanel, settingsPanel, helpPanel, tutorialPanel, dailyPanel, shopPanel, mapPanel, boosterMenu }
-- Boutons du carnet. Les chapitres changent la page de droite dans le livre
-- (sans panneau) ; seul le booster Arcana referme le livre pour l'ouvrir.
local MarketplaceService = game:GetService("MarketplaceService")
local ShopData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ShopData"))
local bookActions = {
	Boosters = function()
		BookController.Close()
		openBooster()
	end,
	ClaimDaily = function()
		claimDaily()
	end,
	Elya = function()
		toast("Elya vend ces boosters à sa boutique, sur la Grand-Place (au sud).", UIKit.Colors.Gold)
	end,
	Selene = function()
		toast("Sélène vend le booster mystique dans son sanctuaire, au quartier des Mages (au nord).", UIKit.Colors.Gold)
	end,
}
BookController.Init(function() end, function() end, function(action: string)
	local packId = action:match("^Buy:(.+)$")
	if packId then
		for _, pack in ipairs(ShopData.GemPacks) do
			if pack.Id == packId then
				if pack.ProductId == 0 then
					toast("Cette offre arrive bientôt !", UIKit.Colors.Gold)
				else
					MarketplaceService:PromptProductPurchase(player, pack.ProductId)
				end
			end
		end
		return
	end
	local run = bookActions[action]
	if run then
		run()
	end
end)

-- Achat Robux validé par le serveur : gemmes qui volent et cartes révélées.
PurchaseGranted.OnClientEvent:Connect(function(data)
	shopPanel:Close()
	hud:Toast("Merci pour ton achat : " .. tostring(data.Name) .. " !", UIKit.Colors.Gold)
	if data.Gems and data.Gems > 0 then
		local camera = workspace.CurrentCamera
		local center = camera and camera.ViewportSize / 2 or Vector2.new(400, 300)
		hud:FlyGems(center, data.Gems)
	end
	if data.Results and #data.Results > 0 then
		task.delay(1.2, function()
			showResults(data.Results)
		end)
	end
end)

-------------------------------------------------------------------------------
-- Entrées
-------------------------------------------------------------------------------
local function handleBack(): boolean
	if dialogue.IsOpen then
		dialogue:Close()
		return true
	end
	if collectionPanel.IsOpen and collectionPanel:HandleBack() then
		return true
	end
	if anyPanelOpen() then
		closePanels()
		return true
	end
	if reveal.IsOpen then
		reveal:Close()
		return true
	end
	return false
end

UserInputService.InputBegan:Connect(function(input, processed)
	local key = input.KeyCode
	if key == Enum.KeyCode.ButtonB then
		handleBack()
		return
	end
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end

	if state == "Game" then
		if key == Enum.KeyCode.B or key == Enum.KeyCode.ButtonR1 then
			if reveal.IsOpen then
				if not reveal.Busy then
					openBooster()
				end
			else
				openBooster()
			end
		end
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "BoosterPrompt" then
		openBooster()
	elseif prompt.Name == "ShopPrompt" then
		openPanel(shopPanel)
	elseif prompt:GetAttribute("NpcId") then
		talkTo(prompt:GetAttribute("NpcId"))
	end
end)

-- Ferme le dialogue si le joueur s'éloigne du PNJ.
RunService.Heartbeat:Connect(function()
	if not (dialogue.IsOpen and currentNpc) then
		return
	end
	local world = workspace:FindFirstChild("World")
	local npcs = world and world:FindFirstChild("NPCs")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (npcs and root) then
		return
	end
	-- Plusieurs PNJ peuvent partager un id (un Varek par zone d'arènes) : on
	-- mesure la distance au plus proche, sinon le dialogue se refermait aussitôt.
	local nearest = math.huge
	for _, npc in ipairs(npcs:GetChildren()) do
		if npc:GetAttribute("NpcId") == currentNpc or npc.Name == currentNpc then
			nearest = math.min(nearest, (npc:GetPivot().Position - root.Position).Magnitude)
		end
	end
	if nearest ~= math.huge and nearest > 20 then
		dialogue:Close()
	end
end)

local NOTIFY_COLORS = {
	Gold = UIKit.Colors.Gold,
	Info = UIKit.Colors.Text,
	Danger = UIKit.Colors.Danger,
}
-- Duels : invitation reçue, écran VS, combat de cartes et fin.
local duelScreen = DuelScreen.new(gui, {
	Act = function(action: string)
		local ok, result = pcall(NpcAction.InvokeServer, NpcAction, "DuelAction", action)
		if ok and type(result) == "table" and not result.ok and result.reason then
			hud:Toast(result.reason, UIKit.Colors.Danger)
		end
	end,
	Pick = function(ids: { string }): boolean
		local ok, result = pcall(NpcAction.InvokeServer, NpcAction, "DuelPick", ids)
		return ok and type(result) == "table" and result.ok == true
	end,
	Shake = shake,
})
local duelInvite = DuelInvite.new(gui, function(fromId: number, accept: boolean)
	local ok, result = pcall(NpcAction.InvokeServer, NpcAction, "DuelRespond", { FromId = fromId, Accept = accept })
	if ok and type(result) == "table" and not result.ok and result.reason then
		hud:Toast(result.reason, UIKit.Colors.Danger)
	end
end)
-- Pendant un duel, l'interface du jeu (gemmes, carte, barre d'objets) s'efface.
local inDuelScreen = false
local function setDuelMode(on: boolean)
	if on == inDuelScreen then
		return
	end
	inDuelScreen = on
	if on then
		hud:Hide()
		setCoreGui(false)
	elseif state == "Game" then
		hud:Show()
		setCoreGui(true)
	end
end
-- Échanges entre joueurs (invite « Échanger » près des autres joueurs).
tradeUI = Trade.new(gui, UIKit.panel, {
	GetProfile = function()
		return profile
	end,
	Toast = toast,
	CanTrade = function()
		return state == "Game" and not inDuelScreen
	end,
})
table.insert(panels, tradeUI.Panel)

-- Spectateurs des duels du Cercle des Arcanes.
local spectator = Spectator.new(toast)

DuelEvent.OnClientEvent:Connect(function(kind: string, data)
	if kind:sub(1, 4) == "Spec" then
		if not inDuelScreen then
			spectator:Handle(kind, data)
		end
		return
	end
	if kind == "Select" or kind == "Start" then
		spectator:Stop()
	end
	if kind == "Select" or kind == "Start" then
		setDuelMode(true)
		Music.play("Duel")
	elseif kind == "End" then
		setDuelMode(false)
		Music.play(state == "Game" and "Explore" or "Menu")
	end
	if kind == "Invite" then
		duelInvite:Show(data)
	elseif kind == "Select" then
		dialogue:Close()
		closePanels()
		duelScreen:Select(data)
	elseif kind == "OppReady" then
		duelScreen:OppReady()
	elseif kind == "Start" then
		dialogue:Close()
		closePanels()
		task.spawn(duelScreen.Start, duelScreen, data)
	elseif kind == "Turn" then
		duelScreen:Turn(data)
	elseif kind == "Resolve" then
		duelScreen:Resolve(data)
	elseif kind == "Result" then
		duelScreen:Result(data)
	elseif kind == "End" then
		duelScreen:Close()
	end
end)

Notify.OnClientEvent:Connect(function(text: string, kind: string?)
	hud:Toast(text, NOTIFY_COLORS[kind or "Info"])
end)

task.spawn(Animals.start)
task.spawn(PropsFX.start)
task.spawn(function()
	local ok, err = pcall(BoosterFX.startDisplay)
	if not ok then
		warn("[BoosterFX] Présentoir de l'autel impossible :", err)
	end
end)
task.spawn(WorldFX.start, function()
	return profile and profile.QuestsReady or 0
end)

-------------------------------------------------------------------------------
-- Démarrage
-------------------------------------------------------------------------------
setCoreGui(false)
updatePrompts()
menu.Root.Visible = false
menu:StartCinematic()

local function updateWorldState()
	menu:SetProgress(workspace:GetAttribute("WorldProgress") or 0)
	if workspace:GetAttribute("WorldReady") then
		menu:SetReady()
	end
end
workspace:GetAttributeChangedSignal("WorldProgress"):Connect(updateWorldState)
workspace:GetAttributeChangedSignal("WorldReady"):Connect(updateWorldState)
updateWorldState()

ProfileChanged.OnClientEvent:Connect(setProfile)
task.spawn(function()
	local ok, result = pcall(GetProfile.InvokeServer, GetProfile)
	if ok then
		setProfile(result)
	end
end)

-- L'écran de chargement (ReplicatedFirst/ArcanaLoading) signale la fin du
-- chargement : le menu apparaît juste après.
local loadingScreen = game:GetService("ReplicatedFirst"):FindFirstChild("ArcanaLoading")
	or playerGui:WaitForChild("ArcanaLoading", 3)
if loadingScreen and not player:GetAttribute("ArcanaLoaded") then
	player:GetAttributeChangedSignal("ArcanaLoaded"):Wait()
end
menu:Show()
Music.play("Menu")

player.CharacterAdded:Connect(function()
	if state == "Menu" then
		setControlsEnabled(false)
	end
end)
