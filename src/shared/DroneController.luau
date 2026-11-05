--!strict
-- src/shared/DroneController.luau
-- v4.0 - Vuelo físico con inercia suave, requires LAZY dentro de new()
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")

-- ContextActionService eliminado (causaba conflictos con el character controller)

local DroneController = {}
DroneController.__index = DroneController

----------------------------------------------------------------------
-- TIPOS
----------------------------------------------------------------------
export type DroneConfig = {
	cruiseSpeed         : number,
	turboSpeed          : number,
	verticalSpeed       : number,
	-- Tasas de interpolación (Lerp alpha por segundo)
	accelRate           : number,  -- al presionar tecla
	decelRate           : number,  -- al soltar tecla
	brakeRate           : number,  -- al presionar X (airbrake)
	vertAccelRate       : number,
	vertDecelRate       : number,
	tiltAngle           : number,
	tiltSpeed           : number,
	baseFOV             : number,
	maxFOV              : number,
}

export type InputState = {
	forward  : boolean,
	backward : boolean,
	left     : boolean,
	right    : boolean,
	up       : boolean,
	down     : boolean,
	turbo    : boolean,
	brake    : boolean,
}

----------------------------------------------------------------------
-- CONFIG POR DEFECTO
-- cruiseSpeed = velocidad máxima crucero (studs/s)
-- accelRate   = qué tan rápido LLEGA a esa velocidad (Lerp factor/s)
--               1.0 = llega en ~1s, 0.3 = llega en ~3s (más suave)
----------------------------------------------------------------------
local DEFAULT_CONFIG: DroneConfig = {
	cruiseSpeed     = 60,    -- velocidad crucero
	turboSpeed      = 110,   -- velocidad turbo (Q)
	verticalSpeed   = 35,    -- velocidad subir/bajar
	accelRate       = 1.5,   -- aceleración horizontal suave (era 2.4 → muy rápido)
	decelRate       = 0.8,   -- desaceleración al soltar
	brakeRate       = 3.5,   -- frenado con X
	vertAccelRate   = 1.8,   -- aceleración vertical
	vertDecelRate   = 1.0,   -- desaceleración vertical
	tiltAngle       = math.rad(18),
	tiltSpeed       = 8,
	baseFOV         = 70,
	maxFOV          = 85,
}

