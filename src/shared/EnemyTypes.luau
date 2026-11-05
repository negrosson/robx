--!strict
-- src/shared/EnemyTypes.luau
-- Arquetipos de Facciones Hostiles — Cyber Delivery Tycoon
-- Tres clases: enjambre, torreta estacionaria e interceptor orbital

local EnemyTypes = {}

----------------------------------------------------------------------
-- TIPOS EXPORTADOS
----------------------------------------------------------------------
export type AggressionMode = "ramming" | "turret" | "orbit"

export type EnemySpec = {
	id              : string,
	name            : string,
	faction         : string,
	aggressionMode  : AggressionMode,

	-- Integridad
	maxHealth       : number,
	armorReduction  : number,

	-- Movimiento (Steering Behaviors 3D)
	maxSpeed        : number,  -- studs/s
	maxForce        : number,  -- fuerza máxima de dirección (studs/s² equivalente)
	mass            : number,  -- kg (afecta inercia)
	detectionRadius : number,  -- studs — rango de detección del jugador
	detectionAngle  : number,  -- grados del cono de visión (360 = omnidireccional)

	-- Comportamiento específico
	orbitRadius     : number,  -- studs desde el jugador (para modo "orbit")
	rammingImpulse  : number,  -- fuerza de embestida en newtons (para "ramming")
	fireRange       : number,  -- studs máximo de disparo
	burstWeapon     : string,  -- id del arma usada (referencia a DroneWeapons)

	-- Recompensa al destruir
	creditReward    : number,
	xpReward        : number,

	-- Visual
	primaryColor    : Color3,
	accentColor     : Color3,
	scale           : Vector3,  -- escala del modelo respecto a TestDrone estándar
}

----------------------------------------------------------------------
-- PALETA
----------------------------------------------------------------------
local COL_SCRAP    = Color3.fromRGB(80, 65, 50)     -- chatarrero oxidado
local COL_RUST     = Color3.fromRGB(140, 60, 30)
local COL_CORP     = Color3.fromRGB(13, 13, 13)     -- #0D0D0D corporativo
local COL_CERAMIC  = Color3.fromRGB(255, 255, 255)  -- #FFFFFF
local COL_NEON_RED = Color3.fromRGB(255, 0, 63)     -- #FF003F
local COL_WARN     = Color3.fromRGB(255, 180, 0)    -- ámbar de alerta

----------------------------------------------------------------------
-- 1. SCAV-GNATS — Enjambre Chatarrero
-- Táctica: Ramming (embestida física directa en grupo para desestabilizar carga)
-- IA: Flocking/Seek hacia el jugador a 10 Hz
----------------------------------------------------------------------
local SCAV_GNATS: EnemySpec = {
	id              = "scav_gnats",
	name            = "Scav-Gnats MK0",
	faction         = "Enjambre Chatarrero",
	aggressionMode  = "ramming",

	maxHealth       = 25,
	armorReduction  = 0.0,

	maxSpeed        = 50,
	maxForce        = 300,
	mass            = 3,       -- ligeros, fáciles de destruir pero agiles
	detectionRadius = 90,
	detectionAngle  = 360,     -- omnidireccional (enjambre sin puntos ciegos)

	orbitRadius     = 0,       -- no orbitan, embisten
	rammingImpulse  = 55,      -- newtons aplicados al dron del jugador en colisión
	fireRange       = 0,       -- sin armas de proyectil, solo embestida
	burstWeapon     = "",

	creditReward    = 15,
	xpReward        = 10,

	primaryColor    = COL_SCRAP,
	accentColor     = COL_RUST,
	scale           = Vector3.new(0.5, 0.3, 0.5),  -- pequeños y compactos
}

----------------------------------------------------------------------
-- 2. AEGIS-44 — Torreta Estacionaria de Cornisa
-- Táctica: Turret (cono de 120°, intercepción angular anticipada)
-- IA: Detecta + rota hacia el jugador + dispara Rail-Driver en ráfaga corta
----------------------------------------------------------------------
local AEGIS_44: EnemySpec = {
	id              = "aegis_44",
	name            = "Aegis-44 Sentry",
	faction         = "Seguridad Corporativa Estacionaria",
	aggressionMode  = "turret",

	maxHealth       = 200,
	armorReduction  = 0.30,  -- blindaje de cornisa reforzado

	maxSpeed        = 0,     -- estacionaria, no se mueve
	maxForce        = 0,
	mass            = 60,
	detectionRadius = 160,
	detectionAngle  = 120,   -- cono frontal de 120°

	orbitRadius     = 0,
	rammingImpulse  = 0,
	fireRange       = 150,
	burstWeapon     = "rail_driver",

	creditReward    = 80,
	xpReward        = 50,

	primaryColor    = COL_CORP,
	accentColor     = COL_WARN,
	scale           = Vector3.new(1.2, 2.0, 1.2),  -- torreta alta y delgada
}

----------------------------------------------------------------------
-- 3. KUROSHIO V — Interceptor Corporativo Orbital
-- Táctica: Orbit (mantiene radio lateral de 100 studs, dispara microondas continuas)
-- IA: Pursue + OrbitTangent a 10 Hz, steering behavior de tangente lateral
----------------------------------------------------------------------
local KUROSHIO_V: EnemySpec = {
	id              = "kuroshio_v",
	name            = "Kuroshio V Interceptor",
	faction         = "Seguridad Aérea Corporativa",
	aggressionMode  = "orbit",

	maxHealth       = 120,
	armorReduction  = 0.12,

	maxSpeed        = 70,
	maxForce        = 450,
	mass            = 8,
	detectionRadius = 200,
	detectionAngle  = 360,     -- sensores omnidireccionales

	orbitRadius     = 100,     -- mantiene 100 studs de distancia orbital
	rammingImpulse  = 0,
	fireRange       = 130,
	burstWeapon     = "synapse_overheat",  -- microondas para sobrecalentar al jugador

	creditReward    = 120,
	xpReward        = 90,

	primaryColor    = COL_CORP,
	accentColor     = COL_NEON_RED,
	scale           = Vector3.new(1.0, 0.6, 1.0),  -- perfil bajo y aerodinámico
}

----------------------------------------------------------------------
-- ÍNDICE PÚBLICO
----------------------------------------------------------------------
EnemyTypes.All: { EnemySpec } = {
	SCAV_GNATS,
	AEGIS_44,
	KUROSHIO_V,
}

EnemyTypes.ById: { [string]: EnemySpec } = {}
for _, spec in ipairs(EnemyTypes.All) do
	EnemyTypes.ById[spec.id] = spec
end

-- Genera estadísticas escaladas según dificultad (0.0 = fácil, 1.0 = difícil)
function EnemyTypes.Scale(spec: EnemySpec, difficulty: number): EnemySpec
	local d = math.clamp(difficulty, 0, 1)
	-- Clonar para no mutar el original
	local scaled: EnemySpec = table.clone(spec) :: EnemySpec
	scaled.maxHealth    = math.round(spec.maxHealth * (1 + d * 0.8))
	scaled.maxSpeed     = spec.maxSpeed * (1 + d * 0.4)
	scaled.creditReward = math.round(spec.creditReward * (1 + d * 1.5))
	scaled.xpReward     = math.round(spec.xpReward * (1 + d * 1.5))
	return scaled
end

return EnemyTypes
