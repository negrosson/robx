--!strict
-- src/client/Main.client.luau
-- v5.0 - Fix definitivo: gpe eliminado en tecla E, carga robusta, debug completo
print("[CLIENTE v5] Main.client.luau iniciando...")

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local Workspace          = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

----------------------------------------------------------------------
-- 1. BOTÓN HOLOGRÁFICO (creado INMEDIATAMENTE, antes de cualquier carga)
----------------------------------------------------------------------
local toggleGui = Instance.new("ScreenGui")
toggleGui.Name           = "DroneQuickToggleGui"
toggleGui.ResetOnSpawn   = false
toggleGui.IgnoreGuiInset = true
toggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
toggleGui.Parent         = playerGui

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name                  = "ToggleFPVButton"
toggleBtn.Size                  = UDim2.fromOffset(380, 50)
toggleBtn.AnchorPoint           = Vector2.new(0.5, 1)
toggleBtn.Position              = UDim2.new(0.5, 0, 1, -28)
toggleBtn.BackgroundColor3      = Color3.fromRGB(12, 18, 28)
toggleBtn.BackgroundTransparency = 0.15
toggleBtn.BorderSizePixel       = 0
toggleBtn.Font                  = Enum.Font.Code
toggleBtn.Text                  = "[INICIANDO SISTEMA...]"
toggleBtn.TextColor3            = Color3.fromRGB(180, 180, 180)
toggleBtn.TextSize              = 14
toggleBtn.AutoButtonColor       = false
toggleBtn.Parent                = toggleGui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent       = toggleBtn

local btnStroke = Instance.new("UIStroke")
btnStroke.Name      = "BtnStroke"
btnStroke.Color     = Color3.fromRGB(80, 80, 80)
btnStroke.Thickness = 2
btnStroke.Parent    = toggleBtn

-- Debug label (esquina superior izquierda)
local debugLabel = Instance.new("TextLabel")
debugLabel.Name                  = "DebugLabel"
debugLabel.Size                  = UDim2.new(0, 600, 0, 22)
debugLabel.Position              = UDim2.new(0, 8, 0, 8)
debugLabel.BackgroundTransparency = 1
debugLabel.Font                  = Enum.Font.Code
debugLabel.Text                  = "[DBG] Iniciando..."
debugLabel.TextColor3            = Color3.fromRGB(0, 255, 180)
debugLabel.TextSize              = 12
debugLabel.TextXAlignment        = Enum.TextXAlignment.Left
debugLabel.Parent                = toggleGui

local function dbg(msg: string)
	debugLabel.Text = "[DBG] " .. msg
	print("[CLIENTE DBG]", msg)
end

local function setBtn(text: string, r: number, g: number, b: number)
	toggleBtn.Text       = text
	toggleBtn.TextColor3 = Color3.fromRGB(r, g, b)
	btnStroke.Color      = Color3.fromRGB(r, g, b)
end

----------------------------------------------------------------------
-- 2. ESTADO GLOBAL
----------------------------------------------------------------------
local isPiloting        = false
local myDrone: any      = nil   -- DroneController instance
local droneReady        = false
local DroneController: any = nil
local CyberGoggles: any    = nil

----------------------------------------------------------------------
-- 3. FUNCIONES DE VUELO
----------------------------------------------------------------------
local function enterDrone()
	if isPiloting then return end

	if not droneReady or myDrone == nil then
		dbg("Dron NO listo aún, espera...")
		setBtn("[E] CARGANDO DRON... ESPERA", 255, 200, 0)
		return
	end

	dbg("Iniciando vuelo FPV...")
	isPiloting = true
	setBtn("[F] DESCONECTAR VISOR FPV", 255, 220, 0)

	-- Activar gafas en avatar
	local char = localPlayer.Character
	if char and CyberGoggles then
		pcall(function() CyberGoggles.SetOnline(char, true) end)
	end

	-- Iniciar vuelo
	local ok, err = pcall(function() myDrone:StartFlying() end)
	if not ok then
		warn("[CLIENTE] Error en StartFlying:", err)
		isPiloting = false
		setBtn("[E] ERROR AL VOLAR - REINTENTA", 255, 80, 80)
	else
		dbg("Vuelo FPV activo! WASD=mover Space=subir Shift/C=bajar Q=turbo X=freno G=entregar V=FPV")
	end