----------------------------------------------------------------------
-- CONSTRUCTOR
----------------------------------------------------------------------
function DroneController.new(droneEntity: Instance, customConfig: DroneConfig?)
	print("[DroneController v4] Inicializando...")

	-- 1. Obtener BasePart del dron
	local rootPart: BasePart
	if droneEntity:IsA("BasePart") then
		rootPart = droneEntity
	elseif droneEntity:IsA("Model") then
		local pp = (droneEntity :: Model).PrimaryPart
		rootPart = pp or (droneEntity:FindFirstChildWhichIsA("BasePart") :: BasePart)
		assert(rootPart, "[DroneController] Modelo sin BasePart.")
	else
		error("[DroneController] Instancia inválida: " .. droneEntity.ClassName)
	end
	print("[DroneController] rootPart =", rootPart:GetFullName())

	-- 2. Obtener/crear constraints de vuelo (el servidor los crea, pero si no existen los creamos)
	local attachment = rootPart:FindFirstChild("FlightAttachment") :: Attachment?
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name     = "FlightAttachment"
		attachment.Position = Vector3.zero
		attachment.Parent   = rootPart
		print("[DroneController] FlightAttachment creado por cliente")
	end

	local linearVelocity = rootPart:FindFirstChild("FlightVelocity") :: LinearVelocity?
	if not linearVelocity then
		linearVelocity = Instance.new("LinearVelocity")
		linearVelocity.Name           = "FlightVelocity"
		linearVelocity.Attachment0    = attachment
		linearVelocity.RelativeTo     = Enum.ActuatorRelativeTo.World
		linearVelocity.MaxForce       = 1e6
		linearVelocity.VectorVelocity = Vector3.zero
		linearVelocity.Parent         = rootPart
		print("[DroneController] FlightVelocity creado por cliente")
	end

	local alignOrientation = rootPart:FindFirstChild("FlightOrientation") :: AlignOrientation?
	if not alignOrientation then
		alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name        = "FlightOrientation"
		alignOrientation.Attachment0 = attachment
		alignOrientation.Mode        = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.Responsiveness = 25
		alignOrientation.MaxTorque   = 1e6
		alignOrientation.CFrame      = rootPart.CFrame
		alignOrientation.Parent      = rootPart
		print("[DroneController] FlightOrientation creado por cliente")
	end

	-- 3. RemoteEvent del servidor
	local flightStateEvent: RemoteEvent? = nil
	local okNet, NetworkEvents = pcall(function()
		return require(script.Parent:WaitForChild("NetworkEvents", 5) :: ModuleScript)
	end)
	if okNet and NetworkEvents then
		flightStateEvent = (NetworkEvents :: any).Get((NetworkEvents :: any).Names.DroneFlightState)
	else
		flightStateEvent = ReplicatedStorage:FindFirstChild("DroneFlightState") :: RemoteEvent?
		if not flightStateEvent then
			flightStateEvent = ReplicatedStorage:WaitForChild("DroneFlightState", 5) :: RemoteEvent?
		end
	end
	if flightStateEvent then
		print("[DroneController] DroneFlightState RemoteEvent OK")
	else
		warn("[DroneController] DroneFlightState no encontrado - el dron puede no desanclarse")
	end

	-- 4. PlayerControls (para deshabilitar movimiento del personaje)
	local playerControls: any = nil
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		pcall(function()
			local ps = localPlayer:WaitForChild("PlayerScripts", 3)
			if ps then
				local pm = ps:FindFirstChild("PlayerModule")
				if pm and pm:IsA("ModuleScript") then
					local mod = require(pm :: ModuleScript)
					playerControls = (mod :: any):GetControls()
				end
			end
		end)
	end

	-- 5. CARGA LAZY de subsistemas (cada uno en pcall independiente)
	--    Los módulos se requieren AQUÍ, no en el top-level del archivo.

	local function lazyRequire(name: string): any
		local ok, result = pcall(function()
			local mod = ReplicatedStorage:FindFirstChild(name) :: ModuleScript?
			if not mod then
				mod = ReplicatedStorage:WaitForChild(name, 5) :: ModuleScript?
			end
			assert(mod, "Módulo no encontrado: " .. name)
			return require(mod)
		end)
		if ok then
			print("[DroneController] Módulo cargado: " .. name)
			return result
		else
			warn("[DroneController] Error cargando " .. name .. ":", result)
			return nil
		end
	end

	local DroneHUD       = lazyRequire("DroneHUD")
	local DroneAudio     = lazyRequire("DroneAudio")
	local DroneVFX       = lazyRequire("DroneVFX")
	local DroneCargo     = lazyRequire("DroneCargo")
	local DeliveryMgr    = lazyRequire("DeliveryManager")
	local CyberGoggles   = lazyRequire("CyberGoggles")

	-- Instanciar subsistemas
	local hud: any = nil
	if DroneHUD then pcall(function() hud = DroneHUD.new() end) end

	local audio: any = nil
	if DroneAudio then pcall(function() audio = DroneAudio.new(rootPart) end) end

	local vfx: any = nil
	if DroneVFX then pcall(function() vfx = DroneVFX.new(rootPart) end) end

	local cargo: any = nil
	if DroneCargo then pcall(function() cargo = DroneCargo.new(rootPart) end) end

	local deliveryManager: any = nil
	if DeliveryMgr then pcall(function() deliveryManager = DeliveryMgr.new() end) end

	-- 6. Construir instancia
	local self = setmetatable({
		rootPart          = rootPart,
		attachment        = attachment,
		linearVelocity    = linearVelocity,
		alignOrientation  = alignOrientation,
		config            = customConfig or DEFAULT_CONFIG,

		-- estado de inputs
		inputState = {
			forward  = false,
			backward = false,
			left     = false,
			right    = false,
			up       = false,
			down     = false,
			turbo    = false,
			brake    = false,
		} :: InputState,

		-- física
		currentVelocity  = Vector3.zero,
		currentPitch     = 0,
		currentRoll      = 0,
		turboEnergy      = 100,

		-- estado
		isFPV      = false,
		isFlying   = false,

		-- conexiones
		connection       = nil :: RBXScriptConnection?,
		inputBeganConn   = nil :: RBXScriptConnection?,
		inputEndedConn   = nil :: RBXScriptConnection?,

		-- camera
		originalWalkSpeed  = 16,
		originalJumpHeight = 7.2,

		-- subsistemas
		hud             = hud,
		audio           = audio,
		vfx             = vfx,
		cargo           = cargo,
		deliveryManager = deliveryManager,
		cyberGoggles    = CyberGoggles,
		playerControls  = playerControls,
		flightStateEvent = flightStateEvent,
	}, DroneController)

	-- Callback de entrega
	if deliveryManager and deliveryManager.SetOnDeliveryCallback then
		deliveryManager:SetOnDeliveryCallback(function(reward: number, padName: string)
			if self.hud then pcall(function() self.hud:ShowSuccessPopup(reward, padName) end) end
			if self.cargo then pcall(function() self.cargo:DeliverAndReload(self.rootPart.Position) end) end
		end)
	end

	print("[DroneController v4] Listo!")
	return self
