--!strict
-- src/shared/DeliveryManager.luau
-- Gestor de Misiones, Detección de Aterrizaje y Despacho de Entregas con Validación
-- Soporta: Aterrizaje progresivo automático (0.55s) y entrega manual con tecla [G]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local NetworkEvents = require(script.Parent:WaitForChild("NetworkEvents", 5) :: ModuleScript)

local DeliveryManager = {}
DeliveryManager.__index = DeliveryManager

export type DeliveryTarget = {
	name: string,
	displayName: string,
	model: Model?,
	position: Vector3,
	basePadPosition: Vector3,
	reward: number,
}

export type ManagerInstance = {
	targets: { DeliveryTarget },
	currentTargetIndex: number,
	originPadName: string,
	touchdownTimer: number,
	isLanded: boolean,
	currentZonePadName: string?,
	claimEvent: RemoteEvent,
	confirmedEvent: RemoteEvent,
	confirmedConn: RBXScriptConnection?,
	onDeliveryCallback: ((reward: number, padName: string) => ())?,
}

-- Tolerancias de aterrizaje generosas para jugabilidad fluida
local MAX_HORIZ_DIST = 22     -- studs desde el centro del helipuerto
local MIN_VERT_DIFF  = -2     -- studs debajo de la superficie del helipuerto
local MAX_VERT_DIFF  = 12     -- studs sobre la superficie (permite vuelo estacionario bajo)
local MAX_SAFE_SPEED = 25     -- studs/s velocidad máxima para autorizar entrega
local TOUCHDOWN_TIME = 0.55   -- segundos continuos necesarios para auto-entrega

