--!strict
-- src/shared/DroneCatalog.luau
-- Catálogo de Fichas Técnicas de Drones — Tributo a Pioneros de la Aeronáutica y Cibernética
-- Paleta: Base carbón #0D0D0D | Cerámico #FFFFFF | Neón Rojo #FF003F

local DroneCatalog = {}

----------------------------------------------------------------------
-- TIPOS EXPORTADOS
----------------------------------------------------------------------
export type WeaponSlot = {
	slotId     : string,
	maxCaliber : string,  -- "light" | "medium" | "heavy" | "cyber"
}

export type DroneSpec = {
	id               : string,
	name             : string,
	historicalTribute : string,
	tier             : number,

	-- Integridad
	maxHealth        : number,
	armorReduction   : number,  -- 0.0–1.0: fracción de daño absorbida pasivamente

	-- Vuelo
	maxSpeed         : number,  -- studs/s velocidad crucero
	turboSpeed       : number,  -- studs/s con nitro activo
	verticalSpeed    : number,  -- studs/s subida/bajada
	accelRate        : number,  -- factor de Lerp horizontal
	decelRate        : number,
	brakeRate        : number,
	tiltAngle        : number,  -- rad
	tiltSpeed        : number,
	responsiveness   : number,  -- AlignOrientation.Responsiveness

	-- Gestión Térmica
	maxHeat          : number,  -- puntos de calor máximos
	heatCoolingRate  : number,  -- puntos/s que se disipan naturalmente
	empResistance    : number,  -- 0.0–1.0: reduce el calor entrante de microondas

	-- Carga
	cargoCapacity    : number,  -- studs³ / unidades de volumen aceptadas
	inertiaAlpha     : number,  -- α en VelocidadEfectiva = Base/(1+masaCarga*α)
	maxCargoMass     : number,  -- kg antes de penalización severa

	-- Armamento
	hardpoints       : { WeaponSlot },

	-- Estética / color base del chasis
	primaryColor     : Color3,
	accentColor      : Color3,
}

----------------------------------------------------------------------
-- PALETA GLOBAL (CURSORRULES)
----------------------------------------------------------------------
local COL_CARBON   = Color3.fromRGB(13,  13,  13)   -- #0D0D0D
local COL_CERAMIC  = Color3.fromRGB(255, 255, 255)  -- #FFFFFF
local COL_NEON_RED = Color3.fromRGB(255, 0,   63)   -- #FF003F
local COL_NEON_CYN = Color3.fromRGB(0,   240, 255)  -- variante de señal activa

----------------------------------------------------------------------
-- FICHAS TÉCNICAS — 5 DRONES (TRIBUTO CODIFICADO)
----------------------------------------------------------------------

-- Tel-98 "Teleautomaton"
-- Tributo: N. Tesla, Patente US613809 (1898) — Control remoto sin cables
-- Tier 1: Explorador ligero, resistencia EMP gracias a su arquitectura de blindaje eléctrico
local TEL_98: DroneSpec = {
	id               = "tel_98",
	name             = "Tel-98 «Teleautomaton»",
	historicalTribute = "US613809 / 1898 — Control Remoto Sin Cables",
	tier             = 1,
	maxHealth        = 100,
	armorReduction   = 0.0,
	maxSpeed         = 55,
	turboSpeed       = 90,
	verticalSpeed    = 30,
	accelRate        = 1.6,
	decelRate        = 0.9,
	brakeRate        = 3.2,
	tiltAngle        = math.rad(16),
	tiltSpeed        = 8,
	responsiveness   = 22,
	maxHeat          = 80,
	heatCoolingRate  = 6,
	empResistance    = 0.55,  -- blindaje dieléctrico natural
	cargoCapacity    = 8,
	inertiaAlpha     = 0.045,
	maxCargoMass     = 12,
	hardpoints = {
		{ slotId = "hp1_light", maxCaliber = "light" },
	},
	primaryColor = COL_CARBON,
	accentColor  = COL_NEON_CYN,
}

-- Oehm-24 "Multicross"
-- Tributo: É. Œhmichen, Multicoptero estable de 1924 — primer vuelo de circuito cerrado en helicóptero
-- Tier 2: Equilibrado, alta respuesta vertical para cañones urbanos
local OEHM_24: DroneSpec = {
	id               = "oehm_24",
	name             = "Oehm-24 «Multicross»",
	historicalTribute = "FR-1924 — Primer Circuito Cerrado Multicóptero",
	tier             = 2,
	maxHealth        = 140,
	armorReduction   = 0.08,
	maxSpeed         = 60,
	turboSpeed       = 100,
	verticalSpeed    = 42,  -- punto fuerte: verticalidad en callejones
	accelRate        = 1.5,
	decelRate        = 0.85,
	brakeRate        = 3.5,
	tiltAngle        = math.rad(18),
	tiltSpeed        = 9,
	responsiveness   = 25,
	maxHeat          = 100,
	heatCoolingRate  = 8,
	empResistance    = 0.20,
	cargoCapacity    = 14,
	inertiaAlpha     = 0.040,
	maxCargoMass     = 18,
	hardpoints = {
		{ slotId = "hp1_light",  maxCaliber = "light"  },
		{ slotId = "hp2_medium", maxCaliber = "medium" },
	},
	primaryColor = COL_CARBON,
	accentColor  = COL_CERAMIC,
}