end

----------------------------------------------------------------------
-- INICIAR VUELO
----------------------------------------------------------------------
function DroneController:StartFlying()
	if self.isFlying then
		print("[DroneController] Ya estaba volando.")
		return
	end
	print("[DroneController] StartFlying() llamado")
	self.isFlying = true

	-- Notificar servidor para desanclar y transferir network ownership
	if self.flightStateEvent then
		print("[DroneController] Disparando StartFlying al servidor...")
		self.flightStateEvent:FireServer("StartFlying")
	else
		warn("[DroneController] Sin RemoteEvent - intentando desanclar localmente (puede fallar con FilteringEnabled)")
		pcall(function() self.rootPart.Anchored = false end)
	end

	-- Pequeña espera para que el servidor procese el desanclado
	task.delay(0.15, function()
		if self.isFlying and self.rootPart.Anchored then
			warn("[DroneController] Dron aún anclado tras 0.15s - servidor no respondió?")
		end
	end)

	-- Bloquear personaje (WalkSpeed=0, JumpPower=0)
	self:LockPlayerCharacter()

	-- Deshabilitar sistema de movimiento de Roblox
	if self.playerControls and self.playerControls.Disable then
		pcall(function() self.playerControls:Disable() end)
	end

	-- Activar gafas
	local localPlayer = Players.LocalPlayer
	local char = localPlayer and localPlayer.Character
	if char and self.cyberGoggles then
		pcall(function() self.cyberGoggles.SetOnline(char, true) end)
	end

	-- Enfocar cámara en dron
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType    = Enum.CameraType.Custom
		camera.CameraSubject = self.rootPart
	end

	-- Vincular inputs de vuelo
	self:BindInputs()

	-- Iniciar loop de física
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	self.connection = RunService.RenderStepped:Connect(function(dt: number)
		dt = math.clamp(dt, 0, 0.1)

		-- Actualizar lista de exclusión para raycast
		local filterList: { Instance } = { self.rootPart }
		local lp = Players.LocalPlayer
		if lp and lp.Character then
			table.insert(filterList, lp.Character)
		end
		raycastParams.FilterDescendantsInstances = filterList

		-- Turbo energy
		local isBoosting = self.inputState.turbo and (self.turboEnergy > 5)
		if isBoosting then
			self.turboEnergy = math.max(0, self.turboEnergy - dt * 25)
		else
			self.turboEnergy = math.min(100, self.turboEnergy + dt * 12)
		end

		local maxSpeed = if isBoosting then self.config.turboSpeed else self.config.cruiseSpeed

		-- Vectores de cámara aplanados al plano horizontal
		local cam = Workspace.CurrentCamera
		local camCF = if cam then cam.CFrame else self.rootPart.CFrame

		local rawLook  = camCF.LookVector
		local flatLook = Vector3.new(rawLook.X, 0, rawLook.Z)
		local fwd: Vector3
		if flatLook.Magnitude > 0.001 then
			fwd = flatLook.Unit
		else
			fwd = Vector3.new(0, 0, -1)
		end

		local rawRight  = camCF.RightVector
		local flatRight = Vector3.new(rawRight.X, 0, rawRight.Z)
		local rgt: Vector3
		if flatRight.Magnitude > 0.001 then
			rgt = flatRight.Unit
		else
			rgt = Vector3.new(1, 0, 0)
		end

		-- Input direccional
		local moveZ = (if self.inputState.forward then 1 else 0) - (if self.inputState.backward then 1 else 0)
		local moveX = (if self.inputState.right then 1 else 0) - (if self.inputState.left then 1 else 0)
		local moveY = (if self.inputState.up then 1 else 0) - (if self.inputState.down then 1 else 0)
		-- Nota: forward = W = fwd (delante de la cámara)

		local isBraking    = self.inputState.brake
		local isThrottling = (math.abs(moveZ) + math.abs(moveX)) > 0.01

		-- Calcular horizontal objetivo
		local moveDir = (fwd * moveZ) + (rgt * moveX)
		if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end
		local targetH = moveDir * maxSpeed

		-- Seleccionar tasa de interpolación horizontal
		local hRate: number
		if isBraking then
			hRate   = self.config.brakeRate
			targetH = Vector3.zero
		elseif isThrottling then
			hRate = self.config.accelRate
		else
			hRate = self.config.decelRate
		end

		-- Lerp horizontal
		local curH = Vector3.new(self.currentVelocity.X, 0, self.currentVelocity.Z)
		local newH = curH:Lerp(targetH, math.clamp(dt * hRate, 0, 1))

		-- Calcular vertical objetivo
		local targetY = moveY * self.config.verticalSpeed
		local vRate: number
		if isBraking then
			vRate   = self.config.brakeRate
			targetY = 0
		elseif math.abs(moveY) > 0.01 then
			vRate = self.config.vertAccelRate
		else
			vRate = self.config.vertDecelRate
		end

		local newY = self.currentVelocity.Y + (targetY - self.currentVelocity.Y) * math.clamp(dt * vRate, 0, 1)

		-- Aplicar velocidad
		self.currentVelocity = Vector3.new(newH.X, newY, newH.Z)
		self.linearVelocity.VectorVelocity = self.currentVelocity

		-- Inclinación del dron (tilt)
		local speedRatio  = math.clamp(self.currentVelocity.Magnitude / self.config.cruiseSpeed, 0, 1)
		local targetPitch = -moveZ * self.config.tiltAngle * math.max(0.3, speedRatio)
		local targetRoll  = moveX * self.config.tiltAngle

		local tFactor = math.clamp(dt * self.config.tiltSpeed, 0, 1)
		self.currentPitch = self.currentPitch + (targetPitch - self.currentPitch) * tFactor
		self.currentRoll  = self.currentRoll  + (targetRoll  - self.currentRoll)  * tFactor

		local baseRot = CFrame.lookAt(Vector3.zero, fwd, Vector3.yAxis)
		self.alignOrientation.CFrame = baseRot * CFrame.Angles(self.currentPitch, 0, self.currentRoll)

		-- Cámara FPV / Chase
		if cam then
			if self.isFPV then
				cam.CameraType = Enum.CameraType.Scriptable
				local eyePos = self.rootPart.CFrame:PointToWorldSpace(Vector3.new(0, 0.3, -self.rootPart.Size.Z * 0.5))
				cam.CFrame = CFrame.lookAt(eyePos, eyePos + self.rootPart.CFrame.LookVector, self.rootPart.CFrame.UpVector)
			else
				if cam.CameraType ~= Enum.CameraType.Custom then
					cam.CameraType = Enum.CameraType.Custom
				end
				if cam.CameraSubject ~= self.rootPart then
					cam.CameraSubject = self.rootPart
				end
				local targetFOV = self.config.baseFOV + (self.config.maxFOV - self.config.baseFOV) * speedRatio
				cam.FieldOfView = cam.FieldOfView + (targetFOV - cam.FieldOfView) * math.clamp(dt * 5, 0, 1)
			end
		end

		-- Altímetro por raycast
		local rayResult = Workspace:Raycast(self.rootPart.Position, Vector3.new(0, -600, 0), raycastParams)
		local altitude  = if rayResult then (self.rootPart.Position.Y - rayResult.Position.Y) else 600

		-- Delivery manager
		local landingProgress = 0
		local currentTarget: any = nil
		if self.deliveryManager then
			pcall(function()
				local _, prog = self.deliveryManager:Update(dt, self.rootPart.Position, self.currentVelocity)
				landingProgress = prog or 0
				currentTarget   = self.deliveryManager:GetCurrentTarget()
			end)
		end

		-- HUD
		if self.hud then
			pcall(function()
				self.hud:Update(
					self.currentVelocity.Magnitude,
					self.config.cruiseSpeed,
					self.turboEnergy / 100,
					altitude,
					self.currentRoll,
					self.isFPV,
					isBraking,
					currentTarget and currentTarget.position or nil,
					currentTarget and currentTarget.displayName or nil,
					currentTarget and currentTarget.reward or 250,
					landingProgress
				)
			end)
		end

		-- Audio y VFX
		if self.audio then pcall(function() self.audio:Update(speedRatio, moveY, dt) end) end
		if self.vfx   then pcall(function() self.vfx:Update(speedRatio, moveY)      end) end
	end)

	print("[DroneController] ¡Loop de vuelo iniciado!")
