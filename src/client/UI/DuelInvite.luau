-- Invitation à un duel reçue d'un autre joueur : carte en haut de l'écran
-- avec compte à rebours, boutons Accepter / Refuser.
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local DuelInvite = {}
DuelInvite.__index = DuelInvite

function DuelInvite.new(parent: Instance, respond: (fromId: number, accept: boolean) -> ())
	local self = setmetatable({}, DuelInvite)
	self.Token = 0

	local root = UIKit.new("Frame", {
		Name = "DuelInvite",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 140),
		Size = UDim2.fromOffset(520, 150),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 40,
		Parent = parent,
	})
	UIKit.scaled(root)
	UIKit.corner(root, 20)
	UIKit.gradient(root, Color3.fromRGB(70, 30, 40), Color3.fromRGB(22, 12, 20), 90)
	UIKit.stroke(root, UIKit.Colors.Gold, 2.5, 0)
	self.Root = root
	self.Pop = UIKit.new("UIScale", { Parent = root })

	UIKit.label({
		Text = "DÉFI EN DUEL",
		Font = UIKit.Fonts.Black,
		TextColor3 = UIKit.Colors.Gold,
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -40, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 40,
		Parent = root,
	}, 20)
	self.Message = UIKit.label({
		Text = "",
		Font = UIKit.Fonts.Bold,
		Position = UDim2.fromOffset(20, 40),
		Size = UDim2.new(1, -40, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 40,
		Parent = root,
	}, 19)

	local track = UIKit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(20, 10, 15),
		Position = UDim2.fromOffset(20, 72),
		Size = UDim2.new(1, -40, 0, 6),
		ZIndex = 40,
		Parent = root,
	})
	UIKit.corner(track, 3)
	self.Timer = UIKit.new("Frame", { BackgroundColor3 = UIKit.Colors.Gold, Size = UDim2.fromScale(1, 1), ZIndex = 40, Parent = track })
	UIKit.corner(self.Timer, 3)

	local function answer(accept: boolean)
		if self.FromId then
			local fromId = self.FromId
			self:Hide()
			respond(fromId, accept)
		end
	end
	self.AcceptButton = UIKit.button({
		Text = "ACCEPTER",
		Style = "Gold",
		Position = UDim2.new(0, 20, 1, -60),
		Size = UDim2.new(0.5, -26, 0, 46),
		TextSize = 18,
		Parent = root,
		Callback = function()
			answer(true)
		end,
	})
	UIKit.button({
		Text = "REFUSER",
		Style = "Ghost",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 1, -60),
		Size = UDim2.new(0.5, -26, 0, 46),
		TextSize = 18,
		Parent = root,
		Callback = function()
			answer(false)
		end,
	})

	return self
end

function DuelInvite:Show(data)
	self.Token += 1
	local token = self.Token
	self.FromId = data.FromId
	self.Message.Text = string.format("%s te défie dans l'Arène des Champions !", data.FromName or "Un dresseur")
	self.Root.Visible = true
	self.Pop.Scale = 0.7
	UIKit.tween(self.Pop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	UIKit.playSound("Reveal", 0.5, 1.1)
	UIKit.focus(self.AcceptButton)
	local duration = data.Duration or 20
	self.Timer.Size = UDim2.fromScale(1, 1)
	UIKit.tween(self.Timer, duration, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	task.delay(duration, function()
		if self.Token == token then
			self:Hide()
		end
	end)
end

function DuelInvite:Hide()
	self.Token += 1
	self.FromId = nil
	UIKit.tween(self.Pop, 0.15, { Scale = 0.8 }).Completed:Once(function()
		if self.FromId == nil then
			self.Root.Visible = false
		end
	end)
end

return DuelInvite
