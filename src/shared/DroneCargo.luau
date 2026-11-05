--!strict
-- src/shared/DroneCargo.luau
-- Sistema de Contenedor y Carga Magnética con Haz Tractor + Inercia Dinámica Real
local DroneCargo = {}
DroneCargo.__index = DroneCargo

-- Constantes de física de carga
local INERTIA_ALPHA_DEFAULT = 0.040  -- α por defecto si el dron no especifica
local EK_DETONATION_THRESHOLD = 4000  -- Joules (Ek = 0.5*M*v²) para detonar carga inestable
local CARGO_MASS_DEFAULT    = 10     -- kg por defecto

export type CargoInstance = {
	rootPart     : BasePart,
	cargoModel   : Model,
	cargoBox     : BasePart,
	weld         : WeldConstraint,
	beams        : { Beam },
	isLoaded     : boolean,
	-- NUEVO: propiedades de masa e inercia
	cargoMass    : number,  -- kg del paquete actual
	inertiaAlpha : number,  -- α para la fórmula VelocidadEfectiva
	isUnstable   : boolean, -- carga inestable (detona en impacto fuerte)
}

local COLOR_CARGO_NEON = Color3.fromRGB(0, 255, 230)
local COLOR_CARGO_BODY = Color3.fromRGB(20, 25, 35)

function DroneCargo.new(dronePart: BasePart): CargoInstance
	local existingCargo = dronePart:FindFirstChild("DroneCargoContainer")
	if existingCargo then
		existingCargo:Destroy()
	end

	local cargoModel = Instance.new("Model")
	cargoModel.Name = "DroneCargoContainer"

	-- Contenedor de carga físico
	local cargoBox = Instance.new("Part")
	cargoBox.Name = "CargoBox"
	cargoBox.Size = Vector3.new(2.8, 1.8, 2.8)
	cargoBox.Material = Enum.Material.Metal
	cargoBox.Color = COLOR_CARGO_BODY
	cargoBox.CanCollide = false
	cargoBox.Massless = true
	cargoBox.CFrame = dronePart.CFrame * CFrame.new(0, -dronePart.Size.Y * 0.7 - 1.2, 0)
	cargoBox.Parent = cargoModel

	-- Bordes luminosos del contenedor
	local cargoBand = Instance.new("Part")
	cargoBand.Name = "NeonBand"
	cargoBand.Size = Vector3.new(2.9, 0.4, 2.9)
	cargoBand.Material = Enum.Material.Neon
	cargoBand.Color = COLOR_CARGO_NEON
	cargoBand.CanCollide = false
	cargoBand.Massless = true
	cargoBand.CFrame = cargoBox.CFrame
	cargoBand.Parent = cargoModel

	local bandWeld = Instance.new("WeldConstraint")
	bandWeld.Part0 = cargoBox
	bandWeld.Part1 = cargoBand
	bandWeld.Parent = cargoBox

	-- Unión física con el chasis del dron
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = dronePart
	weld.Part1 = cargoBox
	weld.Parent = cargoBox

	-- Haz tractor magnético holográfico (Beams)
	local beams: { Beam } = {}
	local attDrone = Instance.new("Attachment")
	attDrone.Name = "TractorAttDrone"
	attDrone.Position = Vector3.new(0, -dronePart.Size.Y * 0.5, 0)
	attDrone.Parent = dronePart

	local attCargo = Instance.new("Attachment")
	attCargo.Name = "TractorAttCargo"
	attCargo.Position = Vector3.new(0, cargoBox.Size.Y * 0.5, 0)
	attCargo.Parent = cargoBox

	local tractorBeam = Instance.new("Beam")
	tractorBeam.Name = "TractorBeam"
	tractorBeam.Attachment0 = attDrone
	tractorBeam.Attachment1 = attCargo
	tractorBeam.Color = ColorSequence.new(COLOR_CARGO_NEON)
	tractorBeam.Width0 = 0.8
	tractorBeam.Width1 = 0.3
	tractorBeam.Transparency = NumberSequence.new(0.35)
	tractorBeam.LightEmission = 1
	tractorBeam.FaceCamera = true
	tractorBeam.Parent = cargoBox
	table.insert(beams, tractorBeam)

	cargoModel.Parent = dronePart

	local self: CargoInstance = {
		rootPart = dronePart,
		cargoModel = cargoModel,
		cargoBox = cargoBox,
		weld = weld,
		beams = beams,
		isLoaded = true,
		-- NUEVO: estado de masa e inercia
		cargoMass    = CARGO_MASS_DEFAULT,
		inertiaAlpha = INERTIA_ALPHA_DEFAULT,
		isUnstable   = false,
	}

	return setmetatable(self, DroneCargo) :: any
