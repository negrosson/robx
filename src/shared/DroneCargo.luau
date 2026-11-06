--!strict
-- src/shared/DroneCargo.luau
-- Sistema de Bahía de Carga (Capacidad: 3 Paquetes) con Haces Tractores Magnéticos e Inercia Dinámica
local Debris = game:GetService("Debris")

local DroneCargo = {}
DroneCargo.__index = DroneCargo

-- Constantes de física de carga
local MAX_CARGO_CAPACITY = 3
local INERTIA_ALPHA_DEFAULT = 0.025
local CARGO_MASS_PER_PKG = 5.0 -- 5 kg por paquete (15 kg carga completa)
local EK_DETONATION_THRESHOLD = 4000

local COLOR_CARGO_NEON = Color3.fromRGB(0, 255, 230)
local COLOR_CARGO_BODY = Color3.fromRGB(20, 25, 35)

export type CargoPackage = {
	model: Model,
	box: BasePart,
	band: BasePart,
	weld: WeldConstraint,
	beam: Beam,
	index: number,
}

export type CargoInstance = {
	rootPart: BasePart,
	cargoContainer: Model,
	packages: { CargoPackage },
	packagesCount: number,
	maxPackages: number,
	isLoaded: boolean,
	cargoMass: number,
	inertiaAlpha: number,
	isUnstable: boolean,
}

-- Offsets horizontales bajo la panza del dron para los 3 paquetes
local PACKAGE_OFFSETS = {
	Vector3.new(-1.25, -1.2, 0), -- Paquete 1 (Izquierda)
	Vector3.new( 0.00, -1.2, 0), -- Paquete 2 (Centro)
	Vector3.new( 1.25, -1.2, 0), -- Paquete 3 (Derecha)
}

local function createSinglePackage(dronePart: BasePart, index: number, offset: Vector3): CargoPackage
	local pkgModel = Instance.new("Model")
	pkgModel.Name = "CargoPackage_" .. tostring(index)

	-- Caja física del paquete
	local cargoBox = Instance.new("Part")
	cargoBox.Name = "CargoBox"
	cargoBox.Size = Vector3.new(1.15, 1.0, 2.2)
	cargoBox.Material = Enum.Material.Metal
	cargoBox.Color = COLOR_CARGO_BODY
	cargoBox.CanCollide = false
	cargoBox.Massless = true
	cargoBox.CFrame = dronePart.CFrame * CFrame.new(offset)
	cargoBox.Parent = pkgModel

	-- Tira luminosa perimetral de neón
	local cargoBand = Instance.new("Part")
	cargoBand.Name = "NeonBand"
	cargoBand.Size = Vector3.new(1.2, 0.25, 2.25)
	cargoBand.Material = Enum.Material.Neon
	cargoBand.Color = COLOR_CARGO_NEON
	cargoBand.CanCollide = false
	cargoBand.Massless = true
	cargoBand.CFrame = cargoBox.CFrame
	cargoBand.Parent = pkgModel

	local bandWeld = Instance.new("WeldConstraint")
	bandWeld.Part0 = cargoBox
	bandWeld.Part1 = cargoBand
	bandWeld.Parent = cargoBox

	-- Unión física con el chasis del dron
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = dronePart
	weld.Part1 = cargoBox
	weld.Parent = cargoBox

	-- Haz tractor magnético individual
	local attDrone = Instance.new("Attachment")
	attDrone.Name = "TractorAttDrone_" .. tostring(index)
	attDrone.Position = Vector3.new(offset.X, -dronePart.Size.Y * 0.5, 0)
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
	tractorBeam.Width0 = 0.4
	tractorBeam.Width1 = 0.15
	tractorBeam.Transparency = NumberSequence.new(0.3)
	tractorBeam.LightEmission = 1
	tractorBeam.FaceCamera = true
	tractorBeam.Parent = cargoBox

	return {
		model = pkgModel,
		box   = cargoBox,
		band  = cargoBand,
		weld  = weld,
		beam  = tractorBeam,
		index = index,
	}
end