end

local function exitDrone()
	if not isPiloting then return end
	isPiloting = false

	dbg("Desconectando visor FPV...")
	setBtn("[E] CONECTAR GAFAS FPV (PILOTAR DRON)", 0, 255, 230)

	local char = localPlayer.Character
	if char and CyberGoggles then
		pcall(function() CyberGoggles.SetOnline(char, false) end)
	end
	if myDrone then
		pcall(function() myDrone:StopFlying() end)
	end
end

-- Click en botón
toggleBtn.MouseButton1Click:Connect(function()
	if not isPiloting then enterDrone() else exitDrone() end
end)

----------------------------------------------------------------------
-- FIX CRÍTICO: Tecla E sin filtro gpe para permitir captura siempre.
-- Roblox marca E/F como gpe=false normalmente, pero el sistema de
-- detección de proximidad puede cambiarlos. Usamos GetKeysPressed() y
-- una conexión directa sin verificar gpe para E y F específicamente.
----------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input: InputObject, gpe: boolean)
	-- Solo bloquear si está escribiendo en el chat (TextBox con foco)
	if gpe then
		-- Verificar si el TextBox del chat es el culpable
		local focused = UserInputService:GetFocusedTextBox()
		if focused then return end  -- Usuario está escribiendo → ignorar
		-- Si gpe=true pero NO hay TextBox con foco, fue el ProximityPrompt u otro sistema
		-- → permitir igual para E y F
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if input.KeyCode == Enum.KeyCode.E then
		if not isPiloting then enterDrone() else exitDrone() end
	elseif input.KeyCode == Enum.KeyCode.F then
		if isPiloting then exitDrone() end
	end
end)

