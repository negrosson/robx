--!strict
-- src/shared/NetworkEvents.luau
-- Gestor Centralizado de Eventos de Red (RemoteEvents) para Cyber Delivery Tycoon
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local NetworkEvents = {}

-- Nombres tipados de eventos de red
NetworkEvents.Names = {
	DroneFlightState   = "DroneFlightState",
	ClaimDelivery      = "DeliveryCompleted",  -- Petición de entrega del cliente
	DeliveryConfirmed  = "DeliveryConfirmed",  -- Confirmación validada por servidor
	DeliveryRejected   = "DeliveryRejected",   -- Notificación de rechazo con motivo
	DroneDestroyed     = "DroneDestroyed",
	OnFireWeapon       = "OnFireWeapon",
	OnDamageTaken      = "OnDamageTaken",
	OnEMPActivated     = "OnEMPActivated",
	OnHeatUpdate       = "OnHeatUpdate",
	OnBountyAwarded    = "OnBountyAwarded",
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
		-- Evento en carpeta dedicada
		local ev = folder:FindFirstChild(eventName) :: RemoteEvent?
		if not ev then
			ev = Instance.new("RemoteEvent")
			ev.Name = eventName
			ev.Parent = folder
		end

		-- Evento espejo en la raíz de ReplicatedStorage para compatibilidad con código existente
		local rootEv = ReplicatedStorage:FindFirstChild(eventName) :: RemoteEvent?
		if not rootEv then
			local alias = Instance.new("RemoteEvent")
			alias.Name = eventName
			alias.Parent = ReplicatedStorage
		end
	end

	return folder
end

-- Obtiene un RemoteEvent de forma segura (funciona en Cliente y Servidor)
function NetworkEvents.Get(eventName: string): RemoteEvent
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
		if not folder then
			folder = NetworkEvents.Init()
		end
		local ev = folder:FindFirstChild(eventName) :: RemoteEvent?
		if not ev then
			ev = Instance.new("RemoteEvent")
			ev.Name = eventName
			ev.Parent = folder
		end
		return ev
	else
		-- 1. Buscar en CyberNetworkEvents (inmediato si ya está disponible)
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
		if not folder then
			folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 5) :: Folder?
		end

		if folder then
			local ev = folder:FindFirstChild(eventName) :: RemoteEvent?
			if not ev then
				ev = folder:WaitForChild(eventName, 4) :: RemoteEvent?
			end
			if ev then return ev end
		end

		-- 2. Fallback a la raíz de ReplicatedStorage
		local rootEv = ReplicatedStorage:FindFirstChild(eventName) :: RemoteEvent?
		if not rootEv then
			rootEv = ReplicatedStorage:WaitForChild(eventName, 4) :: RemoteEvent?
		end
		if rootEv then return rootEv end

		error(string.format("[NetworkEvents] No se pudo encontrar el RemoteEvent '%s'", eventName))
	end
end

return NetworkEvents