end

----------------------------------------------------------------------
-- DETENER VUELO
----------------------------------------------------------------------
function DroneController:StopFlying()
	if not self.isFlying then return end
	self.isFlying = false
	print("[DroneController] StopFlying() llamado")

	-- Parar loop
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end

	-- Parar velocidad
	self.currentVelocity = Vector3.zero
	self.linearVelocity.VectorVelocity = Vector3.zero

	-- Notificar servidor
	if self.flightStateEvent then
		self.flightStateEvent:FireServer("StopFlying")
	else
		pcall(function()
			self.rootPart.AssemblyLinearVelocity = Vector3.zero
			self.rootPart.Anchored = true
		end)
	end

	-- Desactivar gafas
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	if char and self.cyberGoggles then
		pcall(function() self.cyberGoggles.SetOnline(char, false) end)
	end

	-- Desconectar inputs
	self:UnbindInputs()

	-- Restaurar personaje
	self:UnlockPlayerCharacter()
	if self.playerControls and self.playerControls.Enable then
		pcall(function() self.playerControls:Enable() end)
	end

	-- Restaurar cámara al personaje
	local camera = Workspace.CurrentCamera
	if camera and char then
		camera.CameraType = Enum.CameraType.Custom
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then camera.CameraSubject = hum end
		camera.FieldOfView = self.config.baseFOV
	end
