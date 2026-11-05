--!strict
-- src/shared/DeliveryManager.luau
-- Gestor de Misiones, Detección de Aterrizaje y Despacho de Entregas con Validación
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
	reward: number,
}

export type ManagerInstance = {
	targets: { DeliveryTarget },
	currentTargetIndex: number,
	touchdownTimer: number,
	isLanded: boolean,
	claimEvent: RemoteEvent,
	confirmedEvent: RemoteEvent,
	confirmedConn: RBXScriptConnection?,
	onDeliveryCallback: ((reward: number, padName: string) => ())?,
}

function DeliveryManager.new(): ManagerInstance
	local claimEvent = NetworkEvents.Get(NetworkEvents.Names.ClaimDelivery)
	local confirmedEvent = NetworkEvents.Get(NetworkEvents.Names.DeliveryConfirmed)
	local padsFolder = Workspace:WaitForChild("LandingPads", 10) :: Folder?

	local targets: { DeliveryTarget } = {}

	if padsFolder then
		for _, child in ipairs(padsFolder:GetChildren()) do
			if child:IsA("Model") then
				local basePart = child:FindFirstChild("BasePad") :: BasePart?
				if basePart then
					local displayName = child.Name:gsub("Pad_", ""):gsub("(%u)", " %1"):gsub("^%s+", "")
					table.insert(targets, {
						name = child.Name,
						displayName = displayName,
						model = child,
						position = basePart.Position + Vector3.new(0, 2, 0),
						reward = 250,
					})
				end
			end
		end
	end

	if #targets == 0 then
		table.insert(targets, {
			name = "Pad_TorreArasaka",
			displayName = "Torre Arasaka",
			model = nil,
			position = Vector3.new(160, 97, -180),
			reward = 250,
		})
	end

	local self: ManagerInstance = {
		targets = targets,
		currentTargetIndex = 1,
		touchdownTimer = 0,
		isLanded = false,
		claimEvent = claimEvent,
		confirmedEvent = confirmedEvent,
		confirmedConn = nil,
		onDeliveryCallback = nil,
	}

	if #targets > 1 then
		self.currentTargetIndex = 2
	end

	-- Escuchar confirmación validada del servidor
	self.confirmedConn = confirmedEvent.OnClientEvent:Connect(function(padName: string, reward: number)
		local currentTarget = self.targets[self.currentTargetIndex]
		local displayName = if currentTarget and currentTarget.name == padName then currentTarget.displayName else padName

		if self.onDeliveryCallback then
			self.onDeliveryCallback(reward, displayName)
		end
	end)

	return setmetatable(self, DeliveryManager) :: any
end

function DeliveryManager.RefreshTargets(self: ManagerInstance)
	local padsFolder = Workspace:FindFirstChild("LandingPads")
	if not padsFolder then return end

	local targets: { DeliveryTarget } = {}
	for _, child in ipairs(padsFolder:GetChildren()) do
		if child:IsA("Model") then
			local basePart = child:FindFirstChild("BasePad") :: BasePart?
			if basePart then
				local displayName = child.Name:gsub("Pad_", ""):gsub("(%u)", " %1"):gsub("^%s+", "")
				table.insert(targets, {
					name = child.Name,
					displayName = displayName,
					model = child,
					position = basePart.Position + Vector3.new(0, 2, 0),
					reward = 250,
				})
			end
		end
	end

	if #targets > 0 then
		self.targets = targets
	end
end

function DeliveryManager.GetCurrentTarget(self: ManagerInstance): DeliveryTarget
	if #self.targets <= 1 then
		self:RefreshTargets()
	end
	return self.targets[self.currentTargetIndex] or self.targets[1]
end

function DeliveryManager.Update(
	self: ManagerInstance,
	dt: number,
	dronePosition: Vector3,
	droneVelocity: Vector3
): (boolean, number)
	local target = self:GetCurrentTarget()
	if not target then return false, 0 end
	local padPos = target.position

	local horizDist = Vector3.new(dronePosition.X - padPos.X, 0, dronePosition.Z - padPos.Z).Magnitude
	local vertDiff = dronePosition.Y - padPos.Y
	local speed = droneVelocity.Magnitude

	local insideZone = (horizDist <= 14) and (vertDiff >= -1 and vertDiff <= 5)
	local safeSpeed = speed <= 15

	if insideZone and safeSpeed then
		self.touchdownTimer += dt
		local progress = math.clamp(self.touchdownTimer / 0.85, 0, 1)

		if progress >= 1 and not self.isLanded then
			self.isLanded = true
			self:CompleteDelivery()
			return true, 1
		end
		return false, progress
	else
		self.touchdownTimer = math.max(0, self.touchdownTimer - (dt * 2))
		self.isLanded = false
		return false, 0
	end
end

function DeliveryManager.CompleteDelivery(self: ManagerInstance)
	local completedTarget = self:GetCurrentTarget()
	if not completedTarget then return end

	-- Enviar reclamo de entrega al servidor para su validación
	if self.claimEvent then
		self.claimEvent:FireServer(completedTarget.name)
	end

	-- Rotar hacia el siguiente helipuerto objetivo tras breve pausa
	task.delay(1.2, function()
		if #self.targets > 1 then
			local nextIndex = self.currentTargetIndex
			repeat
				nextIndex = math.random(1, #self.targets)
			until nextIndex ~= self.currentTargetIndex

			self.currentTargetIndex = nextIndex
			self.touchdownTimer = 0
			self.isLanded = false
		end
	end)
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
