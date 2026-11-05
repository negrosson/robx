--!strict
-- src/shared/DeliveryManager.luau
-- Gestor de Misiones, Detección de Aterrizaje y Despacho de Entregas con Validación
-- Soporta: Aterrizaje progresivo automático (0.55s) y entrega manual con tecla [G]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local NetworkEvents: any = nil
pcall(function()
	local neMod = ReplicatedStorage:FindFirstChild("NetworkEvents") :: ModuleScript?
	if not neMod then
		neMod = ReplicatedStorage:WaitForChild("NetworkEvents", 10) :: ModuleScript?
	end
	if neMod then
		NetworkEvents = require(neMod)
	end
end)

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
	claimEvent: RemoteEvent?,
	confirmedEvent: RemoteEvent?,
	confirmedConn: RBXScriptConnection?,
	onDeliveryCallback: ((reward: number, padName: string) => ())?,
}

-- Tolerancias de aterrizaje generosas para jugabilidad fluida
local MAX_HORIZ_DIST = 30     -- studs desde el centro del helipuerto
local MIN_VERT_DIFF  = -4     -- studs debajo de la superficie del helipuerto
local MAX_VERT_DIFF  = 22     -- studs sobre la superficie (permite vuelo estacionario cómodo)
local MAX_SAFE_SPEED = 35     -- studs/s velocidad máxima para autorizar entrega
local TOUCHDOWN_TIME = 0.60   -- segundos continuos necesarios para auto-entrega

local function getPadDisplayName(padName: string): string
	if padName == "Pad_Base" then
		return "Base"
	elseif padName == "Pad_TorreA" then
		return "Torre A"
	elseif padName == "Pad_TorreB" then
		return "Torre B"
	else
		return padName:gsub("Pad_", ""):gsub("(%u)", " %1"):gsub("^%s+", "")
	end
end

local function resolveRemote(eventName: string): RemoteEvent?
	local ev: RemoteEvent? = nil
	if NetworkEvents and NetworkEvents.Get then
		pcall(function() ev = NetworkEvents.Get(eventName) end)
	end
	if not ev then
		local evFolder = ReplicatedStorage:FindFirstChild("CyberNetworkEvents")
		if evFolder then
			ev = evFolder:FindFirstChild(eventName) :: RemoteEvent?
		end
	end
	if not ev then
		ev = ReplicatedStorage:FindFirstChild(eventName) :: RemoteEvent?
	end
	if not ev then
		pcall(function()
			ev = ReplicatedStorage:WaitForChild(eventName, 3) :: RemoteEvent?
		end)
	end
	return ev
end