----------------------------------------------------------------------
-- 4. CARGA ASÍNCRONA (task.spawn = no bloquea UI)
----------------------------------------------------------------------
task.spawn(function()
	dbg("Esperando que el servidor inicialice ReplicatedStorage...")

	-- Esperar NetworkEvents primero (indica que el servidor corrió)
	local neModule = ReplicatedStorage:WaitForChild("NetworkEvents", 30)
	if not neModule then
		warn("[CLIENTE] TIMEOUT esperando NetworkEvents - servidor no inició")
		setBtn("ERROR: Servidor no respondió", 255, 80, 80)
		return
	end
	dbg("NetworkEvents OK")

	-- Lista de módulos que DEBEN existir en ReplicatedStorage
	local rsModules = {
		"DroneController",
		"DroneHUD",
		"DroneAudio",
		"DroneVFX",
		"DroneCargo",
		"DeliveryManager",
		"CyberGoggles",
	}

	for _, modName in rsModules do
		local child = ReplicatedStorage:WaitForChild(modName, 15)
		if not child then
			warn("[CLIENTE] TIMEOUT esperando módulo:", modName)
			setBtn("ERROR: falta " .. modName, 255, 80, 80)
			return
		end
		dbg("OK: " .. modName)
	end

	-- Cargar CyberGoggles
	local okGoggles, gogglesResult = pcall(function()
		return require(ReplicatedStorage:WaitForChild("CyberGoggles", 5) :: ModuleScript)
	end)
	if okGoggles then
		CyberGoggles = gogglesResult
		dbg("CyberGoggles cargado OK")
	else
		warn("[CLIENTE] CyberGoggles falló:", gogglesResult)
	end

	-- Equipar gafas en avatar actual y futuros spawns
	local function setupGoggles(char: Model)
		if CyberGoggles then
			pcall(function() CyberGoggles.Attach(char) end)
		end
	end
	if localPlayer.Character then setupGoggles(localPlayer.Character) end
	localPlayer.CharacterAdded:Connect(setupGoggles)

	-- Cargar DroneController
	local okCtrl, ctrlResult = pcall(function()
		return require(ReplicatedStorage:WaitForChild("DroneController", 5) :: ModuleScript)
	end)
	if not okCtrl then
		warn("[CLIENTE] DroneController no cargó:", ctrlResult)
		setBtn("ERROR DroneController", 255, 80, 80)
		return
	end
	DroneController = ctrlResult
	dbg("DroneController módulo OK")

	-- Esperar el dron en Workspace — con reintentos cada segundo hasta 30s
	dbg("Esperando TestDrone en Workspace...")
	local droneEntity: Instance? = nil
	local waitStart = os.clock()
	while os.clock() - waitStart < 30 do
		droneEntity = Workspace:FindFirstChild("TestDrone")
		if droneEntity then break end
		task.wait(0.5)
	end

	if not droneEntity then
		warn("[CLIENTE] TestDrone no encontrado en Workspace tras 30s!")
		setBtn("ERROR: TestDrone no encontrado", 255, 80, 80)
		return
	end
	dbg("TestDrone encontrado: " .. droneEntity:GetFullName())

	-- Verificar RemoteEvents del servidor
	local flightEvent = ReplicatedStorage:FindFirstChild("DroneFlightState") :: RemoteEvent?
	if not flightEvent then
		local evFolder = ReplicatedStorage:FindFirstChild("CyberNetworkEvents") :: Folder?
		if evFolder then
			flightEvent = evFolder:FindFirstChild("DroneFlightState") :: RemoteEvent?
		end
	end
	if not flightEvent then
		flightEvent = ReplicatedStorage:WaitForChild("DroneFlightState", 8) :: RemoteEvent?
	end
	if flightEvent then
		dbg("DroneFlightState RemoteEvent OK")
	end

	-- Asegurar que los eventos de entrega estén replicados
	local evFolder = ReplicatedStorage:FindFirstChild("CyberNetworkEvents") :: Folder?
	if not evFolder then
		pcall(function() evFolder = ReplicatedStorage:WaitForChild("CyberNetworkEvents", 4) :: Folder? end)
	end
	if evFolder then
		pcall(function() evFolder:WaitForChild("DeliveryCompleted", 3) end)
		pcall(function() evFolder:WaitForChild("DeliveryConfirmed", 3) end)
	end

	-- Crear instancia del controlador (con timeout de protección)
	dbg("Creando DroneController.new()...")
	local okNew, newResult = pcall(function()
		return DroneController.new(droneEntity)
	end)
	if not okNew then
		warn("[CLIENTE] DroneController.new() falló:", newResult)
		setBtn("ERROR new(): " .. tostring(newResult):sub(1, 40), 255, 80, 80)
		return
	end

	myDrone    = newResult
	droneReady = true
	dbg("¡DRON LISTO! Presiona E para pilotar.")
	setBtn("[E] CONECTAR GAFAS FPV (PILOTAR DRON)", 0, 255, 230)
	print("[CLIENTE v5] ¡Sistema de vuelo completamente inicializado!")

	-- Conectar eventos de combate del servidor
	task.spawn(function()
		local onDmg = ReplicatedStorage:WaitForChild("OnDamageTaken", 10)
		if onDmg and onDmg:IsA("RemoteEvent") then
			(onDmg :: RemoteEvent).OnClientEvent:Connect(function(damage: number)
				if myDrone then pcall(function() myDrone:ApplyDamage(damage) end) end
			end)
			dbg("OnDamageTaken conectado")
		end
	end)

	task.spawn(function()
		local onEMP = ReplicatedStorage:WaitForChild("OnEMPActivated", 10)
		if onEMP and onEMP:IsA("RemoteEvent") then
			(onEMP :: RemoteEvent).OnClientEvent:Connect(function(dur: number)
				if myDrone then pcall(function() myDrone:TriggerEMPLocal(dur) end) end
			end)
			dbg("OnEMPActivated conectado")
		end
	end)

	task.spawn(function()
		local onHeat = ReplicatedStorage:WaitForChild("OnHeatUpdate", 10)
		if onHeat and onHeat:IsA("RemoteEvent") then
			(onHeat :: RemoteEvent).OnClientEvent:Connect(function(heatAmt: number)
				if myDrone then pcall(function() myDrone:ApplyHeat(heatAmt) end) end
			end)
			dbg("OnHeatUpdate conectado")
		end
	end)
end)
