-- Échange entre joueurs, au Comptoir des Échanges (Grand-Place) : deux
-- joueurs sur les cercles d'une même table ouvrent la fenêtre d'échange (deux offres face à face, ta
-- collection en bas, gemmes, Prêt → compte à rebours → Confirmer).
-- Toute la logique et les vérifications sont côté serveur (Trade.server).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local CardView = require(script.Parent:WaitForChild("CardView"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TradeAction: RemoteFunction = Remotes:WaitForChild("TradeAction")
local TradeEvent: RemoteEvent = Remotes:WaitForChild("TradeEvent")

local GOLD = Color3.fromRGB(255, 215, 120)
local CREAM = Color3.fromRGB(255, 244, 220)
local GREEN = Color3.fromRGB(110, 230, 150)
local RED = Color3.fromRGB(255, 95, 110)
local INK = Color3.fromRGB(14, 10, 24)

local Trade = {}
Trade.__index = Trade

type Callbacks = {
	GetProfile: () -> any,
	Toast: (string, Color3?) -> (),
	CanTrade: () -> boolean,
}

local function invoke(kind: string, arg: any)
	local ok, result = pcall(TradeAction.InvokeServer, TradeAction, kind, arg)
	return ok and result or { ok = false }
end

local function sortedIds(cards: { [string]: number }): { string }
	local ids = {}
	for id in pairs(cards) do
		if CardsData.CardById[id] then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		local ca, cb = CardsData.CardById[a], CardsData.CardById[b]
		local ra, rb = CardsData.RarityById[ca.Rarity].Order, CardsData.RarityById[cb.Rarity].Order
		if ra ~= rb then
			return ra > rb
		end
		return ca.Name < cb.Name
	end)
	return ids
end

-- Tuile : carte + pastille du nombre d'exemplaires.
local function tile(parent: Instance, id: string, count: number, order: number, onClick: (() -> ())?): GuiObject
	local card = CardsData.CardById[id]
	local holder = UIKit.new(onClick and "TextButton" or "Frame", { BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	if onClick then
		holder.Text = ""
		holder.AutoButtonColor = false
		holder.Activated:Connect(function()
			UIKit.playSound("Click", 0.4, 1.2)
			onClick()
		end)
	end
	CardView.create(card, { Parent = holder })
	if count > 1 then
		local badge = UIKit.label({ Text = "×" .. count, Font = UIKit.Fonts.Black, TextColor3 = CREAM, AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 2, 1, 2), Size = UDim2.fromOffset(34, 22), BackgroundTransparency = 0, BackgroundColor3 = INK, ZIndex = 20,
			Parent = holder }, 15)
		UIKit.corner(badge, 8)
		UIKit.stroke(badge, GOLD, 1.5, 0)
	end
	return holder
end

local function grid(parent: Instance, props): ScrollingFrame
	props.BackgroundColor3 = Color3.fromRGB(10, 8, 20)
	props.BackgroundTransparency = 0.35
	props.BorderSizePixel = 0
	props.ScrollBarThickness = 6
	props.ScrollBarImageColor3 = GOLD
	props.AutomaticCanvasSize = props.Horizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y
	props.CanvasSize = UDim2.new()
	props.ScrollingDirection = props.Horizontal and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y
	local horizontal = props.Horizontal
	props.Horizontal = nil
	props.Parent = parent
	local frame = UIKit.new("ScrollingFrame", props)
	UIKit.corner(frame, 10)
	UIKit.padding(frame, 8)
	UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(72, 105), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = horizontal and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal, Parent = frame })
	return frame
end

