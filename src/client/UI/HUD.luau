-- Interface en jeu : carte joueur (gemmes + bestiaire), boutons d'action
-- en haut à droite et notifications.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local WorldMap = require(script.Parent:WaitForChild("WorldMap"))

local HUD = {}
HUD.__index = HUD

type Callbacks = {
	Collection: () -> (),
	Menu: () -> (),
	Daily: () -> (),
	Help: () -> (),
	Shop: () -> (),
	Map: () -> (),
}

function HUD.new(parent: Instance, callbacks: Callbacks)
	local self = setmetatable({}, HUD)
	self.DisplayedCoins = 0

	local root = UIKit.new("CanvasGroup", {
		Name = "HUD",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = parent,
	})
	self.Root = root

	---------------------------------------------------------------------------
	-- Carte joueur (en haut à gauche) : barre de gemmes et barre du bestiaire,
	-- fond bleu nuit, bordures dorées.
	---------------------------------------------------------------------------
	local NAVY_TOP, NAVY_BOTTOM = Color3.fromRGB(34, 36, 70), Color3.fromRGB(12, 12, 28)
	local GOLD = Color3.fromRGB(232, 190, 105)
	local card = UIKit.new("Frame", {
		Name = "PlayerCard",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 72),
		Size = UDim2.fromOffset(270, 280),
		Parent = root,
	})
	UIKit.scaled(card)

	-- Mini-carte cliquable au-dessus des gemmes : ouvre la grande carte.
	local mini = UIKit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(26, 0),
		Size = UDim2.fromOffset(170, 170),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
	})
	UIKit.corner(mini, 12)
	UIKit.stroke(mini, Color3.fromRGB(232, 190, 105), 3, 0)
	local miniMarker = WorldMap.draw(mini, false)
	WorldMap.track(miniMarker, function()
		return root.Visible
	end)
	mini.Activated:Connect(function()
		UIKit.playSound("Click", 0.4)
		callbacks.Map()
	end)
	local MAP_H = 184

	local function pill(props): Frame
		local f = UIKit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Position = props.Position,
			Size = props.Size,
			Parent = card,
		})
		UIKit.corner(f, 10)
		UIKit.gradient(f, NAVY_TOP, NAVY_BOTTOM, 90)
		UIKit.stroke(f, GOLD, 2, 0.05)
		local inset = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), Parent = f })
		UIKit.corner(inset, 7)
		UIKit.stroke(inset, GOLD, 1, 0.65)
		-- Pointe ornementale à droite.
		local tip = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(12, 12),
			Rotation = 45,
			BackgroundColor3 = GOLD,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = f,
		})
		UIKit.stroke(tip, Color3.fromRGB(70, 45, 15), 1.5, 0)
		return f
	end

	-- Barre des gemmes, avec une grosse gemme qui déborde à gauche.
	local gemBar = pill({ Position = UDim2.fromOffset(26, MAP_H + 4), Size = UDim2.fromOffset(226, 52) })
	local badge = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = gemBar,
	})
	UIKit.corner(badge, 6)
	UIKit.gradient(badge, Color3.fromRGB(150, 235, 255), Color3.fromRGB(30, 80, 210), 45)
	UIKit.stroke(badge, GOLD, 2.5, 0)
	local facet = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.45,
		Position = UDim2.fromScale(0.15, 0.15),
		Size = UDim2.fromScale(0.35, 0.35),
		ZIndex = 5,
		Parent = badge,
	})
	UIKit.corner(facet, 3)
	self.BadgeScale = UIKit.new("UIScale", { Parent = badge })
	self.Badge = badge
	self.Gui = parent
	self.Card = card

	UIKit.label({
		Text = "GEMMES",
		Font = UIKit.Fonts.Black,
		TextColor3 = Color3.fromRGB(200, 185, 150),
		Position = UDim2.fromOffset(34, 6),
		Size = UDim2.fromOffset(170, 13),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = gemBar,
	}, 12)
	self.CoinsLabel = UIKit.label({
		Text = "0",
		Font = UIKit.Fonts.Black,
		TextColor3 = Color3.fromRGB(255, 248, 230),
		Position = UDim2.fromOffset(33, 18),
		Size = UDim2.fromOffset(175, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = gemBar,
	}, 26)

	-- Barre du bestiaire, avec un livre en icône.
	local bookBar = pill({ Position = UDim2.fromOffset(14, MAP_H + 64), Size = UDim2.fromOffset(238, 36) })
	local book = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(24, 30),
		Rotation = -10,
		BackgroundColor3 = Color3.fromRGB(130, 70, 35),
		ZIndex = 4,
		Parent = bookBar,
	})
	UIKit.corner(book, 4)
	UIKit.stroke(book, GOLD, 2, 0)
	UIKit.new("Frame", { BackgroundColor3 = GOLD, BorderSizePixel = 0, Position = UDim2.fromScale(0.2, 0), Size = UDim2.new(0, 2, 1, 0), ZIndex = 5, Parent = book })
	local clasp = UIKit.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.6, 0.45), Size = UDim2.fromOffset(8, 8), Rotation = 45,
		BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 5, Parent = book })
	clasp.Name = "Clasp"
	self.ProgressLabel = UIKit.label({
		Text = "BESTIAIRE 0 / 0",
		Font = UIKit.Fonts.Black,
		TextColor3 = Color3.fromRGB(255, 248, 230),
		Position = UDim2.fromOffset(24, 4),
		Size = UDim2.new(1, -40, 0, 15),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bookBar,
	}, 13)
	local track = UIKit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(8, 8, 18),
		Position = UDim2.fromOffset(24, 22),
		Size = UDim2.new(1, -40, 0, 7),
		Parent = bookBar,
	})
	UIKit.corner(track, 4)
	UIKit.stroke(track, GOLD, 1, 0.6)
	self.ProgressFill = UIKit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0, 1), Parent = track })
	UIKit.corner(self.ProgressFill, 4)
	UIKit.gradient(self.ProgressFill, Color3.fromRGB(150, 210, 255), Color3.fromRGB(70, 120, 230), 90)

	---------------------------------------------------------------------------
	-- Actions (en haut à droite ; le bas reste libre pour les contrôles mobiles)
	---------------------------------------------------------------------------
	local topRight = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 72),
		Size = UDim2.fromOffset(560, 112),
		Parent = root,
	})
	UIKit.scaled(topRight)
	local row1 = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), Parent = topRight })
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row1,
	})

	local help = UIKit.button({ Text = "?", Style = "Ghost", Size = UDim2.fromOffset(50, 50), TextSize = 24,
		LayoutOrder = 3, Parent = row1, Callback = callbacks.Help })
	-- Bouton d'aide rond.
	for _, d in ipairs(help:GetDescendants()) do
		if d:IsA("UICorner") then
			d.CornerRadius = UDim.new(0.5, 0)
		end
	end

	---------------------------------------------------------------------------
	-- Notifications
	---------------------------------------------------------------------------
	local toasts = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(460, 200),
		Parent = parent,
		ZIndex = 30,
	})
	UIKit.scaled(toasts)
	UIKit.new("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toasts,
	})
	self.Toasts = toasts
	self.ToastCount = 0

	return self
