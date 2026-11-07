-- Immobilise le personnage pendant un écran (fiche de carte, booster, combat).
-- Aucune attente bloquante : le jeu n'a pas forcément de PlayerModule.
-- Compteur de demandes : le personnage n'est libéré que lorsque tous les
-- écrans qui l'ont figé l'ont relâché.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local Freeze = {}

local holders: { [string]: boolean } = {}
local frozen = false
-- Hauteur de saut normale : celle du jeu (et non une valeur mémorisée, qui
-- pouvait être 0 si le personnage était déjà figé, par le livre par exemple).
local function normalJump(): number
	local ok, value = pcall(function()
		return game:GetService("StarterPlayer").CharacterJumpHeight
	end)
	return (ok and value and value > 0) and value or 7.2
end

local function controls()
	local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then
		return nil
	end
	local ok, result = pcall(function()
		return (require(module :: ModuleScript) :: any):GetControls()
	end)
	return ok and result or nil
end

local function apply(on: boolean)
	if on == frozen then
		return
	end
	frozen = on
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if on then
		-- Touches de déplacement, saut et course avalées.
		ContextActionService:BindActionAtPriority("ArcanaFreeze", function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 200,
			Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Z, Enum.KeyCode.Q,
			Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
			Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.Thumbstick1, Enum.KeyCode.ButtonL3)
		-- (Espace / A restent libres : ils servent dans les menus ; le saut est
		-- de toute façon impossible, personnage ancré et JumpHeight à 0.)
		if humanoid then
			humanoid.JumpHeight = 0
			humanoid:Move(Vector3.zero)
		end
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = true
		end
	else
		ContextActionService:UnbindAction("ArcanaFreeze")
		if humanoid then
			humanoid.JumpHeight = normalJump()
		end
		if root then
			root.Anchored = false
		end
	end
	local c = controls()
	if c then
		if on then
			c:Disable()
		else
			c:Enable()
		end
	end
end

-- `who` : nom de l'écran qui fige (« Booster », « Combat », « Fiche »...).
function Freeze.hold(who: string)
	holders[who] = true
	apply(true)
end

function Freeze.release(who: string)
	holders[who] = nil
	if next(holders) == nil then
		apply(false)
	end
end

return Freeze
