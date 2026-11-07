-- Mode spectateur : les joueurs proches du Cercle des Arcanes voient le duel
-- en cours en 3D (Anima, attaques, barres de vie), caméra libre.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardsData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("CardsData"))
local Arena3D = require(script.Parent:WaitForChild("Arena3D"))

local Spectator = {}
Spectator.__index = Spectator

local GREEN = Color3.fromRGB(95, 225, 130)

local function activeOf(deck)
	for i, f in ipairs(deck or {}) do
		if f.Active and f.HP > 0 then
			return f, i
		end
	end
	for i, f in ipairs(deck or {}) do
		if f.HP > 0 then
			return f, i
		end
	end
	return nil, 0
end

function Spectator.new(toast: (string, Color3?) -> ())
	local self = setmetatable({}, Spectator)
	self.Toast = toast
	self.Token = 0
	return self
end

function Spectator:Stop()
	self.Token += 1
	if self.Arena then
		self.Arena:Destroy()
		self.Arena = nil
	end
end

-- Met les Anima et les barres de vie à jour d'après l'état reçu.
function Spectator:apply(data)
	local arena = self.Arena
	if not arena then
		return
	end
	for _, key in ipairs({ "Me", "Opp" }) do
		local deck = data[key]
		local f = activeOf(deck)
		local side = arena.Sides[key]
		local knockedOut = false
		if side.CardId and (not f or f.Id ~= side.CardId) then
			for _, g in ipairs(deck) do
				if g.Id == side.CardId and g.HP <= 0 then
					knockedOut = true
				end
			end
		end
		arena:SetActive(key, f and f.Id, knockedOut)
		if f then
			local info = key == "Me" and self.MeInfo or self.OppInfo
			local card = CardsData.CardById[f.Id]
			task.delay(knockedOut and 1.1 or 0.3, function()
				if self.Arena == arena and not arena.Dead then
					arena:SetHP(key, f.HP, f.MaxHP, string.format("%s · %s", card and card.Name or "?", info and info.Name or ""))
				end
			end)
		end
	end
end

function Spectator:Start(data)
	self:Stop()
	self.MeInfo, self.OppInfo = data.MeInfo, data.OppInfo
	local ok, arena = pcall(Arena3D.new, {
		Me = { UserId = data.MeInfo.UserId, Deck = data.Me },
		Opp = { UserId = data.OppInfo.UserId, Deck = data.Opp },
	}, function() end, { Spectator = true, MeSign = 1 })
	if not ok or not arena then
		warn("[Spectator]", arena)
		return
	end
	self.Arena = arena
	self:apply(data)
	self.Toast(string.format("Duel en cours : %s contre %s !", data.MeInfo.Name, data.OppInfo.Name), Color3.fromRGB(255, 215, 120))
end

function Spectator:Resolve(data)
	local arena = self.Arena
	if not arena then
		return
	end
	local token = self.Token
	for _, e in ipairs(data.Events or {}) do
		local key = e.From == self.MeInfo.UserId and "Me" or "Opp"
		if e.Action == "Attack" or (e.Action == "Ability" and e.Hits) then
			task.spawn(function()
				pcall(arena.Attack, arena, key, e)
				if self.Token == token then
					self:apply(data)
				end
			end)
			return
		elseif e.Action == "Tick" then
			local st = CardsData.Statuses[e.Status]
			arena:Tick(key, st.Color, st.Icon .. " -" .. e.Damage)
		elseif e.Action == "Defend" then
			arena:Guard(key, "+" .. (e.Heal or 0))
		elseif e.Action == "Ability" then
			arena:Buff(key, (e.Heal or 0) > 0 and ("+" .. e.Heal) or (e.Shield and ("◈ " .. e.Shield)) or nil,
				e.Shield and Color3.fromRGB(120, 200, 255) or GREEN)
		elseif e.Action == "Stunned" then
			local st = CardsData.Statuses[e.Status]
			arena:Number(key, st.Icon .. " " .. st.Label, st.Color)
		end
	end
	task.delay(0.5, function()
		if self.Token == token then
			self:apply(data)
		end
	end)
end

function Spectator:End(data)
	local token = self.Token
	if data and data.Reason then
		self.Toast(data.Reason, Color3.fromRGB(255, 215, 120))
	end
	task.delay(2.5, function()
		if self.Token == token then
			self:Stop()
		end
	end)
end

-- Événements « SpecStart », « SpecResolve », « SpecEnd » du serveur.
function Spectator:Handle(kind: string, data)
	if kind == "SpecStart" then
		self:Start(data)
	elseif kind == "SpecResolve" then
		self:Resolve(data)
	elseif kind == "SpecEnd" then
		self:End(data)
	end
end

return Spectator