function DroneCargo.new(dronePart: BasePart): CargoInstance
	local existingCargo = dronePart:FindFirstChild("DroneCargoContainer")
	if existingCargo then
		existingCargo:Destroy()
	end

	local cargoContainer = Instance.new("Model")
	cargoContainer.Name = "DroneCargoContainer"
	cargoContainer.Parent = dronePart

	local packages: { CargoPackage } = {}
	for i = 1, MAX_CARGO_CAPACITY do
		local pkg = createSinglePackage(dronePart, i, PACKAGE_OFFSETS[i])
		pkg.model.Parent = cargoContainer
		table.insert(packages, pkg)
	end

	local self: CargoInstance = {
		rootPart       = dronePart,
		cargoContainer = cargoContainer,
		packages       = packages,
		packagesCount  = #packages,
		maxPackages    = MAX_CARGO_CAPACITY,
		isLoaded       = true,
		cargoMass      = #packages * CARGO_MASS_PER_PKG,
		inertiaAlpha   = INERTIA_ALPHA_DEFAULT,
		isUnstable     = false,
	}

	print(string.format("[DroneCargo v5] Bodega de carga inicializada: %d/%d paquetes listos.", self.packagesCount, self.maxPackages))
	return setmetatable(self, DroneCargo) :: any
end

-- Desacopla y entrega un único paquete físicamente en el helipuerto
function DroneCargo.DeliverOnePackage(self: CargoInstance, dropPosition: Vector3): (boolean, number)
	if self.packagesCount <= 0 or #self.packages == 0 then
		print("[DroneCargo] ¡Bodega vacía! No quedan paquetes para entregar. Regresa a Base.")
		return false, 0
	end

	-- Despachar el último paquete de la fila
	local pkg = table.remove(self.packages)
	if not pkg then return false, 0 end

	print(string.format("[DroneCargo] ¡Soltando paquete #%d físicamente por gravedad!", pkg.index))

	-- 1. Apagar haz tractor y romper soldadura magnética
	if pkg.beam then pkg.beam.Enabled = false end
	if pkg.weld and pkg.weld.Parent then pkg.weld:Destroy() end

	-- 2. Activar colisiones y física completa en el paquete que cae
	local droppedBox = pkg.box
	if droppedBox and droppedBox.Parent then
		droppedBox.Massless = false
		droppedBox.CanCollide = true
		droppedBox.Anchored = false

		-- Transferir inercia real del vuelo + empuje hacia el helipuerto
		local droneVel = self.rootPart.AssemblyLinearVelocity
		droppedBox.AssemblyLinearVelocity = droneVel + Vector3.new(0, -6, 0)
		droppedBox.AssemblyAngularVelocity = Vector3.new(math.random(-2, 2), math.random(-2, 2), math.random(-2, 2))

		-- Rótulo holográfico en el paquete entregado
		local bbg = Instance.new("BillboardGui")
		bbg.Name = "DeliveredTag"
		bbg.Size = UDim2.fromOffset(180, 36)
		bbg.StudsOffset = Vector3.new(0, 1.4, 0)
		bbg.AlwaysOnTop = true
		bbg.MaxDistance = 120

		local tagLabel = Instance.new("TextLabel")
		tagLabel.Size = UDim2.fromScale(1, 1)
		tagLabel.BackgroundTransparency = 1
		tagLabel.Font = Enum.Font.Code
		tagLabel.Text = "ENTREGADO // [VERIFICADO]"
		tagLabel.TextColor3 = Color3.fromRGB(0, 255, 180)
		tagLabel.TextSize = 13
		tagLabel.TextStrokeTransparency = 0.2
		tagLabel.Parent = bbg
		bbg.Parent = droppedBox

		-- Mover el modelo entregado a Workspace para que se asiente en la torre
		if pkg.model then
			pkg.model.Parent = workspace
			Debris:AddItem(pkg.model, 35)
		end
	end

	-- 3. Sonido de desacople magnético
	local releaseSound = Instance.new("Sound")
	releaseSound.SoundId = "rbxassetid://9114223170"
	releaseSound.Volume = 0.8
	releaseSound.Parent = self.rootPart
	releaseSound:Play()
	Debris:AddItem(releaseSound, 2)

	-- 4. Actualizar estado
	self.packagesCount = #self.packages
	self.isLoaded = (self.packagesCount > 0)
	self.cargoMass = self.packagesCount * CARGO_MASS_PER_PKG

	print(string.format("[DroneCargo] Paquete entregado. Quedan %d/%d en bodega.", self.packagesCount, self.maxPackages))
	return true, self.packagesCount
end