function DeliveryManager.new(): ManagerInstance
	local claimEvent = resolveRemote("DeliveryCompleted")
	local confirmedEvent = resolveRemote("DeliveryConfirmed")

	local padsFolder = Workspace:FindFirstChild("LandingPads") :: Folder?
	if not padsFolder then
		pcall(function()
			padsFolder = Workspace:WaitForChild("LandingPads", 4) :: Folder?
		end)
	end

	local targets: { DeliveryTarget } = {}

	local function scanPads()
		local folder = Workspace:FindFirstChild("LandingPads") :: Folder?
		if not folder then return end
		table.clear(targets)

		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") then
				local basePart = child:FindFirstChild("BasePad") :: BasePart?
				if basePart then
					local displayName = getPadDisplayName(child.Name)
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
			name = "Pad_Base",
			displayName = "Base",
			model = nil,
			position = Vector3.new(0, 6, 0),
			basePadPosition = Vector3.new(0, 4, 0),
			reward = 250,
		})
		table.insert(targets, {
			name = "Pad_TorreA",
			displayName = "Torre A",
			model = nil,
			position = Vector3.new(160, 97, -180),
			basePadPosition = Vector3.new(160, 95, -180),
			reward = 250,
		})
		table.insert(targets, {
			name = "Pad_TorreB",
			displayName = "Torre B",
			model = nil,
			position = Vector3.new(-200, 52, 140),
			basePadPosition = Vector3.new(-200, 50, 140),
			reward = 250,
		})
	end

	-- Buscar Pad_TorreA como destino inicial (el jugador inicia en Base)
	local startIndex = 1
	for idx, tgt in ipairs(targets) do
		if tgt.name == "Pad_TorreA" then
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
		originPadName = "Pad_Base",
		touchdownTimer = 0,
		isLanded = false,
		currentZonePadName = nil,
		claimEvent = claimEvent,
		confirmedEvent = confirmedEvent,
		confirmedConn = nil,
		onDeliveryCallback = nil,
	}

	-- Auto-refrescar cuando se repliquen helipuertos del servidor
	if padsFolder then
		padsFolder.ChildAdded:Connect(function()
			task.wait(0.2)
			self:RefreshTargets()
		end)
	end

	-- Escuchar confirmación validada del servidor
	if confirmedEvent then
		self.confirmedConn = confirmedEvent.OnClientEvent:Connect(function(padName: string, reward: number)
			print(string.format("[DeliveryManager] ¡Servidor confirmó entrega en %s! (+%d ₵)", padName, reward))

			-- Actualizar helipuerto de origen al recién completado
			self.originPadName = padName

			-- Buscar nombre visible
			local displayName = getPadDisplayName(padName)
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
	else
		task.spawn(function()
			local ev = resolveRemote("DeliveryConfirmed")
			if ev and not self.confirmedConn then
				self.confirmedEvent = ev
				self.confirmedConn = ev.OnClientEvent:Connect(function(padName: string, reward: number)
					print(string.format("[DeliveryManager] ¡Servidor confirmó entrega en %s! (+%d ₵)", padName, reward))
					self.originPadName = padName
					local displayName = getPadDisplayName(padName)
					for _, tgt in ipairs(self.targets) do
						if tgt.name == padName then
							displayName = tgt.displayName
							break
						end
					end
					if self.onDeliveryCallback then
						self.onDeliveryCallback(reward, displayName)
					end
					self:PickNextTarget(padName)
				end)
			end
		end)
	end

	-- Escuchar rechazo de entrega para resetear estado
	pcall(function()
		local rejectedEvent = resolveRemote("DeliveryRejected")
		if rejectedEvent then
			rejectedEvent.OnClientEvent:Connect(function(reason: string)
				warn("[DeliveryManager] Servidor rechazó entrega:", reason)
				self.isLanded = false
				self.touchdownTimer = 0
			end)
		end
	end)

	local initialTarget = self.targets[self.currentTargetIndex]
	local initialName = if initialTarget then initialTarget.displayName else "Torre A"
	print(string.format("[DeliveryManager] Inicializado con %d helipuertos. Objetivo inicial: %s",
		#targets, initialName))

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
				local displayName = getPadDisplayName(child.Name)
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
): (boolean, DeliveryTarget?, number, string?)
	local speed = droneVelocity.Magnitude
	if speed > MAX_SAFE_SPEED then
		return false, nil, 0, string.format("Velocidad alta (%.0f studs/s, máx 35). Frena con [X].", speed)
	end

	local closestTarget: DeliveryTarget? = nil
	local closestDist = math.huge

	-- 1. Primero comprobar si está sobre su objetivo asignado
	local currentTgt = self:GetCurrentTarget()
	if currentTgt then
		local hDist = Vector3.new(dronePosition.X - currentTgt.basePadPosition.X, 0, dronePosition.Z - currentTgt.basePadPosition.Z).Magnitude
		local vDiff = dronePosition.Y - currentTgt.basePadPosition.Y
		if hDist <= MAX_HORIZ_DIST and vDiff >= MIN_VERT_DIFF and vDiff <= MAX_VERT_DIFF then
			return true, currentTgt, currentTgt.reward, nil
		end
	end

	-- 2. Comprobar si está sobre cualquier otro helipuerto de la red
	for _, tgt in ipairs(self.targets) do
		local horizDist = Vector3.new(dronePosition.X - tgt.basePadPosition.X, 0, dronePosition.Z - tgt.basePadPosition.Z).Magnitude
		local vertDiff = dronePosition.Y - tgt.basePadPosition.Y

		if horizDist < closestDist then
			closestDist = horizDist
			closestTarget = tgt
		end

		if horizDist <= MAX_HORIZ_DIST and vertDiff >= MIN_VERT_DIFF and vertDiff <= MAX_VERT_DIFF then
			-- Si es el mismo helipuerto de origen de donde recién despegó:
			if tgt.name == self.originPadName then
				return false, tgt, 0, string.format("Ya estás en %s. Vuela hacia %s", tgt.displayName, currentTgt and currentTgt.displayName or "tu objetivo")
			end
			return true, tgt, tgt.reward, nil
		end
	end

	-- Fuera de zona: dar indicación clara al jugador
	local hint = if closestTarget
		then string.format("Helipuerto más cercano: %s a %.0f studs", closestTarget.displayName, closestDist)
		else "No hay helipuertos detectados en rango"

	return false, closestTarget, 0, hint
end

-- Actualización por frame en el loop de vuelo
function DeliveryManager.Update(
	self: ManagerInstance,
	dt: number,
	dronePosition: Vector3,
	droneVelocity: Vector3
): (boolean, number)
	local inZone, target, _, _ = self:CheckPadZone(dronePosition, droneVelocity)

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
function DeliveryManager.TryManualDeliver(self: ManagerInstance, dronePosition: Vector3, droneVelocity: Vector3): (boolean, string?)
	local inZone, target, _, hint = self:CheckPadZone(dronePosition, droneVelocity)
	if inZone and target then
		print(string.format("[DeliveryManager] ¡Entrega manual [G] ejecutada en %s!", target.displayName))
		self:CompleteDelivery(target.name)
		return true, string.format("¡Entregando en %s!", target.displayName)
	else
		local reason = hint or "Debes estar sobre un helipuerto para entregar"
		print("[DeliveryManager] [G] Rechazado:", reason)
		return false, reason
	end
end

-- Envía la solicitud de reclamo al servidor
function DeliveryManager.CompleteDelivery(self: ManagerInstance, padName: string)
	if not self.claimEvent then
		self.claimEvent = resolveRemote("DeliveryCompleted")
	end
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
