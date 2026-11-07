--!strict
-- src/shared/DroneVFX.luau
-- Sistema de Efectos Visuales Cyberpunk (Estelas de Neón y Propulsores Iónicos)
local DroneVFX = {}
DroneVFX.__index = DroneVFX

export type VFXInstance = {
	rootPart: BasePart,
	attachments: { Attachment },
	trails: { Trail },
	emitters: { ParticleEmitter },
	underLight: PointLight?,
}

function DroneVFX.new(rootPart: BasePart): VFXInstance
	local attachments: { Attachment } = {}
	local trails: { Trail } = {}
	local emitters: { ParticleEmitter } = {}

	-- Limpiar efectos previos si existieran
	for _, child in ipairs(rootPart:GetChildren()) do
		if child.Name:find("CyberThruster") or child.Name:find("NeonTrail") or child.Name:find("PlasmaEmitter") or child.Name == "ChassisNeon" then
			child:Destroy()
		end
	end

	local halfX = math.max(rootPart.Size.X * 0.45, 1)
	local halfZ = math.max(rootPart.Size.Z * 0.45, 1)
	local halfY = -math.max(rootPart.Size.Y * 0.4, 0.3)

	local thrusterOffsets = {
		Vector3.new(halfX, halfY, halfZ),
		Vector3.new(-halfX, halfY, halfZ),
		Vector3.new(halfX, halfY, -halfZ),
		Vector3.new(-halfX, halfY, -halfZ),
	}

	local neonColorSeq = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 255, 230)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(150, 0, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 128)),
	})

	local trailTranspSeq = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})

	for i, offset in ipairs(thrusterOffsets) do
		-- En Roblox, los Attachments DEBEN ser hijos directos de un BasePart
		local att0 = Instance.new("Attachment")
		att0.Name = string.format("CyberThrusterAtt%d_0", i)
		att0.Position = offset + Vector3.new(0, 0.2, 0)
		att0.Parent = rootPart
		table.insert(attachments, att0)

		local att1 = Instance.new("Attachment")
		att1.Name = string.format("CyberThrusterAtt%d_1", i)
		att1.Position = offset - Vector3.new(0, 0.2, 0)
		att1.Parent = rootPart
		table.insert(attachments, att1)

		local trail = Instance.new("Trail")
		trail.Name = string.format("NeonTrail%d", i)
		trail.Attachment0 = att0
		trail.Attachment1 = att1
		trail.Color = neonColorSeq
		trail.Transparency = trailTranspSeq
		trail.Lifetime = 0.35
		trail.LightEmission = 1
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		trail.Parent = rootPart
		table.insert(trails, trail)

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = string.format("PlasmaEmitter%d", i)
		emitter.Color = neonColorSeq
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(0.15, 0.3)
		emitter.Rate = 12
		emitter.Speed = NumberRange.new(4, 10)
		emitter.SpreadAngle = Vector2.new(15, 15)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Parent = att1
		table.insert(emitters, emitter)
	end

	local underLight = Instance.new("PointLight")
	underLight.Name = "ChassisNeon"
	underLight.Color = Color3.fromRGB(0, 240, 255)
	underLight.Brightness = 3
	underLight.Range = 16
	underLight.Shadows = true
	underLight.Parent = rootPart

	local self: VFXInstance = {
		rootPart = rootPart,
		attachments = attachments,
		trails = trails,
		emitters = emitters,
		underLight = underLight,
	}

	return setmetatable(self, DroneVFX) :: any
end

function DroneVFX.Update(self: VFXInstance, speedRatio: number, verticalInput: number)
	local boost = math.clamp(speedRatio + (math.abs(verticalInput) * 0.4), 0, 1)
	local targetRate = 10 + (boost * 50)

	for _, emitter in ipairs(self.emitters) do
		if emitter and emitter.Parent then
			emitter.Rate = targetRate
		end
	end

	if self.underLight and self.underLight.Parent then
		self.underLight.Brightness = 2 + (boost * 2.5)
	end
end

-- ═══ Pulido Sensorial: Reacción a impactos y daño de proyectil ═══
function DroneVFX.PlayHitEffect(self: VFXInstance, damage: number)
	if not self.rootPart or not self.rootPart.Parent then return end

	-- Emisión de chispas de daño cinético/térmico en el chasis
	local sparkPart = Instance.new("Part")
	sparkPart.Name = "HitSparks"
	sparkPart.Size = Vector3.new(0.5, 0.5, 0.5)
	sparkPart.CFrame = self.rootPart.CFrame
	sparkPart.Transparency = 1
	sparkPart.Anchored = true
	sparkPart.CanCollide = false
	sparkPart.Parent = Workspace

	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 140, 0), Color3.fromRGB(255, 30, 30))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Speed = NumberRange.new(10, 24)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Lifetime = NumberRange.new(0.2, 0.45)
	pe.Rate = 0
	pe.Parent = sparkPart
	pe:Emit(math.clamp(math.round(damage * 1.5), 10, 30))

	-- Pulso de advertencia en la iluminación de fondo
	if self.underLight and self.underLight.Parent then
		local prevCol = self.underLight.Color
		local prevBright = self.underLight.Brightness
		self.underLight.Color = Color3.fromRGB(255, 30, 40)
		self.underLight.Brightness = 8
		task.delay(0.2, function()
			if self.underLight and self.underLight.Parent then
				self.underLight.Color = prevCol
				self.underLight.Brightness = prevBright
			end
		end)
	end

	task.delay(0.6, function()
		if sparkPart.Parent then sparkPart:Destroy() end
	end)
end

-- ═══ Pulido Sensorial: Reacción a sobrecarga EMP ═══
function DroneVFX.PlayEMPEffect(self: VFXInstance)
	if not self.rootPart or not self.rootPart.Parent then return end

	if self.underLight and self.underLight.Parent then
		local prevCol = self.underLight.Color
		local prevBright = self.underLight.Brightness
		self.underLight.Color = Color3.fromRGB(0, 255, 240)
		self.underLight.Brightness = 12

		task.delay(0.5, function()
			if self.underLight and self.underLight.Parent then
				self.underLight.Color = prevCol
				self.underLight.Brightness = prevBright
			end
		end)
	end
end

function DroneVFX.Destroy(self: VFXInstance)
	for _, trail in ipairs(self.trails) do
		if trail and trail.Parent then trail:Destroy() end
	end
	for _, emitter in ipairs(self.emitters) do
		if emitter and emitter.Parent then emitter:Destroy() end
	end
	for _, att in ipairs(self.attachments) do
		if att and att.Parent then att:Destroy() end
	end
	if self.underLight and self.underLight.Parent then
		self.underLight:Destroy()
	end
end

return DroneVFX