function Trade.new(gui: Instance, panelFactory, callbacks: Callbacks)
	local self = setmetatable({}, Trade)
	self.Callbacks = callbacks
	self.State = nil

	---------------------------------------------------------------------------
	-- Fenêtre d'échange
	---------------------------------------------------------------------------
	local panel = panelFactory(gui, "ÉCHANGE")
	self.Panel = panel
	local content = panel.Content
	local baseClose = panel.Close
	function panel.Close(p)
		if self.State then
			invoke("Cancel")
		end
		baseClose(p)
	end

	self.Status = UIKit.label({ Text = "", RichText = true, Font = UIKit.Fonts.Bold, TextColor3 = CREAM, Size = UDim2.new(1, 0, 0, 24), Parent = content }, 18)
	self.Sides = {}
	for i, key in ipairs({ "Mine", "Theirs" }) do
		local col = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new((i - 1) * 0.505, 0, 0, 30), Size = UDim2.new(0.495, 0, 0.5, -30), Parent = content })
		local header = UIKit.label({ Text = key == "Mine" and "TON OFFRE" or "SON OFFRE", RichText = true, Font = UIKit.Fonts.Black, TextColor3 = GOLD,
			Size = UDim2.new(1, -120, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, Parent = col }, 18)
		local chip = UIKit.label({ Text = "", Font = UIKit.Fonts.Black, TextColor3 = INK, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(112, 24), BackgroundTransparency = 0, BackgroundColor3 = GREEN, Visible = false, Parent = col }, 14)
		UIKit.corner(chip, 12)
		local gems = UIKit.label({ Text = "◆ 0", Font = UIKit.Fonts.Black, TextColor3 = Color3.fromRGB(130, 215, 255), Position = UDim2.fromOffset(0, 26),
			Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = col }, 18)
		local list = grid(col, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52) })
		local stroke = UIKit.stroke(list, key == "Mine" and Color3.fromRGB(70, 140, 255) or Color3.fromRGB(235, 70, 80), 2, 0.3)
		self.Sides[key] = { Header = header, Chip = chip, Gems = gems, List = list, Stroke = stroke }
	end

	UIKit.label({ Text = "TA COLLECTION  ·  touche une carte pour l'ajouter, touche-la dans ton offre pour la retirer", Font = UIKit.Fonts.Bold,
		TextColor3 = UIKit.Colors.SubText, Position = UDim2.new(0, 0, 0.5, 6), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content }, 15)
	self.Collection = grid(content, { Horizontal = true, Position = UDim2.new(0, 0, 0.5, 30), Size = UDim2.new(1, 0, 0.5, -110) })

	-- Gemmes et boutons.
	local bar = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 70),
		Parent = content })
	local gemsRow = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.45, 0, 1, 0), Parent = bar })
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = gemsRow })
	local function gemButton(text: string, delta: number, order: number)
		UIKit.button({ Text = text, Style = "Ghost", Size = UDim2.new(0.17, 0, 0, 52), TextSize = 16, LayoutOrder = order, Parent = gemsRow, Callback = function()
			local s = self.State
			if s then
				invoke("SetGems", math.max(0, s.Mine.Gems + delta))
			end
		end })
	end
	gemButton("-100", -100, 1)
	gemButton("-10", -10, 2)
	self.GemLabel = UIKit.label({ Text = "◆ 0", Font = UIKit.Fonts.Black, TextColor3 = Color3.fromRGB(130, 215, 255), Size = UDim2.new(0.28, 0, 0, 52), LayoutOrder = 3,
		Parent = gemsRow }, 20)
	gemButton("+10", 10, 4)
	gemButton("+100", 100, 5)

	local actions = UIKit.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.53, 0, 1, 0),
		Parent = bar })
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = actions })
	self.ReadyButton = UIKit.button({ Text = "PRÊT", Style = "Primary", Size = UDim2.new(0.32, 0, 0, 56), TextSize = 20, LayoutOrder = 1, Parent = actions,
		Callback = function()
			local s = self.State
			if s and s.Stage ~= "Done" then
				invoke("Ready", not s.MyReady)
			end
		end })
	self.ConfirmButton = UIKit.button({ Text = "CONFIRMER", Style = "Gold", Size = UDim2.new(0.38, 0, 0, 56), TextSize = 20, LayoutOrder = 2, Parent = actions,
		Callback = function()
			local result = invoke("Confirm")
			if not result.ok and result.reason then
				callbacks.Toast(result.reason, RED)
			end
		end })
	UIKit.button({ Text = "ANNULER", Style = "Danger", Size = UDim2.new(0.27, 0, 0, 56), TextSize = 18, LayoutOrder = 3, Parent = actions, Callback = function()
		panel:Close()
	end })

	-- Compte à rebours affiché localement.
	RunService.RenderStepped:Connect(function()
		local s = self.State
		if s and s.Stage == "Locked" and self.LockedUntil then
			local left = self.LockedUntil - os.clock()
			if left > 0 then
				self.ConfirmButton:FindFirstChild("Label").Text = string.format("VÉRIFIE… %d", math.ceil(left))
				UIKit.setDimmed(self.ConfirmButton, true)
			else
				self.ConfirmButton:FindFirstChild("Label").Text = s.MyConfirm and "CONFIRMÉ ✓" or "CONFIRMER"
				UIKit.setDimmed(self.ConfirmButton, s.MyConfirm)
			end
		end
	end)

	---------------------------------------------------------------------------
	-- Fenêtre de demande
	---------------------------------------------------------------------------
	local invite = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -200), Size = UDim2.fromOffset(440, 150),
		BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 40, Visible = false, Parent = gui })
	UIKit.scaled(invite)
	UIKit.corner(invite, 14)
	UIKit.gradient(invite, Color3.fromRGB(52, 32, 82), Color3.fromRGB(16, 10, 30), 90)
	UIKit.stroke(invite, GOLD, 2.5, 0)
	self.InviteText = UIKit.label({ Text = "", RichText = true, Font = UIKit.Fonts.Bold, TextColor3 = CREAM, Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 50), TextWrapped = true, ZIndex = 41, Parent = invite }, 20)
	local timer = UIKit.new("Frame", { BackgroundColor3 = GOLD, BorderSizePixel = 0, Position = UDim2.fromOffset(16, 66), Size = UDim2.new(1, -32, 0, 4), ZIndex = 41,
		Parent = invite })
	self.InviteTimer = timer
	local row = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 80), Size = UDim2.new(1, -32, 0, 56), ZIndex = 41, Parent = invite })
	UIKit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12),
		Parent = row })
	local function respond(accept: boolean)
		local from = self.InviteFrom
		self:HideInvite()
		if from then
			local result = invoke("Respond", { FromId = from, Accept = accept })
			if not result.ok and result.reason then
				callbacks.Toast(result.reason, RED)
			end
		end
	end
	self.AcceptButton = UIKit.button({ Text = "ACCEPTER", Style = "Gold", Size = UDim2.fromOffset(190, 52), TextSize = 18, Parent = row, Callback = function()
		respond(true)
	end })
	UIKit.button({ Text = "REFUSER", Style = "Ghost", Size = UDim2.fromOffset(190, 52), TextSize = 18, Parent = row, Callback = function()
		respond(false)
	end })
	self.Invite = invite

	---------------------------------------------------------------------------
	-- Événements du serveur
	---------------------------------------------------------------------------
	TradeEvent.OnClientEvent:Connect(function(kind: string, data)
		if kind == "Invite" then
			self:ShowInvite(data)
		elseif kind == "Waiting" then
			callbacks.Toast(string.format("Table %d : en attente d'un autre dresseur sur le cercle d'en face...", data.Table), UIKit.Colors.Gold)
		elseif kind == "State" then
			self:SetState(data)
		elseif kind == "Closed" then
			self.State = nil
			self:HideInvite()
			if panel.IsOpen then
				baseClose(panel)
			end
			callbacks.Toast(data.Reason or "Échange annulé.", UIKit.Colors.SubText)
		elseif kind == "Done" then
			self.State = nil
			if panel.IsOpen then
				baseClose(panel)
			end
			local got = {}
			for id, n in pairs(data.Got.Cards) do
				local c = CardsData.CardById[id]
				table.insert(got, (c and c.Name or id) .. (n > 1 and (" ×" .. n) or ""))
			end
			if data.Got.Gems > 0 then
				table.insert(got, data.Got.Gems .. " ◆")
			end
			callbacks.Toast("Échange réussi avec " .. data.Partner .. " ! Reçu : " .. (#got > 0 and table.concat(got, ", ") or "rien"), GREEN)
			UIKit.playSound("Reward", 0.6)
		end
	end)

	return self
end

function Trade:ShowInvite(data)
	self.InviteFrom = data.FromId
	self.InviteText.Text = string.format('<font color="#FFD778">%s</font> te propose un échange de cartes.', data.Name)
	self.Invite.Visible = true
	self.Invite.Position = UDim2.new(0.5, 0, 0, -200)
	UIKit.tween(self.Invite, 0.35, { Position = UDim2.new(0.5, 0, 0, 70) }, Enum.EasingStyle.Back)
	self.InviteTimer.Size = UDim2.new(1, -32, 0, 4)
	UIKit.tween(self.InviteTimer, data.Time or 20, { Size = UDim2.new(0, 0, 0, 4) }, Enum.EasingStyle.Linear)
	UIKit.playSound("Reward", 0.4, 1.2)
	UIKit.focus(self.AcceptButton)
	local from = data.FromId
	task.delay(data.Time or 20, function()
		if self.InviteFrom == from then
			self:HideInvite()
		end
	end)
end

function Trade:HideInvite()
	self.InviteFrom = nil
	if self.Invite.Visible then
		UIKit.tween(self.Invite, 0.25, { Position = UDim2.new(0.5, 0, 0, -200) }).Completed:Once(function()
			if not self.InviteFrom then
				self.Invite.Visible = false
			end
		end)
	end
end

function Trade:SetState(s)
	local previous = self.State
	self.State = s
	local panel = self.Panel
	if not panel.IsOpen then
		self:HideInvite()
		panel:Open()
	end
	panel.Window:FindFirstChild("Title", true).Text = "ÉCHANGE AVEC " .. string.upper(s.Partner.Name)

	-- Offres.
	for key, side in pairs(self.Sides) do
		local offer = s[key]
		for _, child in ipairs(side.List:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, id in ipairs(sortedIds(offer.Cards)) do
			tile(side.List, id, offer.Cards[id], i, key == "Mine" and function()
				invoke("SetCard", { Id = id, Count = offer.Cards[id] - 1 })
			end or nil)
		end
		side.Gems.Text = "◆ " .. offer.Gems .. " gemmes"
		local ready = key == "Mine" and s.MyReady or s.TheirReady
		local confirm = key == "Mine" and s.MyConfirm or s.TheirConfirm
		side.Chip.Visible = ready
		side.Chip.Text = confirm and "CONFIRMÉ ✓" or "PRÊT ✓"
		side.Stroke.Color = ready and GREEN or (key == "Mine" and Color3.fromRGB(70, 140, 255) or Color3.fromRGB(235, 70, 80))
	end
	self.GemLabel.Text = "◆ " .. s.Mine.Gems

	-- Collection (moins ce qui est déjà proposé).
	local profile = self.Callbacks.GetProfile()
	local owned = profile and profile.Cards or {}
	for _, child in ipairs(self.Collection:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, id in ipairs(sortedIds(owned)) do
		local free = (owned[id] or 0) - (s.Mine.Cards[id] or 0)
		if free > 0 then
			tile(self.Collection, id, free, i, function()
				invoke("SetCard", { Id = id, Count = (s.Mine.Cards[id] or 0) + 1 })
			end)
		end
	end

	-- Statut et alerte anti-arnaque.
	local changed = previous and previous.Version ~= s.Version and (previous.MyReady or previous.TheirReady or previous.Stage ~= "Edit")
	if s.Stage == "Locked" then
		self.LockedUntil = os.clock() + (s.Countdown or 0)
		self.Status.Text = '<font color="#7CF59A">Offres verrouillées.</font> Vérifie bien ce que tu reçois, puis confirme.'
	else
		self.LockedUntil = nil
		self.ConfirmButton:FindFirstChild("Label").Text = "CONFIRMER"
		UIKit.setDimmed(self.ConfirmButton, true)
		if changed then
			self.Status.Text = '<font color="#FF8080">⚠ Une offre a changé : vérifie-la avant de valider.</font>'
			UIKit.playSound("Click", 0.6, 0.6)
		elseif s.TheirReady and not s.MyReady then
			self.Status.Text = s.Partner.Name .. " est prêt. Vérifie son offre puis appuie sur PRÊT."
		elseif s.MyReady then
			self.Status.Text = "En attente de " .. s.Partner.Name .. "..."
		else
			self.Status.Text = "Compose ton offre, puis appuie sur PRÊT."
		end
	end
	self.ReadyButton:FindFirstChild("Label").Text = s.MyReady and "PAS PRÊT" or "PRÊT"
end

-- Invite « Échanger » sur les autres joueurs (locale à ce client).
function Trade:SetupPrompts()
	local function attach(player: Player, character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root or root:FindFirstChild("TradePrompt") then
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TradePrompt"
		prompt.ActionText = "Échanger"
		prompt.ObjectText = player.DisplayName
		prompt.KeyboardKeyCode = Enum.KeyCode.T
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
		prompt.Triggered:Connect(function()
			if not self.Callbacks.CanTrade() then
				return
			end
			local result = invoke("Request", player.UserId)
			if result.reason then
				self.Callbacks.Toast(result.reason, result.ok and UIKit.Colors.Gold or RED)
			end
		end)
	end
	local function watch(player: Player)
		if player == Players.LocalPlayer then
			return
		end
		if player.Character then
			task.spawn(attach, player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			attach(player, character)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
end

-- Le profil a changé (gemmes, cartes) : la collection affichée suit.
function Trade:Refresh()
	if self.State and self.Panel.IsOpen then
		self:SetState(self.State)
	end
end

return Trade
