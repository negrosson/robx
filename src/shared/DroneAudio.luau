--!strict
-- src/shared/DroneAudio.luau
-- Sistema de Audio Dinámico Cyberpunk para Cyber Delivery Tycoon
local TweenService = game:GetService("TweenService")

local DroneAudio = {}
DroneAudio.__index = DroneAudio

export type AudioInstance = {
	engineSound: Sound,
	rootPart: BasePart,
	currentPitch: number,
	currentVolume: number,
}

-- ID de sonido ambiental / rotor de turbina cyberpunk (Loop)
local TURBINE_SOUND_ID = "rbxassetid://9114223170"

function DroneAudio.new(rootPart: BasePart): AudioInstance
	local existingSound = rootPart:FindFirstChild("DroneTurbineSound") :: Sound?
	if existingSound then
		existingSound:Destroy()
	end

	local sound = Instance.new("Sound")
	sound.Name = "DroneTurbineSound"
	sound.SoundId = TURBINE_SOUND_ID
	sound.Looped = true
	sound.Volume = 0.35
	sound.PlaybackSpeed = 0.85
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 120
	sound.Parent = rootPart
	sound:Play()

	local self: AudioInstance = {
		engineSound = sound,
		rootPart = rootPart,
		currentPitch = 0.85,
		currentVolume = 0.35,
	}

	return setmetatable(self, DroneAudio) :: any
end

function DroneAudio.Update(self: AudioInstance, speedRatio: number, verticalInput: number, deltaTime: number)
	if not self.engineSound or not self.engineSound.Parent then return end

	local dt = math.clamp(deltaTime, 0, 0.1)

	-- Tono base: 0.85 (ralentí) hasta 1.65 (máxima velocidad + impulso vertical)
	local verticalBoost = math.abs(verticalInput) * 0.25
	local targetPitch = 0.85 + (speedRatio * 0.55) + verticalBoost
	local targetVolume = 0.35 + (speedRatio * 0.4) + (verticalBoost * 0.15)

	-- Suavizado de transición de audio (evita chasquidos acústicos)
	self.currentPitch = self.currentPitch + (targetPitch - self.currentPitch) * math.clamp(dt * 10, 0, 1)
	self.currentVolume = self.currentVolume + (targetVolume - self.currentVolume) * math.clamp(dt * 8, 0, 1)

	self.engineSound.PlaybackSpeed = self.currentPitch
	self.engineSound.Volume = self.currentVolume
end

function DroneAudio.Destroy(self: AudioInstance)
	if self.engineSound then
		local fade = TweenService:Create(self.engineSound, TweenInfo.new(0.3), { Volume = 0 })
		fade:Play()
		fade.Completed:Connect(function()
			self.engineSound:Destroy()
		end)
	end
end

return DroneAudio

