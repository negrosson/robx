--!strict
-- src/shared/NetworkEvents.luau
-- Gestor Centralizado de Eventos de Red (RemoteEvents) para Cyber Delivery Tycoon
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local NetworkEvents = {}

-- Nombres tipados de eventos de red
NetworkEvents.Names = {
	DroneFlightState      = "DroneFlightState",
	ClaimDelivery         = "DeliveryCompleted",  -- Petición de entrega del cliente
	DeliveryConfirmed     = "DeliveryConfirmed",  -- Confirmación validada por servidor
	DeliveryRejected      = "DeliveryRejected",   -- Notificación de rechazo con motivo
	DroneDestroyed        = "DroneDestroyed",
	OnFireWeapon          = "OnFireWeapon",
	OnDamageTaken         = "OnDamageTaken",
	OnEMPActivated        = "OnEMPActivated",
	OnHeatUpdate          = "OnHeatUpdate",
	OnBountyAwarded       = "OnBountyAwarded",
	OnTargetHit           = "OnTargetHit",
	BuyMissiles           = "BuyMissiles",
	BuyMissilesConfirmed  = "BuyMissilesConfirmed",
}

local FOLDER_NAME = "CyberNetworkEvents"

-- Inicializa todos los eventos en el servidor (llamado al arrancar Main.server.luau)
function NetworkEvents.Init(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	for _, eventName in pairs(NetworkEvents.Names) do
		-- Buscar si ya existe en ReplicatedStorage o en folder para no duplicar instancias
		local ev = folder:FindFirstChild(eventName) :: RemoteEvent?
		if not ev then
			ev = ReplicatedStorage:FindFirstChild(eventName) :: RemoteEvent?
			if ev then
				-- Consolidar dentro de folder para evitar split-brain
				ev.Parent = folder
			end
		end

		if not ev then
			ev = Instance.new("RemoteEvent")
			ev.Name = eventName
			ev.Parent = folder
		end
	end

	return folder
end

-- Obtiene un RemoteEvent de forma segura garantizando la misma instancia canónica
function NetworkEvents.Get(eventName: string): RemoteEvent
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
	if not folder and RunService:IsServer() then
		folder = NetworkEvents.Init()
	elseif not folder then
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 4) :: Folder?
	end

	local ev: RemoteEvent? = nil
	if folder then
		ev = folder:FindFirstChild(eventName) :: RemoteEvent?
		if not ev then
			ev = folder:WaitForChild(eventName, 2) :: RemoteEvent?
		end
	end

	if not ev then
		ev = ReplicatedStorage:FindFirstChild(eventName) :: RemoteEvent?
	end

	if not ev and RunService:IsServer() then
		ev = Instance.new("RemoteEvent")
		ev.Name = eventName
		ev.Parent = folder or ReplicatedStorage
	end

	return ev :: RemoteEvent
end

return NetworkEvents