end

----------------------------------------------------------------------
-- BLOQUEAR / DESBLOQUEAR PERSONAJE
----------------------------------------------------------------------
function DroneController:LockPlayerCharacter()
	local lp   = Players.LocalPlayer
	local char = lp and lp.Character
	if not char then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		self.originalWalkSpeed  = hum.WalkSpeed
		self.originalJumpHeight = hum.JumpHeight
		hum.WalkSpeed  = 0
		hum.JumpHeight = 0
		hum.JumpPower  = 0
	end
	-- NO anclamos HumanoidRootPart: causa problemas con la física del servidor
end

function DroneController:UnlockPlayerCharacter()
	local lp   = Players.LocalPlayer
	local char = lp and lp.Character
	if not char then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed  = self.originalWalkSpeed  or 16
		hum.JumpHeight = self.originalJumpHeight or 7.2
		hum.JumpPower  = 50
	end
end

----------------------------------------------------------------------
-- VINCULAR / DESVINCULAR INPUTS DE VUELO
----------------------------------------------------------------------
function DroneController:BindInputs()
	self:UnbindInputs()
	print("[DroneController] BindInputs() - WASD/Space/Shift/Q/X/V activos")

	self.inputBeganConn = UserInputService.InputBegan:Connect(function(input: InputObject, gpe: boolean)
		-- gpe = true cuando el chat u otro sistema captura la tecla
		-- Para WASD durante el vuelo, Roblox puede marcarlos como gpe=true
		-- (el character controller los procesa). Los ignoramos IGUAL porque
		-- LockPlayerCharacter() pone WalkSpeed=0.
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local k = input.KeyCode

		if     k == Enum.KeyCode.W          then self.inputState.forward   = true
		elseif k == Enum.KeyCode.S          then self.inputState.backward  = true
		elseif k == Enum.KeyCode.A          then self.inputState.left      = true
		elseif k == Enum.KeyCode.D          then self.inputState.right     = true
		elseif k == Enum.KeyCode.Space      then self.inputState.up        = true
		elseif k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.LeftControl or k == Enum.KeyCode.C then self.inputState.down = true
		elseif k == Enum.KeyCode.Q          then self.inputState.turbo     = true
		elseif k == Enum.KeyCode.X          then self.inputState.brake     = true
		elseif k == Enum.KeyCode.V          then self.isFPV = not self.isFPV
		end
	end)

	self.inputEndedConn = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local k = input.KeyCode

		if     k == Enum.KeyCode.W          then self.inputState.forward   = false
		elseif k == Enum.KeyCode.S          then self.inputState.backward  = false
		elseif k == Enum.KeyCode.A          then self.inputState.left      = false
		elseif k == Enum.KeyCode.D          then self.inputState.right     = false
		elseif k == Enum.KeyCode.Space      then self.inputState.up        = false
		elseif k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.LeftControl or k == Enum.KeyCode.C then self.inputState.down = false
		elseif k == Enum.KeyCode.Q          then self.inputState.turbo     = false
		elseif k == Enum.KeyCode.X          then self.inputState.brake     = false
		end
	end)