end

function DroneCargo.DeliverAndReload(self: CargoInstance, dropPosition: Vector3)
	if not self.isLoaded then
		print("[DroneCargo] No hay carga para soltar actualmente (recargando...).")
		return
	end

	self.isLoaded = false
	print("[DroneCargo] ¡Soltando paquete de entrega físicamente por gravedad!")

	-- 1. Apagar haz tractor magnético
	for _, beam in ipairs(self.beams) do
		beam.Enabled = false
	end

	-- 2. Desenganchar físicamente el contenedor del dron
	if self.weld and self.weld.Parent then
		self.weld:Destroy()
	end

	-- 3. Habilitar físicas completas en el paquete que cae
	local droppedBox = self.cargoBox
	if droppedBox and droppedBox.Parent then
		droppedBox.Massless = false
		droppedBox.CanCollide = true
		droppedBox.Anchored = false

		-- Transferir inercia real del vuelo + impulso hacia el helipuerto
		local droneVel = self.rootPart.AssemblyLinearVelocity
		droppedBox.AssemblyLinearVelocity = droneVel + Vector3.new(0, -6, 0)
		droppedBox.AssemblyAngularVelocity = Vector3.new(math.random(-2, 2), math.random(-2, 2), math.random(-2, 2))

		-- Mover el modelo al Workspace exterior para que caiga libremente
		if self.cargoModel then
			self.cargoModel.Parent = workspace
			game:GetService("Debris"):AddItem(self.cargoModel, 25)
		end
	end

	-- 4. Efecto de audio de desacople magnético
	local releaseSound = Instance.new("Sound")
	releaseSound.SoundId = "rbxassetid://9114223170"
	releaseSound.Volume = 0.8
	releaseSound.Parent = self.rootPart
	releaseSound:Play()
	game:GetService("Debris"):AddItem(releaseSound, 2)

	-- 5. Recargar un nuevo paquete fresco tras 1.5 segundos
	task.delay(1.5, function()
		if not self.rootPart or not self.rootPart.Parent then return end
		self:ReloadFreshCargo()
	end)
end

function DroneCargo.ReloadFreshCargo(self: CargoInstance)
	local dronePart = self.rootPart

	local cargoModel = Instance.new("Model")
	cargoModel.Name = "DroneCargoContainer"

	local cargoBox = Instance.new("Part")
	cargoBox.Name = "CargoBox"
	cargoBox.Size = Vector3.new(2.8, 1.8, 2.8)
	cargoBox.Material = Enum.Material.Metal
	cargoBox.Color = COLOR_CARGO_BODY
	cargoBox.CanCollide = false
	cargoBox.Massless = true
	cargoBox.CFrame = dronePart.CFrame * CFrame.new(0, -dronePart.Size.Y * 0.7 - 1.2, 0)
	cargoBox.Parent = cargoModel

	local cargoBand = Instance.new("Part")
	cargoBand.Name = "NeonBand"
	cargoBand.Size = Vector3.new(2.9, 0.4, 2.9)
	cargoBand.Material = Enum.Material.Neon
	cargoBand.Color = if self.isUnstable then Color3.fromRGB(255, 160, 0) else COLOR_CARGO_NEON
	cargoBand.CanCollide = false
	cargoBand.Massless = true
	cargoBand.CFrame = cargoBox.CFrame
	cargoBand.Parent = cargoModel

	local bandWeld = Instance.new("WeldConstraint")
	bandWeld.Part0 = cargoBox
	bandWeld.Part1 = cargoBand
	bandWeld.Parent = cargoBox

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = dronePart
	weld.Part1 = cargoBox
	weld.Parent = cargoBox

	local attDrone = dronePart:FindFirstChild("TractorAttDrone") :: Attachment?
	if not attDrone then
		attDrone = Instance.new("Attachment")
		attDrone.Name = "TractorAttDrone"
		attDrone.Position = Vector3.new(0, -dronePart.Size.Y * 0.5, 0)
		attDrone.Parent = dronePart
	end

	local attCargo = Instance.new("Attachment")
	attCargo.Name = "TractorAttCargo"
	attCargo.Position = Vector3.new(0, cargoBox.Size.Y * 0.5, 0)
	attCargo.Parent = cargoBox

	table.clear(self.beams)
	local tractorBeam = Instance.new("Beam")
	tractorBeam.Name = "TractorBeam"
	tractorBeam.Attachment0 = attDrone
	tractorBeam.Attachment1 = attCargo
	tractorBeam.Color = ColorSequence.new(if self.isUnstable then Color3.fromRGB(255, 160, 0) else COLOR_CARGO_NEON)
	tractorBeam.Width0 = 0.8
	tractorBeam.Width1 = 0.3
	tractorBeam.Transparency = NumberSequence.new(0.35)
	tractorBeam.LightEmission = 1
	tractorBeam.FaceCamera = true
	tractorBeam.Parent = cargoBox
	table.insert(self.beams, tractorBeam)

	cargoModel.Parent = dronePart

	self.cargoModel = cargoModel
	self.cargoBox   = cargoBox
	self.weld       = weld
	self.isLoaded   = true

	print("[DroneCargo] ¡Nuevo contenedor de mercancía acoplado al dron!")
