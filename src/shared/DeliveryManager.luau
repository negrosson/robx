--!strict
-- src/shared/DeliveryManager.luau
-- Gestor de Misiones, Ciclo Logístico (3 Paquetes) y Reabastecimiento en Base Central
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

export type ThreatLevel = "safe" | "hostile" | "black_ops"

export type DeliveryTarget = {
	name: string,
	displayName: string,
	model: Model?,
	position: Vector3,
	basePadPosition: Vector3,
	reward: number,
	threatLevel: ThreatLevel,
	hazardInfo: string,
	timeBonusSeconds: number?,
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
	onDeliveryCallback: ((reward: number, padName: string, streak: number, multiplier: number) -> ())?,
	-- Control de inventario de bodega de 3 paquetes
	packagesRemaining: number,
	maxPackages: number,
	-- Fase 1: Sistema de Racha y Amenaza
	deliveryStreak: number,
	streakMultiplier: number,
	-- Fase 5: Contratos de Entrega Rápida (Rush Orders)
	rushOrderActive: boolean,
	rushTimeRemaining: number,
	rushTotalTime: number,
	rushMultiplier: number,
	-- Contador para reabastecimiento gratuito de misiles guiados (3 entregas)
	deliveriesCompletedSinceRestock: number,
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

local function getPadThreat(padName: string, position: Vector3?): (ThreatLevel, string, number)
	if padName == "Pad_Base" or padName == "Base" then
		return "safe", "ZONA VERDE // REABASTECIMIENTO Y DESPACHO", 100
	elseif padName == "Pad_TorreA" or padName == "Torre A" then
		return "hostile", "SECTOR INDUSTRIAL // NIDO SCAV-GNATS", 250
	elseif padName == "Pad_TorreB" or padName == "Torre B" then
		return "black_ops", "ESPACIO RESTRINGIDO // CORREDOR KUROSHIO", 400
	else
		local y = if position then position.Y else 50
		if y > 80 then
			return "black_ops", "ALTA ALTITUD // ALERTA DEFENSIVA", 400
		elseif y > 30 then
			return "hostile", "ZONA HOSTIL // PATRULLAS PIRATAS", 250
		else
			return "safe", "ZONA SEGURA // VUELO NOMINAL", 150
		end
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
					local threat, hazard, rwd = getPadThreat(child.Name, basePart.Position)
					table.insert(targets, {
						name = child.Name,
						displayName = displayName,
						model = child,
						position = basePart.Position + Vector3.new(0, 3, 0),
						basePadPosition = basePart.Position,
						reward = rwd,
						threatLevel = threat,
						hazardInfo = hazard,
						timeBonusSeconds = if threat == "black_ops" then 90 else nil,
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
			reward = 100,
			threatLevel = "safe",
			hazardInfo = "ZONA VERDE // REABASTECIMIENTO Y DESPACHO",
			timeBonusSeconds = nil,
		})
		table.insert(targets, {
			name = "Pad_TorreA",
			displayName = "Torre A",
			model = nil,
			position = Vector3.new(300, 117, -340),
			basePadPosition = Vector3.new(300, 115, -340),
			reward = 350,
			threatLevel = "hostile",
			hazardInfo = "SECTOR INDUSTRIAL // NIDO SCAV-GNATS",
			timeBonusSeconds = nil,
		})
		table.insert(targets, {
			name = "Pad_TorreB",
			displayName = "Torre B",
			model = nil,
			position = Vector3.new(-360, 67, 260),
			basePadPosition = Vector3.new(-360, 65, 260),
			reward = 500,
			threatLevel = "black_ops",
			hazardInfo = "ESPACIO RESTRINGIDO // CORREDOR KUROSHIO",
			timeBonusSeconds = 120,
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
		packagesRemaining = 3,
		maxPackages = 3,
		deliveryStreak = 0,
		streakMultiplier = 1.0,
		-- Fase 5
		rushOrderActive = false,
		rushTimeRemaining = 0,
		rushTotalTime = 0,
		rushMultiplier = 1.0,
		deliveriesCompletedSinceRestock = 0,
	}

	-- Auto-refrescar cuando se repliquen helipuertos del servidor
	if padsFolder then
		padsFolder.ChildAdded:Connect(function()
			task.wait(0.2)
			self:RefreshTargets()
		end)
	end

	local function onConfirmed(padName: string, reward: number, serverStreak: any, serverMultiplier: any)
		print(string.format("[DeliveryManager] ¡Servidor confirmó operación en %s! (+%d ₵)", padName, reward))
		self.originPadName = padName

		local isBase = (padName == "Pad_Base" or padName == "Base")
		if isBase then
			-- Reabastecimiento completo en Base (la racha no se reinicia al recargar)
			self.packagesRemaining = self.maxPackages
			print(string.format("[DeliveryManager] ¡Bodega reabastecida al 100%! 3 paquetes disponibles. Racha actual: x%d", self.deliveryStreak))
		else
			-- Entrega normal en una torre
			self.packagesRemaining = math.max(0, self.packagesRemaining - 1)
			self.deliveriesCompletedSinceRestock += 1
			if typeof(serverStreak) == "number" then
				self.deliveryStreak = serverStreak
			else
				self.deliveryStreak += 1
			end

			if typeof(serverMultiplier) == "number" then
				self.streakMultiplier = serverMultiplier
			else
				self.streakMultiplier = 1.0 + math.clamp((self.deliveryStreak - 1) * 0.10, 0, 0.50)
			end

			print(string.format("[DeliveryManager] Paquete entregado. Quedan %d/%d. ¡Racha: x%d (+%.0f%%)!",
				self.packagesRemaining, self.maxPackages, self.deliveryStreak, (self.streakMultiplier - 1) * 100))
		end

		local displayName = getPadDisplayName(padName)
		for _, tgt in ipairs(self.targets) do
			if tgt.name == padName then
				displayName = tgt.displayName
				break
			end
		end

		if self.onDeliveryCallback then
			self.onDeliveryCallback(reward, displayName, self.deliveryStreak, self.streakMultiplier)
		end

		-- Asignar el siguiente destino según la carga restante
		self:PickNextTarget(padName)
	end

	if confirmedEvent then
		self.confirmedConn = confirmedEvent.OnClientEvent:Connect(onConfirmed)
	else
		task.spawn(function()
			local ev = resolveRemote("DeliveryConfirmed")
			if ev and not self.confirmedConn then
				self.confirmedEvent = ev
				self.confirmedConn = ev.OnClientEvent:Connect(onConfirmed)
			end
		end)
	end

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
	print(string.format("[DeliveryManager v5] Inicializado: 3/3 paquetes. Primer objetivo: %s", initialName))

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
				local threat, hazard, rwd = getPadThreat(child.Name, basePart.Position)
				table.insert(newTargets, {
					name = child.Name,
					displayName = displayName,
					model = child,
					position = basePart.Position + Vector3.new(0, 3, 0),
					basePadPosition = basePart.Position,
					reward = rwd,
					threatLevel = threat,
					hazardInfo = hazard,
					timeBonusSeconds = if threat == "black_ops" then 90 else nil,
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

	-- Si nos quedamos sin paquetes, el único objetivo es la Base Central
	if self.packagesRemaining == 0 then
		for idx, tgt in ipairs(self.targets) do
			if tgt.name == "Pad_Base" then
				self.currentTargetIndex = idx
				return {
					name = tgt.name,
					displayName = "Base Central (Reabastecer)",
					model = tgt.model,
					position = tgt.position,
					basePadPosition = tgt.basePadPosition,
					reward = 100, -- Bono por completar la ruta
					threatLevel = "safe",
					hazardInfo = "BODEGA VACÍA // REGRESO A BASE REQUERIDO",
					timeBonusSeconds = nil,
				}
			end
		end
	end

	return self.targets[self.currentTargetIndex] or self.targets[1]
end

-- Selecciona el siguiente destino
function DeliveryManager.PickNextTarget(self: ManagerInstance, lastDeliveredPadName: string)
	if #self.targets <= 1 then return end

	-- Si ya no quedan paquetes, dirigir obligatoriamente a la Base Central
	if self.packagesRemaining <= 0 then
		for idx, tgt in ipairs(self.targets) do
			if tgt.name == "Pad_Base" then
				self.currentTargetIndex = idx
				print("[DeliveryManager] ¡BODEGA VACÍA! Asignando regreso a Base Central para reabastecimiento.")
				return
			end
		end
	end

	-- Si aún quedan paquetes, buscar torres distintas a la Base y a la última torre visitada
	local candidates: { number } = {}
	for idx, tgt in ipairs(self.targets) do
		if tgt.name ~= "Pad_Base" and tgt.name ~= lastDeliveredPadName then
			table.insert(candidates, idx)
		end
	end

	if #candidates > 0 then
		self.currentTargetIndex = candidates[math.random(1, #candidates)]
	else
		-- Si no hay otra torre candidata, alternar a cualquier torre disponible
		for idx, tgt in ipairs(self.targets) do
			if tgt.name ~= "Pad_Base" then
				self.currentTargetIndex = idx
				break
			end
		end
	end

	self.touchdownTimer = 0
	self.isLanded = false
	self.currentZonePadName = nil

	-- Fase 5: Asignación de Contratos de Entrega Prioritaria (Rush Orders)
	local isRush = (math.random(1, 100) <= 65)
	if isRush and self.packagesRemaining > 0 and self.currentTargetIndex > 0 then
		local tgt = self.targets[self.currentTargetIndex]
		if tgt and tgt.name ~= "Pad_Base" then
			self.rushOrderActive = true
			self.rushTotalTime = if tgt.threatLevel == "black_ops" then 60 else 45
			self.rushTimeRemaining = self.rushTotalTime
			self.rushMultiplier = 1.5
			print(string.format("[DeliveryManager] ¡CONTRATO RUSH ACTIVADO! %.0fs para entregar en %s (+50%% bonus)", self.rushTotalTime, tgt.displayName))
		else
			self.rushOrderActive = false
			self.rushTimeRemaining = 0
		end
	else
		self.rushOrderActive = false
		self.rushTimeRemaining = 0
	end

	local newTarget = self:GetCurrentTarget()
	print(string.format("[DeliveryManager] Siguiente destino: %s (+%d ₵ | Carga: %d/%d)",
		newTarget.displayName, newTarget.reward, self.packagesRemaining, self.maxPackages))
end

-- Comprueba si el dron está dentro de una zona válida de entrega o reabastecimiento
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

	-- 1. Primero comprobar el objetivo actual
	local currentTgt = self:GetCurrentTarget()
	if currentTgt then
		local hDist = Vector3.new(dronePosition.X - currentTgt.basePadPosition.X, 0, dronePosition.Z - currentTgt.basePadPosition.Z).Magnitude
		local vDiff = dronePosition.Y - currentTgt.basePadPosition.Y
		local maxH = if currentTgt.name == "Pad_Base" then 36 else MAX_HORIZ_DIST
		local minV = if currentTgt.name == "Pad_Base" then -6 else MIN_VERT_DIFF
		local maxV = if currentTgt.name == "Pad_Base" then 26 else MAX_VERT_DIFF

		if hDist <= maxH and vDiff >= minV and vDiff <= maxV then
			-- Si el objetivo es la Base para reabastecer:
			if currentTgt.name == "Pad_Base" then
				if self.packagesRemaining < self.maxPackages then
					return true, currentTgt, currentTgt.reward, nil
				else
					return false, currentTgt, 0, "Bodega completa (3/3 paquetes). Vuela hacia tu objetivo"
				end
			else
				-- Si es una torre y tenemos paquetes:
				if self.packagesRemaining > 0 then
					return true, currentTgt, currentTgt.reward, nil
				else
					return false, currentTgt, 0, "Bodega vacía. Vuela a Base Central a reabastecerte"
				end
			end
		end
	end

	-- 2. Comprobar si está sobre cualquier otro helipuerto de la red
	for _, tgt in ipairs(self.targets) do
		local horizDist = Vector3.new(dronePosition.X - tgt.basePadPosition.X, 0, dronePosition.Z - tgt.basePadPosition.Z).Magnitude
		local vertDiff = dronePosition.Y - tgt.basePadPosition.Y
		local maxH = if tgt.name == "Pad_Base" then 36 else MAX_HORIZ_DIST
		local minV = if tgt.name == "Pad_Base" then -6 else MIN_VERT_DIFF
		local maxV = if tgt.name == "Pad_Base" then 26 else MAX_VERT_DIFF

		if horizDist < closestDist then
			closestDist = horizDist
			closestTarget = tgt
		end

		if horizDist <= maxH and vertDiff >= minV and vertDiff <= maxV then
			-- Caso Base: si está en Base y no tiene carga completa, siempre permitir reabastecer
			if tgt.name == "Pad_Base" then
				if self.packagesRemaining < self.maxPackages then
					return true, tgt, 100, nil
				else
					return false, tgt, 0, "Ya tienes carga completa (3/3). Vuela a " .. (currentTgt and currentTgt.displayName or "tu objetivo")
				end
			end

			-- Caso Torre
			if self.packagesRemaining <= 0 then
				return false, tgt, 0, "Bodega vacía. Regresa a Base Central para reabastecerte"
			end

			if tgt.name == self.originPadName then
				return false, tgt, 0, string.format("Ya entregaste en %s. Vuela hacia %s", tgt.displayName, currentTgt and currentTgt.displayName or "tu objetivo")
			end

			return true, tgt, tgt.reward, nil
		end
	end

	local hint = if closestTarget
		then string.format("Helipuerto más cercano: %s a %.0f studs", closestTarget.displayName, closestDist)
		else "No hay helipuertos detectados en rango"

	return false, closestTarget, 0, hint
end

function DeliveryManager.Update(
	self: ManagerInstance,
	dt: number,
	dronePosition: Vector3,
	droneVelocity: Vector3
): (boolean, number)
	-- Fase 5: Temporizador de Entrega Prioritaria
	if self.rushOrderActive and self.rushTimeRemaining > 0 then
		self.rushTimeRemaining = math.max(0, self.rushTimeRemaining - dt)
		if self.rushTimeRemaining <= 0 then
			self.rushOrderActive = false
			print("[DeliveryManager] Temporizador de Entrega Rápida expirado. Recompensa nominal restaurada.")
		end
	end

	local inZone, target, _, _ = self:CheckPadZone(dronePosition, droneVelocity)

	if inZone and target then
		self.currentZonePadName = target.name
		self.touchdownTimer += dt
		local progress = math.clamp(self.touchdownTimer / TOUCHDOWN_TIME, 0, 1)

		if progress >= 1 and not self.isLanded then
			self.isLanded = true

			-- Si estamos aterrizando en Base Central y nos falta carga, reabastecer inmediatamente en cliente
			if target.name == "Pad_Base" and self.packagesRemaining < self.maxPackages then
				print(string.format("[DeliveryManager] Reabastecimiento automático en touchdown de Base Central (%d -> 3).", self.packagesRemaining))
				self.packagesRemaining = self.maxPackages
				self.originPadName = "Pad_Base"
				if self.onDeliveryCallback then
					self.onDeliveryCallback(100, "Base", self.deliveryStreak, self.streakMultiplier)
				end
				self:PickNextTarget("Pad_Base")
			end

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

function DeliveryManager.TryManualDeliver(self: ManagerInstance, dronePosition: Vector3, droneVelocity: Vector3): (boolean, string?)
	-- Comprobación de proximidad a Base Central holgada (hasta 42 studs) para reabastecimiento manual garantizado
	local baseDist = Vector3.new(dronePosition.X, 0, dronePosition.Z).Magnitude
	local baseVert = dronePosition.Y - 4.0
	if baseDist <= 42 and baseVert >= -8 and baseVert <= 30 then
		if self.packagesRemaining < self.maxPackages then
			print(string.format("[DeliveryManager] ¡Reabastecimiento manual [G] en Base Central! (%d -> %d paquetes)", self.packagesRemaining, self.maxPackages))
			self.packagesRemaining = self.maxPackages
			self.originPadName = "Pad_Base"
			if self.onDeliveryCallback then
				self.onDeliveryCallback(100, "Base", self.deliveryStreak, self.streakMultiplier)
			end
			self:CompleteDelivery("Pad_Base")
			self:PickNextTarget("Pad_Base")
			return true, "¡Bodega reabastecida al 100%! 3 paquetes disponibles."
		else
			return false, "Tu bodega ya está al 100% (3/3 paquetes). Vuela hacia tu objetivo."
		end
	end

	local inZone, target, _, hint = self:CheckPadZone(dronePosition, droneVelocity)
	if inZone and target then
		local isBase = (target.name == "Pad_Base")
		if isBase then
			if self.packagesRemaining < self.maxPackages then
				self.packagesRemaining = self.maxPackages
				self.originPadName = "Pad_Base"
				if self.onDeliveryCallback then
					self.onDeliveryCallback(100, "Base", self.deliveryStreak, self.streakMultiplier)
				end
				self:CompleteDelivery("Pad_Base")
				self:PickNextTarget("Pad_Base")
				return true, "¡Bodega reabastecida al 100%! 3 paquetes disponibles."
			else
				return false, "Tu bodega ya está al 100% (3/3 paquetes)."
			end
		end

		local actionMsg = string.format("¡Entregando en %s!", target.displayName)
		print(string.format("[DeliveryManager] Operación manual [G] en %s: %s", target.displayName, actionMsg))
		self:CompleteDelivery(target.name)
		return true, actionMsg
	else
		local reason = hint or "Debes estar sobre un helipuerto para operar"
		print("[DeliveryManager] [G] Rechazado:", reason)
		return false, reason
	end
end

function DeliveryManager.CompleteDelivery(self: ManagerInstance, padName: string)
	if not self.claimEvent then
		self.claimEvent = resolveRemote("DeliveryCompleted")
	end
	if self.claimEvent then
		local isRushClaim = (self.rushOrderActive and self.rushTimeRemaining > 0)
		print(string.format("[DeliveryManager] Enviando confirmación de operación en '%s' al servidor (Rush:%s)...", padName, tostring(isRushClaim)))
		self.claimEvent:FireServer(padName, isRushClaim)
	else
		warn("[DeliveryManager] No se pudo enviar evento: claimEvent es nil")
	end
end

function DeliveryManager.GetRushInfo(self: ManagerInstance): (boolean, number, number)
	return self.rushOrderActive, self.rushTimeRemaining, self.rushMultiplier
end

function DeliveryManager.NotifyCargoLost(self: ManagerInstance, remainingCount: number)
	self.packagesRemaining = math.max(0, remainingCount)
	self.isLanded = false
	self.touchdownTimer = 0
	if self.packagesRemaining <= 0 then
		print("[DeliveryManager] ¡Carga perdida por impactos! Re-enrutando obligatoriamente a Base Central.")
		self:PickNextTarget("")
	end
end

function DeliveryManager.GetPackagesRemaining(self: ManagerInstance): number
	return self.packagesRemaining
end

function DeliveryManager.GetMaxPackages(self: ManagerInstance): number
	return self.maxPackages
end

function DeliveryManager.GetDeliveryStreak(self: ManagerInstance): number
	return self.deliveryStreak
end

function DeliveryManager.GetStreakMultiplier(self: ManagerInstance): number
	return self.streakMultiplier
end

function DeliveryManager.ResetStreak(self: ManagerInstance)
	self.deliveryStreak = 0
	self.streakMultiplier = 1.0
end

function DeliveryManager.GetDeliveriesCompletedSinceRestock(self: ManagerInstance): number
	return self.deliveriesCompletedSinceRestock or 0
end

function DeliveryManager.CheckAndConsumeMissileRestock(self: ManagerInstance): boolean
	if (self.deliveriesCompletedSinceRestock or 0) >= 3 then
		self.deliveriesCompletedSinceRestock = 0
		return true
	end
	return false
end

function DeliveryManager.SetOnDeliveryCallback(
	self: ManagerInstance,
	callback: (reward: number, padName: string, streak: number, multiplier: number) -> ()
)
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
