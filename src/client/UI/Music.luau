-- Musique de fond : une piste par écran (Menu, Explore, Duel) avec fondu
-- enchaîné. Les pistes sont définies dans Configs/SoundData.Music et
-- respectent le réglage « Son ».
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local SoundData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("SoundData"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local Music = {}

local FADE = 1.6
local group = Instance.new("SoundGroup")
group.Name = "Musique"
group.Parent = SoundService

local tracks: { [string]: Sound } = {}
local current: string? = nil

local function trackFor(name: string): Sound?
	local data = SoundData.Music[name]
	if not data or data.Id == "" then
		return nil
	end
	local sound = tracks[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = data.Id
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = group
		sound.Parent = SoundService
		tracks[name] = sound
	end
	return sound
end

local function targetVolume(name: string): number
	local data = SoundData.Music[name]
	return (UIKit.Settings.Sound ~= false and data) and data.Volume or 0
end

-- Passe à la piste « name » (Menu, Explore, Duel). nil : silence.
function Music.play(name: string?)
	if name == current then
		return
	end
	local previous = current and tracks[current]
	current = name
	if previous then
		local fadeOut = TweenService:Create(previous, TweenInfo.new(FADE), { Volume = 0 })
		fadeOut:Play()
		fadeOut.Completed:Once(function()
			if previous ~= (current and tracks[current]) then
				previous:Pause()
			end
		end)
	end
	local sound = name and trackFor(name)
	if sound then
		if not sound.IsPlaying then
			-- Le Menu repart du début, les autres reprennent où elles étaient.
			if name == "Menu" then
				sound.TimePosition = 0
			end
			sound:Resume()
		end
		TweenService:Create(sound, TweenInfo.new(FADE), { Volume = targetVolume(name :: string) }):Play()
	end
end

-- À appeler quand le réglage « Son » change.
function Music.refresh()
	for name, sound in pairs(tracks) do
		sound.Volume = name == current and targetVolume(name) or 0
	end
end

return Music
