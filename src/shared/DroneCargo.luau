--!strict
-- src/shared/DroneCargo.luau
-- Sistema de Contenedor y Carga Magnética con Haz Tractor
local DroneCargo = {}
DroneCargo.__index = DroneCargo

export type CargoInstance = {
	rootPart: BasePart,
	cargoModel: Model,
	cargoBox: BasePart,
	weld: WeldConstraint,
	beams: { Beam },
	isLoaded: boolean,
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
	}

	return setmetatable(self, DroneCargo) :: any
end

function DroneCargo.DeliverAndReload(self: CargoInstance, dropPosition: Vector3)
	-- Efecto visual: dejar una copia decorativa en el helipuerto y recargar una nueva carga
	local deliveredCrate = self.cargoBox:Clone()
	deliveredCrate.CanCollide = true
	deliveredCrate.Massless = false
	deliveredCrate.Anchored = true
	deliveredCrate.CFrame = CFrame.new(dropPosition + Vector3.new(0, 1.2, 0))
	deliveredCrate.Parent = workspace

	-- Destruir la caja anterior tras 20 segundos para no saturar memoria
	game:GetService("Debris"):AddItem(deliveredCrate, 20)

	-- Parpadear el haz tractor (simulando recarga de carga)
	for _, beam in ipairs(self.beams) do
		beam.Enabled = false
		task.delay(0.6, function()
			beam.Enabled = true
		end)
	end
end

function DroneCargo.Destroy(self: CargoInstance)
	if self.cargoModel then
		self.cargoModel:Destroy()
	end
end

return DroneCargo

