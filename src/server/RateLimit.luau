-- Limiteur de requêtes par joueur (seau à jetons) et validation d'arguments.
-- Un client modifié peut appeler les remotes en boucle : chaque clé a un
-- débit (jetons/seconde) et une réserve (rafale autorisée). Un joueur qui
-- abuse lourdement est signalé puis expulsé.
local Players = game:GetService("Players")

local RateLimit = {}

type Bucket = { Tokens: number, At: number }
local buckets: { [Player]: { [string]: Bucket } } = {}
local strikes: { [Player]: number } = {}

local STRIKE_LIMIT = 300 -- refus cumulés avant expulsion

-- true si la requête est autorisée.
function RateLimit.allow(player: Player, key: string, perSecond: number, burst: number): boolean
	local mine = buckets[player]
	if not mine then
		mine = {}
		buckets[player] = mine
	end
	local now = os.clock()
	local b = mine[key]
	if not b then
		b = { Tokens = burst, At = now }
		mine[key] = b
	end
	b.Tokens = math.min(burst, b.Tokens + (now - b.At) * perSecond)
	b.At = now
	if b.Tokens >= 1 then
		b.Tokens -= 1
		return true
	end
	strikes[player] = (strikes[player] or 0) + 1
	if strikes[player] == STRIKE_LIMIT then
		warn("[RateLimit] " .. player.Name .. " (" .. player.UserId .. ") inonde le serveur de requêtes : expulsion.")
		player:Kick("Trop de requêtes envoyées.")
	end
	return false
end

-- Valeur « raisonnable » venant du client : types simples, taille bornée.
function RateLimit.safeArg(value: any, depth: number?): boolean
	local d = depth or 0
	local t = type(value)
	if t == "nil" or t == "boolean" then
		return true
	elseif t == "number" then
		return value == value and value > -1e9 and value < 1e9 -- refuse NaN et l'infini
	elseif t == "string" then
		return #value <= 200
	elseif t == "table" and d < 2 then
		local n = 0
		for k, v in pairs(value) do
			n += 1
			if n > 40 or not RateLimit.safeArg(k, d + 1) or not RateLimit.safeArg(v, d + 1) then
				return false
			end
		end
		return true
	end
	return false
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
	strikes[player] = nil
end)

return RateLimit
