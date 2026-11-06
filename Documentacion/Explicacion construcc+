# 🏗️ Cyber Delivery Tycoon: Guía Arquitectónica y de Interacción

Esta guía detalla de forma clara, didáctica y técnica cómo fueron construidas **la Base**, **las Gafas FPV**, **las Torres** y **el Sistema de Interacción y Red** que conecta todo el bucle de juego.

---

## 📑 Índice de Contenidos
1. [La Base (Pad_Base y Rampa de Acceso)](#1-la-base-pad_base-y-rampa-de-acceso)
2. [Los Lentes FPV (CyberGoggles)](#2-los-lentes-fpv-cybergoggles)
3. [Las Torres de Reparto (Pad_TorreA y Pad_TorreB)](#3-las-torres-de-reparto-pad_torrea-y-pad_torreb)
4. [Mecánicas de Interacción y Ciclo de Reparto](#4-mecánicas-de-interacción-y-ciclo-de-reparto)
5. [Resumen del Flujo de Datos (Arquitectura Cliente-Servidor)](#5-resumen-del-flujo-de-datos-arquitectura-cliente-servidor)

---

## 1. La Base (Pad_Base y Rampa de Acceso)

### 🧩 Explicación Sencilla
La Base es el cuartel general y punto de partida del jugador. Es una gran plataforma metálica octogonal elevada ligeramente sobre el suelo (`Y = 4`), equipada con un anillo perimetral de neón cian, una cruz luminosa blanca que marca el punto central de despegue y una rampa inclinada para que el avatar pueda subir caminando cómodamente hasta la plataforma del dron.

### 💻 Perspectiva de Programador (`src/server/Main.server.luau`)
La base se genera procedimentalmente en el servidor al arrancar mediante la función `createHelipad()`:

```luau
local pad1 = createHelipad("Pad_Base", Vector3.new(0, 4, 0), Color3.fromRGB(0, 240, 255), true)
pad1.Parent = Workspace.LandingPads
```

1. **Plataforma Estructural (`BasePad`):**
   * Un bloque sólido `Part` de tamaño `(36, 3, 36)` studs, `Anchored = true`, material `Metal` y color grafito oscuro (`Color3.fromRGB(20, 24, 32)`).
   * Funciona como la superficie física de colisión donde descansa el dron (`TestDrone`).
2. **Señalización Visual de Neón:**
   * **Anillo (`NeonRing`):** Bloque perimetral de material `Neon` cian con un `PointLight` integrado (`Brightness = 8`, `Range = 60`) que baña la plataforma en luz volumétrica.
   * **Cruz de Aterrizaje (`LandingCrossH` y `LandingCrossV`):** Dos partes cruzadas en neón blanco puro de 12x3 studs empotradas en la cara superior (`Y + 1.62`) para indicar visualmente el centro de gravedad.
3. **Pilar de Apoyo (`SupportPillar`):**
   * Un bloque masivo de 38x4x38 studs que conecta la base con el terreno en `Y = 0`, asegurando que la plataforma no parezca flotar en el aire.
4. **Rampa de Acceso (`AccessRamp`):**
   * Como `hasRamp = true`, se instancia un `Part` de tamaño `(12, 0.6, 20)` rotado $-14^\circ$ en el eje X:
     ```luau
     local rampAngle = math.rad(-14)
     ramp.CFrame = CFrame.new(position.X, position.Y * 0.5, position.Z + 24) * CFrame.Angles(rampAngle, 0, 0)
     ```
   * Permite que la física del personaje humanoide suba caminando fluidamente sin tropezar.

---

## 2. Los Lentes FPV (CyberGoggles)

### 🧩 Explicación Sencilla
Son unas gafas/visor cibernético de realidad virtual montadas directamente en la cabeza de tu avatar. Cuando caminas por el mapa están en modo *Standby* (color oscuro apagado). En el instante en que presionas **[E]** para pilotar el dron, el visor se enciende en Neón Cian fluorescente e ilumina el rostro del personaje, indicando a todos en el juego que estás operando el dron por telemetría remota.

### 💻 Perspectiva de Programador (`src/shared/CyberGoggles.luau`)
El módulo se encarga de instanciar y soldar dinámicamente las partes del visor a la cabeza del personaje usando restricciones modernas de Roblox:

```
[Avatar Head]
     │ (WeldConstraint)
     ▼
[VisorFrame] (Part Metálica Oscura)
     │
     ├── (WeldConstraint) ──> [VisorLens] (Part Neón + PointLight "VisorGlow")
     └── (WeldConstraint) ──> [Antenna]   (Part Neón Transmisora)
```

1. **Ensamblado Físico (`Attach(character)`):**
   * Busca el hueso/parte `Head` del modelo del personaje.
   * Crea un contenedor `Model` llamado `CyberFPVVisor`.
   * **Marco (`VisorFrame`):** Un `Part` metálico de tamaño `(1.6, 0.45, 0.5)`, soldado mediante `WeldConstraint` con offset `CFrame.new(0, 0.12, -0.65)`. Al ser `Massless = true` y `CanCollide = false`, no altera la masa ni tropieza con paredes.
   * **Lente Holográfica (`VisorLens`):** Part de material `Neon` montado en la parte frontal del marco.
   * **Antena Lateral (`Antenna`):** Mástil emisor montado en la sien izquierda para el toque cyberpunk.
   * **Proyector Facial (`VisorGlow`):** Un `PointLight` dentro de la lente que proyecta luz hacia los ojos y la cara del avatar.
2. **Control de Estados (`SetOnline(character, isOnline)`):**
   * **`isOnline = true` (Pilotando):** `lens.Color` y `antenna.Color` cambian a `Color3.fromRGB(0, 255, 230)` (Neón Cian brillante) y `glow.Brightness = 3`.
   * **`isOnline = false` (A pie):** Pasan a `Color3.fromRGB(40, 50, 65)` (modo reposo) y `glow.Brightness = 0`.

---

## 3. Las Torres de Reparto (Pad_TorreA y Pad_TorreB)

### 🧩 Explicación Sencilla
Las torres son rascacielos gigantescos distribuidos por el mapa. Cada torre tiene:
* Su propia identidad visual (Torre A es Rosa Magenta; Torre B es Amarillo Neón).
* Bandas de luz que simulan los pisos del rascacielos.
* Un **SkyBeam**: una columna de luz vertical inmensa que sube hacia las nubes, para que puedas ver el destino desde kilómetros de distancia incluso a alta velocidad.
* Un helipuerto en la azotea con un cartel holográfico 3D flotante que indica el nombre del edificio.

### 💻 Perspectiva de Programador (`src/server/Main.server.luau`)
Ubicaciones registradas en el servidor:
* **Torre A (`Pad_TorreA`):** `Vector3.new(160, 95, -180)` | Color: `Color3.fromRGB(255, 30, 120)` (Magenta) | Altura: 95 studs.
* **Torre B (`Pad_TorreB`):** `Vector3.new(-200, 50, 140)` | Color: `Color3.fromRGB(255, 200, 0)` (Amarillo) | Altura: 50 studs.

Elementos de ingeniería de cada torre:
1. **Rascacielos Arquitectónico (`SupportPillar`):**
   * Bloque estructural de 30 studs de ancho cuya altura (`pillarHeight`) coincide exactamente con la altitud de la plataforma (`position.Y`), extendiéndose verticalmente desde `Y = 0`.
2. **Tiras de Esquina (`NeonCorner_1..4`):**
   * 4 tiras delgadas de neón vertical de 1.4 studs de grosor colocadas en los 4 vértices del edificio que resaltan el contorno de la torre de noche.
3. **Pisos Iluminados (`FloorBand_1..N`):**
   * Un bucle calcula los pisos cada 20 studs (`pillarHeight / 20`) y genera anillos horizontales semitransparentes (`Transparency = 0.35`) que emulan ventanales de oficinas iluminadas.
4. **Antena y Baliza de Aviación (`CommAntenna`):**
   * Un mástil de comunicaciones de 35 studs en una esquina del helipuerto con un `PointLight` rojo de advertencia para tráfico aéreo (`Color3.fromRGB(255, 0, 50)`).
5. **Haz Tractor Holográfico (`HoloSkyBeam`):**
   * Un cilindro/bloque vertical de 300 studs de altura en material `Neon` colocado sobre la antena. Al emitir luz intensa hacia el cielo, actúa como faro de navegación a larga distancia.
6. **Cartel Flotante Holográfico (`BillboardGui`):**
   * `BillboardGui` anclado a la azotea con `StudsOffset = Vector3.new(0, 10, 0)`, `AlwaysOnTop = true` y `MaxDistance = 1000`.
   * Muestra texto como `◀ TORRE A ▶\n[ZONA DE ATERRIZAJE]`, visible a través de cualquier obstáculo dentro de 1000 studs.

---

## 4. Mecánicas de Interacción y Ciclo de Reparto

### 🧩 Explicación Sencilla
1. **Subir al dron:** Te acercas al dron en la base y pulsas **[E]** (o el botón inferior). Tu personaje se sienta/congela, tus lentes se encienden y tomas el control directo del dron.
2. **Navegación:** En pantalla ves la misión actual (ej: "DESTINO: Torre A (+250 PELAOCOINS)") con una mira holográfica y distancia en studs. Puedes alternar a primera persona con **[V]** y apuntar con el ratón.
3. **Aterrizaje y Entrega:** Al volar sobre la azotea de la torre, el sistema detecta que estás en zona segura. Puedes esperar 0.6 segundos o presionar **[G]**.
4. **Efecto de Entrega:** El imán del dron se desactiva, la caja cae físicamente por gravedad en la azotea, ganas **+250 PELAOCOINS** y tras 1.5 segundos el dron recarga automáticamente un nuevo paquete para el siguiente destino.

---

### 💻 Perspectiva de Programador

### A. Toma de Control Físico (`Main.client.luau` y `Main.server.luau`)
Para lograr que el vuelo responda a 60 FPS sin retraso de red, Roblox requiere transferir la **Network Ownership**:
1. El cliente detecta la pulsación de **[E]** y llama a `myDrone:StartFlying()`.
2. Envía un RemoteEvent al servidor: `flightStateEvent:FireServer("StartFlying")`.
3. El servidor ejecuta:
   ```luau
   dronePart.Anchored = false
   dronePart:SetNetworkOwner(player)
   ```
4. Con el dron desanclado y bajo propiedad física del cliente, las restricciones `LinearVelocity` y `AlignOrientation` son simuladas en local sin lag.
5. El cliente desactiva los controles del personaje (`WalkSpeed = 0`, `JumpPower = 0`) y activa `CyberGoggles.SetOnline(char, true)`.

---

### B. Detección Espacial de Zonas de Helipuerto (`DeliveryManager.luau`)
Cada fotograma en `RunService.RenderStepped`, el `DeliveryManager` evalúa la posición del dron respecto al helipuerto de la torre objetivo:
* **Distancia Horizontal:**
  ```luau
  local horizDist = Vector2.new(dronePos.X - targetPos.X, dronePos.Z - targetPos.Z).Magnitude
  ```
  Debe ser menor a `MAX_HORIZ_DIST = 30` studs.
* **Tolerancia Vertical:**
  ```luau
  local vertDiff = dronePos.Y - targetPos.Y
  ```
  Debe estar entre `MIN_VERT_DIFF = -4` y `MAX_VERT_DIFF = 22` studs (permite vuelo estacionario).
* **Velocidad Segura:**
  La velocidad actual del dron debe ser menor a `MAX_SAFE_SPEED = 35` studs/s.

Si se cumplen las 3 condiciones, el dron se encuentra en `zoneDetected`.

---

### C. Despacho y Validación Anti-Exploit Server-Side
Cuando el jugador pulsa **[G]** o completa la barra de aterrizaje:
1. **Petición del Cliente:**
   `claimDeliveryEvent:FireServer("Pad_TorreA")`
2. **Validación en el Servidor (`Main.server.luau`):**
   * **Anti-Spam Cooldown:** Verifica que hayan pasado al menos 2.0 segundos desde la última entrega del jugador.
   * **Validación de Distancia Real:**
     ```luau
     local dist = (dronePart.Position - basePad.Position).Magnitude
     if dist > 45 then return end -- Rechaza si un hacker intenta reclamar desde lejos
     ```
   * **Acreditación de Recompensa:**
     Incrementa dinámicamente la estadística configurada (`PELAOCOINS`) y el contador de `Entregas`:
     ```luau
     credits.Value += reward      -- +250
     deliveries.Value += 1        -- +1
     deliveryConfirmedEvent:FireClient(player, padName, reward)
     ```

---

### D. Desacople Físico de Carga y Recarga Asíncrona (`DroneCargo.luau`)
Al recibir `deliveryConfirmedEvent`:
1. **Desenganche:**
   * Se destruye el `WeldConstraint` que unía la caja a la base del dron.
   * La caja activa `CanCollide = true`, `Massless = false` y `Anchored = false`.
   * Hereda la inercia del dron más un vector de caída hacia abajo (`Vector3.new(0, -6, 0)`), cayendo físicamente sobre la azotea.
   * Se programa su limpieza con `Debris:AddItem(cargo, 25)`.
2. **Recarga Asíncrona:**
   * Tras 1.5 segundos, `ReloadFreshCargo()` genera una nueva caja bajo el dron, crea un nuevo `WeldConstraint` magnético y enciende el haz tractor.
   * `DeliveryManager` rota al siguiente objetivo (ej: de Torre A pasa a Torre B).

---

## 5. Resumen del Flujo de Datos (Arquitectura Cliente-Servidor)

```
[Cliente: Main.client / DroneController]
       │
       ├── Tecla [E] ────> RemoteEvent "StartFlying" ────> [Servidor: Main.server]
       │                                                         │
       │                                                Desancla TestDrone y
       │                                                asigna NetworkOwnership
       │                                                         │
[Vuelo FPV 60 FPS: AlignOrientation + LinearVelocity] <──────────┘
       │
[Sobrevolar Torre A: Zona Detectada]
       │
       ├── Tecla [G] ────> RemoteEvent "DeliveryCompleted" ─> [Servidor: Validación]
       │                                                             │
       │                                                     Verifica Cooldown (2s)
       │                                                     Verifica Distancia (<45 studs)
       │                                                     +250 PELAOCOINS
       │                                                             │
       │ <──────── RemoteEvent "DeliveryConfirmed" <────────────────┘
       │
       ├── WeldConstraint:Destroy() ──> Caja cae por gravedad a la azotea
       ├── Sonido de entrega + Popup HUD: "+250 PELAOCOINS"
       └── Recarga de nuevo paquete tras 1.5s ──> Siguiente Contrato: Torre B
```

---
*Documento técnico generado para el proyecto Cyber Delivery Tycoon.*