-- Reabastece completamente la bodega de carga en la Base Central
function DroneCargo.RestockAtBase(self: CargoInstance): (boolean, number)
	if self.packagesCount >= self.maxPackages and self.isLoaded then
		return false, self.packagesCount
	end

	-- Limpiar cualquier resto previo
	for _, pkg in ipairs(self.packages) do
		if pkg.model and pkg.model.Parent then pkg.model:Destroy() end
	end
	table.clear(self.packages)

	if not self.cargoContainer or not self.cargoContainer.Parent then
		self.cargoContainer = Instance.new("Model")
		self.cargoContainer.Name = "DroneCargoContainer"
		self.cargoContainer.Parent = self.rootPart
	else
		self.cargoContainer:ClearAllChildren()
	end

	-- Generar los 3 paquetes nuevos
	for i = 1, self.maxPackages do
		local pkg = createSinglePackage(self.rootPart, i, PACKAGE_OFFSETS[i])
		pkg.model.Parent = self.cargoContainer
		table.insert(self.packages, pkg)
	end

	self.packagesCount = self.maxPackages
	self.isLoaded      = true
	self.cargoMass     = self.maxPackages * CARGO_MASS_PER_PKG

	-- Sonido de reabastecimiento en hangar
	local reloadSound = Instance.new("Sound")
	reloadSound.SoundId = "rbxassetid://9114223170"
	reloadSound.Volume = 1.0
	reloadSound.PlaybackSpeed = 1.2
	reloadSound.Parent = self.rootPart
	reloadSound:Play()
	Debris:AddItem(reloadSound, 3)

	print("[DroneCargo] ¡Bodega completamente reabastecida en Base! 3/3 paquetes disponibles.")
	return true, self.packagesCount
end

function DroneCargo.GetPackageCount(self: CargoInstance): number
	return self.packagesCount
end

function DroneCargo.GetMaxPackages(self: CargoInstance): number
	return self.maxPackages
end

-- Compatibilidad hacia atrás con DeliverAndReload
function DroneCargo.DeliverAndReload(self: CargoInstance, dropPosition: Vector3)
	self:DeliverOnePackage(dropPosition)
end

function DroneCargo.Destroy(self: CargoInstance)
	if self.cargoContainer then
		self.cargoContainer:Destroy()
	end
end

----------------------------------------------------------------------
-- EXTENSIONES: MASA REAL E INERCIA DINÁMICA
----------------------------------------------------------------------
function DroneCargo.SetCargo(self: CargoInstance, massKg: number, inertiaAlpha: number, unstable: boolean?)
	self.cargoMass    = math.max(0, massKg)
	self.inertiaAlpha = math.max(0.001, inertiaAlpha)
	self.isUnstable   = unstable or false

	for _, pkg in ipairs(self.packages) do
		if pkg.band then
			pkg.band.Color = if self.isUnstable then Color3.fromRGB(255, 160, 0) else COLOR_CARGO_NEON
		end
	end
end

-- Multiplicador dinámico: más cargado = más pesado; vacío = más veloz y ágil
function DroneCargo.GetSpeedMultiplier(self: CargoInstance): number
	if self.packagesCount == 3 then
		return 0.88  -- 3 paquetes: pesado y con inercia
	elseif self.packagesCount == 2 then
		return 0.94  -- 2 paquetes
	elseif self.packagesCount == 1 then
		return 0.98  -- 1 paquete
	else
		return 1.06  -- 0 paquetes: ágil y veloz de regreso a base
	end
end

function DroneCargo.EvaluateImpact(self: CargoInstance, droneMassKg: number, impactSpeed: number): boolean
	if not self.isLoaded or not self.isUnstable then return false end
	local totalMass = droneMassKg + self.cargoMass
	local ek = 0.5 * totalMass * (impactSpeed * impactSpeed)

	if ek >= EK_DETONATION_THRESHOLD then
		self:Detonate()
		return true
	end
	return false
end

function DroneCargo.Detonate(self: CargoInstance)
	local pos = self.rootPart.Position
	local explosion = Instance.new("Explosion")
	explosion.Position = pos
	explosion.BlastRadius = 18
	explosion.BlastPressure = 5e5
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace
	Debris:AddItem(explosion, 3)

	for _, pkg in ipairs(self.packages) do
		if pkg.model then pkg.model:Destroy() end
	end
	table.clear(self.packages)
	self.packagesCount = 0
	self.isLoaded = false
end

return DroneCargo