-- Breg-07 "Gyro-Wing"
-- Tributo: L. Breguet, Gyroplane No.1 (1907) — primer vuelo estabilizado por giroscopio
-- Tier 2: Rotores basculantes, velocidad punta alta, agresivo en maniobras horizontales
local BREG_07: DroneSpec = {
	id               = "breg_07",
	name             = "Breg-07 «Gyro-Wing»",
	historicalTribute = "FR-1907 — Gyroplane No.1, Vuelo Estabilizado por Giroscopio",
	tier             = 2,
	maxHealth        = 120,
	armorReduction   = 0.05,
	maxSpeed         = 80,  -- punto fuerte: velocidad crucero alta
	turboSpeed       = 130,
	verticalSpeed    = 28,
	accelRate        = 2.0,  -- más agresivo
	decelRate        = 0.75,
	brakeRate        = 4.0,
	tiltAngle        = math.rad(26),  -- inclinación agresiva
	tiltSpeed        = 11,
	responsiveness   = 28,
	maxHeat          = 110,
	heatCoolingRate  = 7,
	empResistance    = 0.15,
	cargoCapacity    = 10,
	inertiaAlpha     = 0.055,  -- penalización mayor por velocidad
	maxCargoMass     = 14,
	hardpoints = {
		{ slotId = "hp1_medium", maxCaliber = "medium" },
		{ slotId = "hp2_light",  maxCaliber = "light"  },
	},
	primaryColor = COL_CARBON,
	accentColor  = COL_NEON_RED,
}

-- Skor-39 "Heavy-Lift"
-- Tributo: I. Sikorsky, VS-300 (1939) — padre del helicóptero moderno práctico
-- Tier 3: Hexacóptero blindado, reducción pasiva de daño 25%, carga pesada
local SKOR_39: DroneSpec = {
	id               = "skor_39",
	name             = "Skor-39 «Heavy-Lift»",
	historicalTribute = "US-1939 — VS-300, Padre del Helicóptero Moderno",
	tier             = 3,
	maxHealth        = 280,
	armorReduction   = 0.25,  -- reducción pasiva de daño
	maxSpeed         = 45,
	turboSpeed       = 75,
	verticalSpeed    = 25,
	accelRate        = 1.1,
	decelRate        = 0.6,
	brakeRate        = 2.8,
	tiltAngle        = math.rad(12),  -- inclinación conservadora por masa
	tiltSpeed        = 6,
	responsiveness   = 18,
	maxHeat          = 160,
	heatCoolingRate  = 10,
	empResistance    = 0.35,  -- blindaje metálico grueso
	cargoCapacity    = 40,  -- especialidad: carga pesada
	inertiaAlpha     = 0.025,  -- motor más potente compensa la masa
	maxCargoMass     = 55,
	hardpoints = {
		{ slotId = "hp1_medium", maxCaliber = "medium" },
		{ slotId = "hp2_medium", maxCaliber = "medium" },
		{ slotId = "hp3_heavy",  maxCaliber = "heavy"  },
	},
	primaryColor = COL_CARBON,
	accentColor  = COL_CERAMIC,
}

-- W-NER "Daemon-Link"
-- Tributo: N. Wiener, "Cybernetics" (1948) — padre del control de sistemas y retroalimentación
-- Tier 4: Propulsión iónica antigravedad, enlace neuronal sin latencia, disipación máxima
local WNER_T4: DroneSpec = {
	id               = "wner_daemon",
	name             = "W-NER «Daemon-Link»",
	historicalTribute = "1948 Cybernetics — Retroalimentación y Control de Sistemas Adaptativos",
	tier             = 4,
	maxHealth        = 180,
	armorReduction   = 0.15,
	maxSpeed         = 95,
	turboSpeed       = 155,
	verticalSpeed    = 55,
	accelRate        = 2.4,
	decelRate        = 1.2,
	brakeRate        = 5.0,
	tiltAngle        = math.rad(22),
	tiltSpeed        = 14,
	responsiveness   = 35,
	maxHeat          = 200,
	heatCoolingRate  = 22,  -- punto fuerte: disipación de calor instantánea
	empResistance    = 0.80,  -- enlace iónico casi inmune a EMP
	cargoCapacity    = 20,
	inertiaAlpha     = 0.030,
	maxCargoMass     = 25,
	hardpoints = {
		{ slotId = "hp1_cyber",  maxCaliber = "cyber"  },
		{ slotId = "hp2_heavy",  maxCaliber = "heavy"  },
		{ slotId = "hp3_medium", maxCaliber = "medium" },
		{ slotId = "hp4_light",  maxCaliber = "light"  },
	},
	primaryColor = COL_CARBON,
	accentColor  = COL_NEON_RED,
}

----------------------------------------------------------------------
-- ÍNDICE PÚBLICO
----------------------------------------------------------------------
DroneCatalog.All = {
	TEL_98,
	OEHM_24,
	BREG_07,
	SKOR_39,
	WNER_T4,
} :: { DroneSpec }

local byIdDrones: { [string]: DroneSpec } = {}
for _, spec in ipairs(DroneCatalog.All) do
	byIdDrones[spec.id] = spec
end
DroneCatalog.ById = byIdDrones

-- Convierte una DroneSpec en un DroneConfig compatible con DroneController.new()
function DroneCatalog.ToControllerConfig(spec: DroneSpec): { [string]: any }
	return {
		cruiseSpeed   = spec.maxSpeed,
		turboSpeed    = spec.turboSpeed,
		verticalSpeed = spec.verticalSpeed,
		accelRate     = spec.accelRate,
		decelRate     = spec.decelRate,
		brakeRate     = spec.brakeRate,
		tiltAngle     = spec.tiltAngle,
		tiltSpeed     = spec.tiltSpeed,
		responsiveness = spec.responsiveness,
		baseFOV       = 70,
		maxFOV        = 85,
	}
end

-- Devuelve el tier formateado como texto de UI
function DroneCatalog.FormatTier(tier: number): string
	local labels: { string } = { "TIER I", "TIER II", "TIER III", "TIER IV" }
	return labels[tier] or ("TIER " .. tostring(tier))
end

return DroneCatalog