end

function HUD:SetProfile(profile)
	if profile == nil then
		return
	end
	local target = profile.Coins
	if self.GemFlight then
		-- Le compteur sera mis à jour par l'arrivée des gemmes.
		self.PendingCoins = target
		target = self.DisplayedCoins
	end
	local start = self.DisplayedCoins
	self.DisplayedCoins = target
	if start ~= target then
		task.spawn(function()
			local steps = 20
			for i = 1, steps do
				self.CoinsLabel.Text = tostring(math.floor(start + (target - start) * i / steps + 0.5))
				task.wait(0.02)
			end
		end)
		if target > start then
			self.BadgeScale.Scale = 1.25
			UIKit.tween(self.BadgeScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Elastic)
		end
	else
		self.CoinsLabel.Text = tostring(target)
	end

	local discovered = 0
	for _ in pairs(profile.Cards) do
		discovered += 1
	end
	local total = #CardsData.Cards
	self.ProgressLabel.Text = string.format("BESTIAIRE %d / %d", discovered, total)
	UIKit.tween(self.ProgressFill, 0.4, { Size = UDim2.fromScale(discovered / total, 1) })

end

-- Gerbe de gemmes qui jaillit de `from` puis file vers le compteur ; le
-- total monte à chaque gemme reçue.
function HUD:FlyGems(from: Vector2, amount: number)
	local gui = self.Gui
	local guiPos = gui.AbsolutePosition
	local origin = from - guiPos
	local badgeCenter = self.Badge.AbsolutePosition + self.Badge.AbsoluteSize / 2 - guiPos
	local count = math.clamp(math.floor(amount / 25), 8, 18)
	local start = self.DisplayedCoins
	self.GemFlight = true
	self.PendingCoins = start + amount
	local arrived = 0

	for i = 1, count do
		local gem = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(origin.X, origin.Y),
			Size = UDim2.fromOffset(22, 22),
			Rotation = 45,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 200,
			Parent = gui,
		})
		UIKit.corner(gem, 4)
		UIKit.gradient(gem, Color3.fromRGB(170, 245, 255), Color3.fromRGB(40, 120, 230), 90)
		UIKit.stroke(gem, Color3.fromRGB(230, 252, 255), 1.5, 0.1)
		local scale = UIKit.new("UIScale", { Scale = 0, Parent = gem })
		local angle = math.random() * math.pi * 2
		local burst = origin + Vector2.new(math.cos(angle), math.sin(angle)) * (60 + math.random() * 90)
		task.delay((i - 1) * 0.04, function()
			UIKit.tween(scale, 0.25, { Scale = 0.8 + math.random() * 0.5 }, Enum.EasingStyle.Back)
			UIKit.tween(gem, 0.4, { Position = UDim2.fromOffset(burst.X, burst.Y), Rotation = 45 + math.random(-90, 90) }, Enum.EasingStyle.Quad).Completed:Wait()
			task.wait(0.1 + i * 0.05)
			-- Trajectoire courbe vers la pastille gemme.
			local control = Vector2.new(burst.X, badgeCenter.Y) + Vector2.new(0, 80)
			local t0 = os.clock()
			local duration = 0.55
			while true do
				local t = math.clamp((os.clock() - t0) / duration, 0, 1)
				local e = t * t
				local p = burst:Lerp(control, e):Lerp(control:Lerp(badgeCenter, e), e)
				gem.Position = UDim2.fromOffset(p.X, p.Y)
				scale.Scale = 1 - 0.5 * e
				if t >= 1 then
					break
				end
				task.wait()
			end
			gem:Destroy()
			arrived += 1
			local value = math.floor(start + amount * arrived / count + 0.5)
			self.DisplayedCoins = value
			self.CoinsLabel.Text = tostring(value)
			self.BadgeScale.Scale = 1.2
			UIKit.tween(self.BadgeScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			UIKit.playSound("Click", 0.25, 1.4 + arrived / count * 0.6)
			if arrived == count then
				self.GemFlight = false
				local final = self.PendingCoins or value
				self.DisplayedCoins = final
				self.CoinsLabel.Text = tostring(final)
				self.BadgeScale.Scale = 1.35
				UIKit.tween(self.BadgeScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Elastic)
			end
		end)
	end
end

function HUD:Toast(text: string, color: Color3?)
	-- Notifications en haut de l'écran désactivées.
	if true then
		return
	end
	self.ToastCount += 1
	local toast = UIKit.new("Frame", {
		BackgroundColor3 = UIKit.Colors.Panel,
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(440, 44),
		LayoutOrder = self.ToastCount,
		Parent = self.Toasts,
	})
	UIKit.corner(toast, 22)
	UIKit.stroke(toast, color or UIKit.Colors.Accent, 2, 0)
	local label = UIKit.label({
		Text = text,
		Font = UIKit.Fonts.Bold,
		TextColor3 = color or UIKit.Colors.Text,
		Size = UDim2.new(1, -24, 1, -12),
		Position = UDim2.fromOffset(12, 6),
		Parent = toast,
	}, 20)
	local scale = UIKit.new("UIScale", { Scale = 0.6, Parent = toast })
	UIKit.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.6, function()
		UIKit.tween(toast, 0.3, { BackgroundTransparency = 1 })
		UIKit.tween(label, 0.3, { TextTransparency = 1 })
		UIKit.tween(scale, 0.3, { Scale = 0.8 }).Completed:Wait()
		toast:Destroy()
	end)
end

function HUD:Show()
	self.Root.Visible = true
	self.Root.GroupTransparency = 1
	UIKit.tween(self.Root, 0.5, { GroupTransparency = 0 })
	self.Card.Position = UDim2.fromOffset(-260, 72)
	UIKit.tween(self.Card, 0.6, { Position = UDim2.fromOffset(16, 72) }, Enum.EasingStyle.Back)
end

function HUD:Hide()
	local tween = UIKit.tween(self.Root, 0.3, { GroupTransparency = 1 })
	tween.Completed:Once(function()
		if self.Root.GroupTransparency >= 0.99 then
			self.Root.Visible = false
		end
	end)
end

return HUD