end

function DroneCargo.Destroy(self: CargoInstance)
	if self.cargoModel then
		self.cargoModel:Destroy()
	end
end

----------------------------------------------------------------------
-- EXTENSIONES: MASA REAL E INERCIA DINÁMICA
----------------------------------------------------------------------

-- Configura la masa del paquete actual y si es inestable (detona en impacto fuerte)
function DroneCargo.SetCargo(self: CargoInstance, massKg: number, inertiaAlpha: number, unstable: boolean?)
	self.cargoMass    = math.max(0, massKg)
	self.inertiaAlpha = math.max(0.001, inertiaAlpha)
	self.isUnstable   = unstable or false

	-- Cambio visual: carga inestable tiene neón ámbar de advertencia
	local band = self.cargoModel:FindFirstChild("NeonBand") :: BasePart?
	if band then
		if self.isUnstable then
			band.Color = Color3.fromRGB(255, 160, 0)  -- ámbar de peligro
		else
			band.Color = Color3.fromRGB(0, 255, 230)  -- cian estándar
		end
	end

	print(string.format("[DroneCargo] Carga configurada: %.1f kg, α=%.3f, inestable=%s",
		massKg, inertiaAlpha, tostring(self.isUnstable)))
end

-- Calcula la velocidad efectiva según la masa de la carga
-- VelocidadEfectiva = VelocidadBase / (1 + (MasaCarga * InerciaAlpha))
function DroneCargo.GetSpeedMultiplier(self: CargoInstance): number
	if not self.isLoaded or self.cargoMass <= 0 then return 1.0 end
	local factor = 1 + (self.cargoMass * self.inertiaAlpha)
	return math.max(0.3, 1.0 / factor)  -- mínimo 30% de velocidad base
end

-- Evalúa energía cinética en impacto y detona si supera umbral (carga inestable)
-- Llamado desde DroneController al detectar una colisión a alta velocidad
-- Ek = 0.5 * MasaTotal * |velocidad|²
function DroneCargo.EvaluateImpact(self: CargoInstance, droneMassKg: number, impactSpeed: number): boolean
	if not self.isLoaded or not self.isUnstable then return false end

	local totalMass = droneMassKg + self.cargoMass
	local ek = 0.5 * totalMass * (impactSpeed * impactSpeed)

	if ek >= EK_DETONATION_THRESHOLD then
		warn(string.format("[DroneCargo] ¡DETONACIÓN! Ek=%.0f J > umbral %.0f J (masa=%.1f kg, v=%.1f studs/s)",
			ek, EK_DETONATION_THRESHOLD, totalMass, impactSpeed))
		self:Detonate()
		return true
	end
	return false
end

-- Detonación de la carga: explosión en Workspace y destrucción del contenedor
function DroneCargo.Detonate(self: CargoInstance)
	local pos = self.cargoBox.Position

	local explosion = Instance.new("Explosion")
	explosion.Position       = pos
	explosion.BlastRadius    = 18
	explosion.BlastPressure  = 5e5
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType  = Enum.ExplosionType.NoCraters
	explosion.Parent         = workspace
	game:GetService("Debris"):AddItem(explosion, 3)

	self.isLoaded = false
	self.isUnstable = false
	if self.cargoModel then
		game:GetService("Debris"):AddItem(self.cargoModel, 0.5)
	end
end

return DroneCargo