function DeliveryManager.new(): ManagerInstance
	local claimEvent = NetworkEvents.Get(NetworkEvents.Names.ClaimDelivery)
	local confirmedEvent = NetworkEvents.Get(NetworkEvents.Names.DeliveryConfirmed)
	local padsFolder = Workspace:WaitForChild("LandingPads", 10) :: Folder?

	local targets: { DeliveryTarget } = {}

	local function scanPads()
		local folder = Workspace:FindFirstChild("LandingPads") :: Folder?
		if not folder then return end
		table.clear(targets)

		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") then
				local basePart = child:FindFirstChild("BasePad") :: BasePart?
				if basePart then
					local displayName = child.Name:gsub("Pad_", ""):gsub("(%u)", " %1"):gsub("^%s+", "")
					table.insert(targets, {
						name = child.Name,
						displayName = displayName,
						model = child,
						position = basePart.Position + Vector3.new(0, 3, 0),
						basePadPosition = basePart.Position,
						reward = 250,
					})
				end
			end
		end
	end

	scanPads()

	-- Fallback por si los pads demoran en replicar
	if #targets == 0 then
		table.insert(targets, {
			name = "Pad_HangarCentral",
			displayName = "Hangar Central",
			model = nil,
			position = Vector3.new(0, 6, 0),
			basePadPosition = Vector3.new(0, 4, 0),
			reward = 250,
		})
		table.insert(targets, {
			name = "Pad_TorreArasaka",
			displayName = "Torre Arasaka",
			model = nil,
			position = Vector3.new(160, 97, -180),
			basePadPosition = Vector3.new(160, 95, -180),
			reward = 250,
		})
		table.insert(targets, {
			name = "Pad_DistritoNeon",
			displayName = "Distrito Neón",
			model = nil,
			position = Vector3.new(-200, 52, 140),
			basePadPosition = Vector3.new(-200, 50, 140),
			reward = 250,
		})
	end

	-- Buscar Pad_TorreArasaka como destino inicial (el jugador inicia en HangarCentral)
	local startIndex = 1
	for idx, tgt in ipairs(targets) do
		if tgt.name == "Pad_TorreArasaka" then
			startIndex = idx
			break
		end
	end
	if startIndex == 1 and #targets > 1 then
		startIndex = 2
	end

	local self: ManagerInstance = {
		targets = targets,
		currentTargetIndex = startIndex,
		originPadName = "Pad_HangarCentral",
		touchdownTimer = 0,
		isLanded = false,
		currentZonePadName = nil,
		claimEvent = claimEvent,
		confirmedEvent = confirmedEvent,
		confirmedConn = nil,
		onDeliveryCallback = nil,
	}

	-- Escuchar confirmación validada del servidor
	self.confirmedConn = confirmedEvent.OnClientEvent:Connect(function(padName: string, reward: number)
		print(string.format("[DeliveryManager] ¡Servidor confirmó entrega en %s! (+%d ₵)", padName, reward))

		-- Actualizar helipuerto de origen al recién completado
		self.originPadName = padName

		-- Buscar nombre visible
		local displayName = padName:gsub("Pad_", ""):gsub("(%u)", " %1"):gsub("^%s+", "")
		for _, tgt in ipairs(self.targets) do
			if tgt.name == padName then
				displayName = tgt.displayName
				break
			end
		end

		if self.onDeliveryCallback then
			self.onDeliveryCallback(reward, displayName)
		end

		-- Asignar nuevo objetivo aleatorio distinto al helipuerto actual
		self:PickNextTarget(padName)
	end)

	print(string.format("[DeliveryManager] Inicializado con %d helipuertos. Objetivo inicial: %s",
		#targets, targets[self.currentTargetIndex].displayName))

	return setmetatable(self, DeliveryManager) :: any
end

function DeliveryManager.RefreshTargets(self: ManagerInstance)
	local folder = Workspace:FindFirstChild("LandingPads")
	if not folder then return end

	local newTargets: { DeliveryTarget } = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			local basePart = child:FindFirstChild("BasePad") :: BasePart?
			if basePart then
				local displayName = child.Name:gsub("Pad_", ""):gsub("(%u)", " %1"):gsub("^%s+", "")
				table.insert(newTargets, {
					name = child.Name,
					displayName = displayName,
					model = child,
					position = basePart.Position + Vector3.new(0, 3, 0),
					basePadPosition = basePart.Position,
					reward = 250,
				})
			end
		end
	end

	if #newTargets >= 2 then
		self.targets = newTargets
	end
end

function DeliveryManager.GetCurrentTarget(self: ManagerInstance): DeliveryTarget
	if #self.targets <= 1 then
		self:RefreshTargets()
	end
	return self.targets[self.currentTargetIndex] or self.targets[1]
end

-- Selecciona el siguiente destino que no sea el recién entregado
function DeliveryManager.PickNextTarget(self: ManagerInstance, lastDeliveredPadName: string)
	if #self.targets <= 1 then return end

	local candidates: { number } = {}
	for idx, tgt in ipairs(self.targets) do
		if tgt.name ~= lastDeliveredPadName then
			table.insert(candidates, idx)
		end
	end

	if #candidates > 0 then
		self.currentTargetIndex = candidates[math.random(1, #candidates)]
	else
		self.currentTargetIndex = (self.currentTargetIndex % #self.targets) + 1
	end

	self.touchdownTimer = 0
	self.isLanded = false
	self.currentZonePadName = nil

	local newTarget = self:GetCurrentTarget()
	print(string.format("[DeliveryManager] Nuevo contrato asignado: %s (+%d ₵)", newTarget.displayName, newTarget.reward))
end

-- Comprueba si el dron está dentro de una zona de aterrizaje válida
function DeliveryManager.CheckPadZone(
	self: ManagerInstance,
	dronePosition: Vector3,
	droneVelocity: Vector3
): (boolean, DeliveryTarget?, number)
	local speed = droneVelocity.Magnitude
	if speed > MAX_SAFE_SPEED then
		return false, nil, 0
	end

	-- 1. Comprobar primero el objetivo primario (bono completo)
	local primary = self:GetCurrentTarget()
	if primary then
		local horizDist = Vector3.new(dronePosition.X - primary.basePadPosition.X, 0, dronePosition.Z - primary.basePadPosition.Z).Magnitude
		local vertDiff = dronePosition.Y - primary.basePadPosition.Y

		if horizDist <= MAX_HORIZ_DIST and vertDiff >= MIN_VERT_DIFF and vertDiff <= MAX_VERT_DIFF then
			return true, primary, primary.reward
		end
	end

	-- 2. Comprobar otros helipuertos secundarios si no es el helipuerto de despegue
	for _, tgt in ipairs(self.targets) do
		if tgt.name ~= self.originPadName and tgt.name ~= primary.name then
			local horizDist = Vector3.new(dronePosition.X - tgt.basePadPosition.X, 0, dronePosition.Z - tgt.basePadPosition.Z).Magnitude
			local vertDiff = dronePosition.Y - tgt.basePadPosition.Y

			if horizDist <= MAX_HORIZ_DIST and vertDiff >= MIN_VERT_DIFF and vertDiff <= MAX_VERT_DIFF then
				return true, tgt, 175  -- recompensa secundaria por entrega alternativa
			end
		end
	end

	return false, nil, 0
end

-- Actualización por frame en el loop de vuelo
function DeliveryManager.Update(
	self: ManagerInstance,
	dt: number,
	dronePosition: Vector3,
	droneVelocity: Vector3
): (boolean, number)
	local inZone, target, _ = self:CheckPadZone(dronePosition, droneVelocity)

	if inZone and target then
		self.currentZonePadName = target.name
		self.touchdownTimer += dt
		local progress = math.clamp(self.touchdownTimer / TOUCHDOWN_TIME, 0, 1)

		if progress >= 1 and not self.isLanded then
			self.isLanded = true
			self:CompleteDelivery(target.name)
			return true, 1
		end
		return false, progress
	else
		self.currentZonePadName = nil
		self.touchdownTimer = math.max(0, self.touchdownTimer - (dt * 2))
		self.isLanded = false
		return false, 0
	end
end

-- Entrega manual inmediata al presionar tecla [G] sobre la zona
function DeliveryManager.TryManualDeliver(self: ManagerInstance, dronePosition: Vector3, droneVelocity: Vector3): boolean
	local inZone, target, _ = self:CheckPadZone(dronePosition, droneVelocity)
	if inZone and target and not self.isLanded then
		self.isLanded = true
		print(string.format("[DeliveryManager] ¡Entrega manual [G] activada en %s!", target.displayName))
		self:CompleteDelivery(target.name)
		return true
	end
	return false
end

-- Envía la solicitud de reclamo al servidor
function DeliveryManager.CompleteDelivery(self: ManagerInstance, padName: string)
	if self.claimEvent then
		print(string.format("[DeliveryManager] Reclamando entrega en el servidor para '%s'...", padName))
		self.claimEvent:FireServer(padName)
	else
		warn("[DeliveryManager] No se pudo reclamar: claimEvent es nil")
	end
end

function DeliveryManager.SetOnDeliveryCallback(self: ManagerInstance, callback: (reward: number, padName: string) -> ())
	self.onDeliveryCallback = callback
end

function DeliveryManager.Destroy(self: ManagerInstance)
	if self.confirmedConn then
		self.confirmedConn:Disconnect()
		self.confirmedConn = nil
	end
	self.onDeliveryCallback = nil
end

return DeliveryManager