end

function DroneController:UnbindInputs()
	if self.inputBeganConn then self.inputBeganConn:Disconnect(); self.inputBeganConn = nil end
	if self.inputEndedConn then self.inputEndedConn:Disconnect(); self.inputEndedConn = nil end

	-- Resetear todos los estados de input
	self.inputState.forward  = false
	self.inputState.backward = false
	self.inputState.left     = false
	self.inputState.right    = false
	self.inputState.up       = false
	self.inputState.down     = false
	self.inputState.turbo    = false
	self.inputState.brake    = false
end

----------------------------------------------------------------------
-- DESTRUCTOR Y LIMPIEZA UNIFICADA DE RECURSOS
----------------------------------------------------------------------
function DroneController:Destroy()
	self:StopFlying()
	if self.hud and self.hud.Destroy then
		pcall(function() self.hud:Destroy() end)
		self.hud = nil
	end
	if self.audio and self.audio.Destroy then
		pcall(function() self.audio:Destroy() end)
		self.audio = nil
	end
	if self.vfx and self.vfx.Destroy then
		pcall(function() self.vfx:Destroy() end)
		self.vfx = nil
	end
	if self.cargo and self.cargo.Destroy then
		pcall(function() self.cargo:Destroy() end)
		self.cargo = nil
	end
	if self.deliveryManager and self.deliveryManager.Destroy then
		pcall(function() self.deliveryManager:Destroy() end)
		self.deliveryManager = nil
	end
	print("[DroneController] Instancia destruida y recursos liberados.")
end

return DroneController
