# 📘 Cyber Delivery Tycoon — Análisis Integral de Errores y Correcciones

**Proyecto:** Cyber Delivery Tycoon (Roblox Luau / Rojo)  
**Fecha de Auditoría y Corrección:** 5 de Noviembre, 2026  
**Autor:** Nexsson1 & Antigravity AI  

---

## 📑 Tabla de Contenidos
1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Error Crítico 1: El Dron solo sube y no puede descender (Sign Inversion Bug)](#2-error-crítico-1-el-dron-solo-sube-y-no-puede-descender)
3. [Error Crítico 2: Bloqueo de Carga y Tecla [E] Inoperativa (Top-Level Requires Hang)](#3-error-crítico-2-bloqueo-de-carga-y-tecla-e-inoperativa)
4. [Error Crítico 3: Bloqueo de Teclas WASD por el Character Controller (GPE Flag)](#4-error-crítico-3-bloqueo-de-teclas-wasd-por-el-character-controller)
5. [Error Crítico 4: Conflicto de Físicas y Network Ownership (HumanoidRootPart Anchoring)](#5-error-crítico-4-conflicto-de-físicas-y-network-ownership)
6. [Mejoras de Conducción, Físicas y Mapeo de Controles](#6-mejoras-de-conducción-físicas-y-mapeo-de-controles)
7. [Matriz de Estado y Diagnóstico de Archivos](#7-matriz-de-estado-y-diagnóstico-de-archivos)

---

## 1. Resumen Ejecutivo
Durante el desarrollo del sistema de pilotaje para **Cyber Delivery Tycoon**, se detectaron fallos críticos que impedían la experiencia de vuelo:
1. El dron ascendía al presionar la tecla de descender.
2. La tecla `[E]` no activaba el dron o se quedaba permanentemente en estado `(CARGANDO...)`.
3. Una vez en el aire, el dron no respondía a los controles horizontales o se aceleraba instantáneamente sin inercia.

A continuación se detalla la causa raíz técnica de cada falla y la ingeniería aplicada para resolverla.

---

## 2. Error Crítico 1: El Dron solo sube y no puede descender

### 🔍 Causa Raíz
En el bucle de actualización física de `DroneController.luau`, el vector de entrada vertical (`moveY`) se calculaba con la siguiente expresión ternaria:

```luau
-- ❌ CÓDIGO CON ERROR:
local moveY = (if self.inputState.up then 1 else 0) - (if self.inputState.down then -1 else 0)
```

**Análisis Algebraico del Fallo:**
* Al presionar `Espacio` (Subir / Up):
  $$\text{moveY} = 1 - 0 = +1 \quad (\text{Sube})$$
* Al presionar `Shift` (Bajar / Down):
  $$\text{moveY} = 0 - (-1) = 0 + 1 = +1 \quad (\mathbf{¡Sube!})$$
* Al presionar ambas teclas:
  $$\text{moveY} = 1 - (-1) = 1 + 1 = +2 \quad (\mathbf{¡Sube\ al\ doble\ de\ velocidad!})$$

Debido a que restar un número negativo equivale a una suma ($a - (-b) = a + b$), **era matemáticamente imposible obtener un valor negativo para `moveY`**. El dron interpretaba la orden de descender como una orden de ascenso.

### 🛠️ Solución Aplicada
Se corrigió la expresión para que la sustracción opere sobre un valor positivo:

```luau
-- ✅ CÓDIGO CORREGIDO:
local moveY = (if self.inputState.up then 1 else 0) - (if self.inputState.down then 1 else 0)
```

Adicionalmente, se amplió el soporte de teclas en `BindInputs` para permitir descender con:
* `LeftShift` (Shift izquierdo)
* `LeftControl` (Control izquierdo)
* `C` (Tecla estándar de agacharse/descender)

---

## 3. Error Crítico 2: Bloqueo de Carga y Tecla [E] Inoperativa

### 🔍 Causa Raíz
En versiones anteriores de `DroneController.luau`, se invocaban módulos secundarios en el nivel superior (*top-level*) del script:

```luau
-- ❌ Invocación sincrónica bloqueante en la cabecera:
local DroneHUD = require(script.Parent:WaitForChild("DroneHUD"))
local DroneAudio = require(script.Parent:WaitForChild("DroneAudio"))
local DroneVFX = require(script.Parent:WaitForChild("DroneVFX"))
local DroneCargo = require(script.Parent:WaitForChild("DroneCargo"))
local DeliveryManager = require(script.Parent:WaitForChild("DeliveryManager"))
local CyberGoggles = require(script.Parent:WaitForChild("CyberGoggles"))
```

Si cualquiera de estos componentes demoraba en replicarse desde `ReplicatedStorage` o generaba una advertencia/yield, la ejecución del módulo completo se suspendía indefinidamente. Como consecuencia:
* `Main.client.luau` se quedaba esperando a `DroneController`.
* La variable `myDrone` nunca se instanciaba (`nil`).
* El botón permanecía en `[E] CONECTAR GAFAS FPV (CARGANDO...)` y presionar `[E]` no ejecutaba ninguna acción.

### 🛠️ Solución Aplicada
Se implementó un patrón de **Lazy Loading Seguro con Protección de Errores (`pcall`)** dentro de `DroneController.new()`:
* Ningún módulo se carga en el top-level.
* Los submódulos se importan únicamente cuando el controlador es instanciado.
* Si un subsistema secundario (por ejemplo, el audio o una partícula) sufre algún inconveniente, el sistema de vuelo principal continúa operativo al 100%.

---

## 4. Error Crítico 3: Bloqueo de Teclas WASD por el Character Controller

### 🔍 Causa Raíz
En `UserInputService.InputBegan`, se utilizaba la condición estándar:

```luau
-- ❌ gpe bloqueaba las teclas de movimiento:
self.inputBeganConn = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    ...
```

En Roblox, el `PlayerModule` (controlador de movimiento del personaje) procesa las teclas `W`, `A`, `S`, `D` antes que los scripts del usuario y marca la bandera `gameProcessedEvent` (`gpe`) como `true`. Como resultado, el dron ignoraba completamente las pulsaciones de dirección.

### 🛠️ Solución Aplicada
1. Se deshabilitó el filtrado de `gpe` para teclas de juego durante la sesión de pilotaje.
2. Para evitar que el avatar camine en el suelo mientras pilota el dron, se neutraliza el movimiento del personaje asignando:
   ```luau
   humanoid.WalkSpeed = 0
   humanoid.JumpHeight = 0
   humanoid.JumpPower = 0
   ```
3. Se desactivan los controles nativos mediante `playerControls:Disable()`.

---

## 5. Error Crítico 4: Conflicto de Físicas y Network Ownership

### 🔍 Causa Raíz
Inicialmente se intentaba anclar el `HumanoidRootPart` del avatar desde el cliente (`root.Anchored = true`) al momento de subir al dron. Esto creaba un conflicto de sincronización entre el cliente y el servidor:
* El motor de físicas de Roblox priorizaba la simulación del personaje anclado.
* `SetNetworkOwner(player)` sobre el `TestDrone` en el servidor no lograba transferir el control suavemente porque el cliente estaba en un estado físico ambiguo.

### 🛠️ Solución Aplicada
* Se eliminó el anclaje forzado de `HumanoidRootPart` en el cliente.
* La inmovilidad del avatar se gestiona únicamente mediante `WalkSpeed = 0` y `JumpPower = 0`.
* El servidor se encarga de desanclar el `TestDrone` (`dronePart.Anchored = false`) inmediatamente antes de otorgar el `SetNetworkOwner(player)`.

---

## 6. Mejoras de Conducción, Físicas y Mapeo de Controles

### 🎛️ Tabla de Controles del Dron
| Tecla | Acción | Descripción |
|---|---|---|
| **W** | Avanzar | Empuje frontal alineado a la vista de la cámara |
| **S** | Retroceder | Empuje en reversa |
| **A** | Alabeo / Giro Izq. | Desplazamiento lateral izquierdo con inclinación |
| **D** | Alabeo / Giro Der. | Desplazamiento lateral derecho con inclinación |
| **Espacio** | Ascender | Impulso vertical positivo constante |
| **Shift / Ctrl / C** | Descender | Impulso vertical negativo suave hacia helipuerto |
| **Q** | Turbo Neón | Incrementa la velocidad de 60 a 110 studs/s |
| **X** | Freno Aéreo | Deceleración rápida asistida por propulsores |
| **V** | Alternar Cámara | Alterna entre vista FPV en cabina y vista 3ra persona |
| **E / F** | Desconectar Gafas | Regresa al avatar y ancla el dron en el helipuerto |

### 🚀 Calibración de Inercia Progresiva
* **Velocidad Crucero:** 60 studs/s (antes 75, optimizada para aterrizajes de precisión).
* **Velocidad Turbo:** 110 studs/s (con consumo de energía holográfica).
* **Tasa de Aceleración (`accelRate`):** 1.5 (suavizado progresivo mediante interpolación lineal `Lerp`).
* **Tasa de Frenado (`brakeRate`):** 3.5 con tecla `X`.

---

## 7. Matriz de Estado y Diagnóstico de Archivos

| Archivo | Estado | Responsabilidad |
|---|---|---|
| `src/server/Main.server.luau` | ✅ Operativo | Generación de helipuertos, economía (`leaderstats`), `TestDrone` y delegación de `NetworkOwnership`. |
| `src/client/Main.client.luau` | ✅ Operativo | HUD de estado en pantalla, detección de tecla `[E]`, equipamiento de gafas cyberpunk y arranque seguro. |
| `src/shared/DroneController.luau` | ✅ Operativo | Motor de física con `LinearVelocity` y `AlignOrientation`, inercia progresiva, descenso y ascenso. |
| `src/shared/DroneHUD.luau` | ✅ Operativo | Interfaz cyberpunk con velocímetro, altímetro, minimapa/waypoint, barra de turbo y popup de recompensas. |
| `src/shared/DroneAudio.luau` | ✅ Operativo | Modulación continua de pitch y volumen de turbina según velocidad y empuje. |
| `src/shared/DroneVFX.luau` | ✅ Operativo | 4 estelas de neón cian/magenta en las esquinas de los propulsores y partículas de plasma. |
| `src/shared/DroneCargo.luau` | ✅ Operativo | Contenedor acoplado en la parte inferior con rayo tractor. |
| `src/shared/DeliveryManager.luau` | ✅ Operativo | Detección de aterrizaje en helipuertos, cálculo de recompensas y asignación de rutas. |
| `src/shared/CyberGoggles.luau` | ✅ Operativo | Visor holográfico en la cabeza del avatar con lentes iluminados al conectar FPV. |
| `src/shared/NetworkEvents.luau` | ✅ Operativo | Módulo centralizado de RemoteEvents tipados para cliente y servidor. |

---

## 8. Fase de Seguridad y Arquitectura Server-Side (v4.1)

### 🛡️ 1. Validación Server-Side Anti-Exploits (`Main.server.luau`)
Anteriormente, el evento `DeliveryCompleted` aceptaba peticiones directas del cliente sin validación física, permitiendo potencialmente cobros arbitrarios. Se implementó una triple barrera en el servidor:
1. **Cooldown de Entrega:** Límite mínimo de 3 segundos entre entregas por jugador para evitar peticiones masivas en bucle.
2. **Validación de Rango Físico:** Verificación de coordenadas reales entre `TestDrone` y el helipuerto (`distancia horizontal <= 18 studs`, `desplazamiento vertical entre -2 y +10 studs`).
3. **Validación de Velocidad de Aterrizaje:** El servidor exige que la velocidad lineal del chasis (`AssemblyLinearVelocity.Magnitude`) sea inferior o igual a 20 studs/s en el momento del reclamo.
4. **Respuesta Verificada:** Solo tras superar los 3 filtros, el servidor otorga `CyberCréditos`, incrementa las entregas y dispara el evento `DeliveryConfirmed` de vuelta al cliente.

### 🌐 2. Centralización de Remotes (`NetworkEvents.luau`)
Se eliminaron las búsquedas dispersas de `RemoteEvents` con strings mágicos en el DataModel. El nuevo módulo `src/shared/NetworkEvents.luau`:
* Genera e inicializa los eventos de red en una carpeta dedicada (`CyberNetworkEvents`).
* Ofrece resolución segura con `NetworkEvents.Get(...)` para cliente y servidor con tipado estricto.

### 🧹 3. Ciclo de Vida y Limpieza de Recursos (`:Destroy()`)
Se integró el método `:Destroy()` en `DroneController.luau` y `DeliveryManager.luau`:
* Desconecta los bucles de actualización física (`RenderStepped`).
* Destruye de forma segura los ScreenGuis de la interfaz holográfica (`DroneHUD`).
* Libera sonidos de turbinas con fade out gradual (`DroneAudio`).
* Elimina emisores y estelas (`DroneVFX`), contenedores (`DroneCargo`) y desvincula eventos de entrada del teclado.

---

## 9. Fase 2: Catálogo de Drones, Arsenal Táctico, IA Enemiga 3D y Físicas de Inercia

### 🛸 1. Catálogo de Drones con Tributo Histórico (`src/shared/DroneCatalog.luau`)
Se implementó un catálogo tipado (`--!strict`) con 4 Tiers y 5 drones de autor que homenajean a pioneros de la aviación, radio y cibernética mediante códigos industriales y patentes históricas:
1. **Tel-98 «Teleautomaton» (Tier 1):** Homenaje a la patente US613809 (Nikola Tesla, 1898) sobre control remoto por radiofrecuencia. Quad experimental ligero con blindaje dieléctrico (resistencia EMP del 55%) y 1 punto de anclaje.
2. **Oehm-24 «Multicross» (Tier 2):** Homenaje al vuelo en circuito cerrado de Étienne Œhmichen (1924). Quad equilibrado con alta respuesta vertical (42 studs/s) optimizado para cañones urbanos estrechos.
3. **Breg-07 «Gyro-Wing» (Tier 2):** Homenaje al Gyroplane No.1 de Louis Breguet (1907). Rotores basculantes con velocidad crucero elevada (80 studs/s, turbo 130 studs/s) e inclinación agresiva de 26°.
4. **Skor-39 «Heavy-Lift» (Tier 3):** Homenaje al VS-300 de Igor Sikorsky (1939). Hexacóptero blindado con 280 HP, reducción pasiva de daño del 25%, gran bahía de carga y 3 anclajes de armas.
5. **W-NER «Daemon-Link» (Tier 4):** Homenaje a Norbert Wiener y la teoría cibernética (1948). Propulsión antigravedad/iónica sin hélices mecánicas, disipación de calor instantánea (22 pts/s), 80% resistencia a EMP y enlace neuronal de respuesta inmediata.

Incluye la función puente `DroneCatalog.ToControllerConfig(spec)` para traducir automáticamente cualquier ficha de dron a los parámetros de vuelo leídos por `DroneController.new()`.

### ⚡ 2. Arsenal Táctico y Tipologías de Daño (`src/shared/DroneWeapons.luau` y `CombatService.server.luau`)
Se diseñó un sistema armamentístico en 4 familias tecnológicas cyberpunk:
1. **Térmica / Plasma («Magma-Spike Mk.II»):** Lanza-plasma que aplica daño continuo (*DoT* de 6 HP/s durante 3.5s) y genera turbulencia térmica que reduce la sustentación vertical de la víctima en un 35% durante 2 segundos.
2. **Cinética / Gauss («Rail-Driver HVP»):** Cañón de riel hipersónico (*Hitscan* mediante `Raycast` autoritativo). Atraviesa cristales/paneles compuestos y aplica un impulso de 85 Newtons que colapsa momentáneamente el `AlignOrientation` del blanco provocando pérdida de control angular.
3. **Misiles Guiados («Smart Gyro-Lock M4»):** Cabeza buscadora subsónica (90 studs/s) que corrige su trayectoria hacia el objetivo mediante curvas Bézier cuadráticas y detona con onda de fragmentación (120 N de impulso).
4. **Ciberguerra / Microondas («Synapse Overheat»):** Rayo continuo de alta frecuencia (20 Hz) que inyecta calor térmico puro en el hardware enemigo. Al llegar al 100% de calor, fuerza un estado `Overheated/EMP` que apaga las restricciones de vuelo (`LinearVelocity.Enabled = false` y `AlignOrientation.Enabled = false`) durante 2 segundos provocando caída libre gravitatoria.

### 🤖 3. Facciones Hostiles e Inteligencia Artificial 3D a 10 Hz (`EnemyTypes.luau` y `EnemyAIService.server.luau`)
Se desarrolló un subsistema de IA pura sin `PathfindingService`, ejecutado en el servidor a 10 Hz mediante acumuladores sobre `RunService.Heartbeat`:
1. **Scav-Gnats (Enjambre Chatarrero):** Pequeños quads que operan en enjambre utilizando algoritmos de separación y persecución (*Seek* + *Separation*). Aplican embestidas físicas directas (*Ramming*) de 55 N para desestabilizar al dron del jugador y forzar la caída o destrucción de paquetes.
2. **Aegis-44 (Torreta Estacionaria):** Centinelas en cornisas con cono de detección angular de 120°. Realizan intercepción balística y disparan ráfagas de Rail-Driver si detectan naves sin autorización en un radio de 160 studs.
3. **Kuroshio V (Interceptores Corporativos):** Drones de intercepción ágiles (70 studs/s) que calculan vectores tangenciales para orbitar lateralmente a 100 studs del jugador mientras lo hostigan con microondas para inducir sobrecalentamiento.

### 📦 4. Acoplamiento Físico con Cargas e Inercia Real (`DroneCargo.luau` y `DroneController.luau`)
El peso de los paquetes afecta la simulación dinámica en tiempo real:
- **Penalización de Velocidad:** $\text{VelocidadEfectiva} = \frac{\text{VelocidadBase}}{1 + (\text{MasaCarga} \times \alpha)}$, garantizando una respuesta más pesada, mayor distancia de frenado y menor aceleración.
- **Detonación por Energía Cinética:** El sistema evalúa el impacto cinético ($E_k = \frac{1}{2} M_{\text{total}} \|\vec{v}\|^2$). Si una carga clasificada como inestable choca a alta velocidad superando el umbral de 4,000 Joules, se genera una detonación física con `Explosion` que destruye el contenedor y desestabiliza el dron.

---

## 10. Optimización de Helipuertos y Sistema de Desenganche Físico de Entrega con Tecla [G]

### 🏷️ 1. Simplificación de Nombres de Helipuertos y Señalética Holográfica
Para evitar confusión con lore cyberpunk en esta fase de desarrollo y ofrecer máxima claridad operativa en el mapa y la interfaz:
* **Pad_Base** (Posición: `0, 4, 0`): Helipuerto central de operaciones y recarga con rampa de acceso. Letrero holográfico 3D: `BASE`.
* **Pad_TorreA** (Posición: `160, 95, -180`, Altura: 95 studs): Rascacielos principal en neón magenta con antena de comunicaciones. Letrero holográfico 3D: `TORRE A`.
* **Pad_TorreB** (Posición: `-200, 50, 140`, Altura: 50 studs): Rascacielos intermedio en neón dorado. Letrero holográfico 3D: `TORRE B`.

Se sincronizaron de forma homogénea las definiciones en `Main.server.luau`, `DeliveryManager.luau` y `DroneHUD.luau`.

### 📦 2. Diagnóstico y Corrección Integral de la Tecla [G] y la Entrega de Carga
**Causa Raíz de que «la tecla G no dejaba el paquete»:**
1. **Falta de Desacople Físico Real:** En versiones previas, `DroneCargo.DeliverAndReload()` creaba un clon estático anclado en el helipuerto pero **nunca destruía el `WeldConstraint`** ni modificaba `self.cargoBox`. Por tanto, el jugador seguía viendo la caja pegada a la panza del dron en todo momento, dando la impresión de que presionar `[G]` no tenía ningún efecto.
2. **Tolerancias de Zona Excesivamente Rígidas:** El radio horizontal estaba fijado en 22 studs y la altura máxima en 12 studs. En helipuertos de 32 a 36 studs de ancho, si el dron sobrevolaba a 14 studs de altitud o cerca del borde exterior de la plataforma, `CheckPadZone` retornaba `false` y cancelaba la entrega sin retroalimentación visual clara.
3. **Falta de Feedback en Caso Fuera de Zona:** Si el usuario presionaba `[G]` en vuelo o en la base, no recibía un mensaje explicativo visible en pantalla.

**Solución Implementada:**
1. **Desenganche Dinámico por Gravedad:**
   * Al validarse la entrega, `self.weld:Destroy()` destruye de inmediato la unión física.
   * `self.cargoBox` activa colisión (`CanCollide = true`), desactiva massless (`Massless = false`) y se desancla (`Anchored = false`).
   * Se transfiere la velocidad lineal y angular del dron más un vector de descenso (`Vector3.new(0, -6, 0)`), haciendo que la caja caiga por gravedad real y ruede/se asiente sobre el helipuerto.
   * El haz tractor magnético se apaga temporalmente y suena un pitido de liberación magnética (`rbxassetid://9114223170`).
   * La caja liberada pasa a `Workspace` y se limpia tras 25 segundos con `Debris`.
2. **Recarga Asíncrona de Nuevo Pedido:**
   * Tras 1.5 segundos de soltar la carga, `ReloadFreshCargo()` genera automáticamente un nuevo contenedor sellado bajo el dron, restablece el `WeldConstraint`, reactiva el haz tractor magnético holográfico y asigna el siguiente destino de reparto.
3. **Ampliación de Tolerancias de Detección:**
   * Radio horizontal ampliado a **30 studs** (cubre todo el helipuerto y su borde con holgura).
   * Rango de altitud vertical ampliado de **-4 a +25 studs** (permite planear cómodamente sobre la plataforma sin peligro de colisión).
   * Velocidad máxima autorizada ampliada a **35–40 studs/s** para permitir entregas dinámicas al vuelo.
4. **Retroalimentación en Tiempo Real en HUD:**
   * Si el jugador pulsa `[G]` fuera de zona, el HUD muestra en rojo: `[G] NO DISPONIBLE: Helipuerto más cercano: Torre A a XX studs`.
   * Si pulsa `[G]` en la base inicial antes de salir, se le indica: `Ya estás en Base. Vuela hacia Torre A`.
   * Al entregar exitosamente, se muestra el popup dorado: `¡ENTREGA EXITOSA EN TORRE A! +250 CYBER-CRÉDITOS`.

---

## 11. Corrección Definitiva: Error «SISTEMA DE ENTREGA NO DISPONIBLE» y Resiliencia de Red

### 🔍 1. Diagnóstico de Causa Raíz
Al presionar la tecla `[G]`, la interfaz mostraba en rojo: **`SISTEMA DE ENTREGA NO DISPONIBLE`**. La inspección de los logs oficiales de Roblox Studio (`%LOCALAPPDATA%\Roblox\logs`) arrojó el fallo definitivo:
```
Error: ReplicatedStorage.DeliveryManager:32: Expected '->' when parsing function type, got '='
Warning: [DroneController] Falló require(DeliveryManager) bajo demanda: Requested module experienced an error while loading
```
1. **Error de Sintaxis en Tipado Luau:** En `src/shared/DeliveryManager.luau`, la definición del tipo de callback estaba escrita como `((reward: number, padName: string) => ())?` utilizando `=>` (sintaxis de TypeScript/JS) en lugar de `->` (sintaxis requerida por Luau estricto).
2. **Fallo en Tiempo de Parseo:** Roblox no podía compilar `DeliveryManager.luau` y marcaba el módulo como corrupto en memoria (`Requested module experienced an error while loading`).
3. **Cascada de Fallos:** Cualquier intento de importar `DeliveryManager` fallaba de inmediato, dejando `self.deliveryManager = nil` e impidiendo que el HUD mostrara la tarjeta de misión y que la tecla `[G]` procesara entregas.

### 🛠️ 2. Solución de Ingeniería Implementada
1. **Corrección de Tipado en `DeliveryManager.luau`:**
   * Se corrigió la signatura a `onDeliveryCallback: ((reward: number, padName: string) -> ())?`.
   * El módulo ahora compila y carga limpiamente en Luau estricto sin errores.
2. **Resolución Segura de Eventos de Red (`NetworkEvents.luau` y `DeliveryManager.luau`):**
   * Se modificó `NetworkEvents.Get()` para usar búsqueda inmediata con `FindFirstChild` antes de cualquier yield, reduciendo la latencia de arranque a 0 ms si los objetos ya están replicados.
   * Se incorporó la función auxiliar `resolveRemote()` en `DeliveryManager.luau`: comprueba `NetworkEvents.Get`, luego `CyberNetworkEvents`, y finalmente la raíz de `ReplicatedStorage`.
3. **Mecanismo de Auto-Recuperación y Blindaje de Ciclo de Vida (`DroneController.luau`):**
   * Activación garantizada en `new()`, en `StartFlying()` al presionar `[E]`, y auto-recuperación al pulsar `[G]`.
4. **Reubicación de `missionBox` en el HUD:**
   * Se reposicionó el recuadro de misión a `Y = 160` studs para evitar que la lista de jugadores de Roblox Studio lo oculte.

---

## 12. Desacople del Nombre de la Moneda («PIGICOINS») y Resiliencia en Validación Server-Side

### 🔍 1. Diagnóstico de Causa Raíz
Al modificar el nombre de la recompensa/moneda en `src/server/Main.server.luau` de `"CyberCréditos"` a `"PIGICOINS"`, las entregas dejaron de funcionar por completo.
1. **Búsqueda Rígida en el Servidor (`claimDeliveryEvent`):**
   En el evento del servidor `claimDeliveryEvent.OnServerEvent`, la lógica buscaba estrictamente:
   ```luau
   local credits = leaderstats:FindFirstChild("CyberCréditos") :: IntValue?
   local deliveries = leaderstats:FindFirstChild("Entregas") :: IntValue?

   if credits and deliveries then
       credits.Value += reward
       deliveries.Value += 1
       deliveryConfirmedEvent:FireClient(player, padName, reward)
   end
   ```
2. **Fallo Silencioso de Validación:**
   Al renombrar el valor en `leaderstats` a `"PIGICOINS"`, `FindFirstChild("CyberCréditos")` retornaba `nil`.
   Como resultado, la condición `if credits and deliveries then` se evaluaba como `false`.
3. **Bloqueo del Ciclo de Entrega en Cliente:**
   Dado que el servidor nunca ejecutaba `deliveryConfirmedEvent:FireClient()`, el cliente jamás recibía la confirmación. Sin esa confirmación:
   * La caja física nunca se desacoplaba (`weld:Destroy()` no ocurría).
   * El HUD nunca mostraba el popup de éxito ni actualizaba la misión.
   * El jugador quedaba permanentemente atascado creyendo que la entrega no funcionaba.

### 🛠️ 2. Solución de Ingeniería Implementada
1. **Centralización y Búsqueda Robusta en Servidor (`Main.server.luau`):**
   * Se definió la constante `local CURRENCY_NAME = "PIGICOINS"`.
   * En `claimDeliveryEvent`, la resolución de créditos ahora utiliza un enfoque multi-nivel:
     1. Busca `leaderstats:FindFirstChild(CURRENCY_NAME)`.
     2. Fallback a `"PIGICOINS"` y `"CyberCréditos"`.
     3. Fallback inteligente: itera cualquier `IntValue` dentro de `leaderstats` que no sea `"Entregas"`.
   * Se añadió un log de advertencia claro (`warn`) en lugar de fallar en silencio si alguna estadística no se encuentra.
2. **Sincronización Dinámica en el HUD del Cliente (`DroneHUD.luau`):**
   * Se implementó la función auxiliar `getCurrencyName()` que lee directamente el nombre de la moneda configurada en `leaderstats` del jugador local en tiempo de ejecución.
   * Todas las etiquetas del HUD (`missionRewardLabel`, `successText`) ahora muestran dinámicamente `+250 PIGICOINS` (o el nombre que el usuario asigne) sin requerir reescrituras de código.

---

## 13. Pulido de Primera Persona (FPV) con Giro de Mouse y Corrección Aerodinámica de Inclinación Lateral (Roll)

### 🔍 1. Diagnóstico de Causas Raíz
1. **Primera Persona (FPV) Bloqueada en Línea Recta:**
   * Al presionar `[V]` para pasar a primera persona, `cam.CameraType = Enum.CameraType.Scriptable` desactivaba por completo el sistema orbital de cámara nativo de Roblox.
   * `DroneController.luau` carecía de un listener de movimiento de mouse (`UserInputService.InputChanged`).
   * No se bloqueaba el cursor al centro de la pantalla (`UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter`), de modo que el puntero se movía libremente por la pantalla sin registrar giros.
   * La orientación del dron se calculaba rígidamente en un bucle circular a partir del propio LookVector del dron, impidiendo que el jugador pudiera virar o mirar hacia los lados.
2. **Inclinación Invertida hacia los Lados (Roll Invertido):**
   * En `targetRoll = moveX * self.config.tiltAngle`, al presionar `D` (`moveX = 1`), el valor de rotación en el eje Z era positivo.
   * En el sistema de coordenadas de Roblox, una rotación positiva en Z eleva el lado derecho (`RightVector.Y > 0`) hacia el cielo.
   * Esto exponía el vientre del dron al aire frontal/lateral como una cometa levantada contra el viento, generando una sensación física contraria a la aerodinámica real de un cuadricóptero (donde para desplazarse a la derecha, el dron debe ladearse hacia abajo a la derecha para dirigir el empuje).

### 🛠️ 2. Solución de Ingeniería Implementada
1. **Control Total de Giro y Mirada en Primera Persona (FPV):**
   * **Variables de Rumbo Dinámico:** Se añadieron `self.flightYaw` (rumbo horizontal en radianes) y `self.fpvPitch` (ángulo de visión vertical del piloto).
   * **Giro de Vuelo con Mouse:** Se vinculó `UserInputService.InputChanged` para capturar `MouseMovement`, permitiendo al jugador girar 360° en vuelo con el mouse con sensibilidad calibrada (`0.003` rad/px) y mirar verticalmente arriba/abajo dentro de $\pm 60^\circ$.
   * **Bloqueo Centrado del Cursor (`LockCenter`):** Al activar FPV (`[V]`), el cursor se ancla y oculta en el centro de la pantalla. Al volver a 3ra persona o detener el vuelo, se restaura a `Default`. Al hacer clic en pantalla se reasegura el anclaje si el jugador abrió algún menú.
   * **Soporte de Teclado:** Se añadió soporte para girar el rumbo también con las flechas del teclado (`Izquierda` y `Derecha`).
   * **Transición Fluida 1ra / 3ra Persona:** En 3ra persona, `flightYaw` se sincroniza automáticamente con la rotación orbital de la cámara; al entrar a FPV, el dron continúa exactamente en la misma dirección sin saltos bruscos.
   * **Sensación Cinemática de Cabina:** La cámara en FPV se posicionó en la parte delantera superior del fuselaje (`Vector3.new(0, 0.45, -size.Z * 0.5 - 0.2)`), con una inclinación física sutil sincronizada con el balanceo del fuselaje y un campo visual dinámico (FOV) que se expande de 85° a 100° con el turbo.
2. **Corrección Aerodinámica del Roll Lateral:**
   * Se invirtió la fórmula a:
     ```luau
     local targetRoll = -moveX * self.config.tiltAngle
     ```
   * Al presionar `D` (derecha), el lado derecho del dron desciende y el lado izquierdo se eleva, inclinando la aeronave hacia la derecha para dirigir los vectores de propulsión y cortar el aire aerodinámicamente.
   * Al presionar `A` (izquierda), el lado izquierdo desciende simétricamente.
   * El horizonte artificial holográfico del HUD se sincroniza automáticamente con la inclinación real.

---
*Fin del documento de auditoría técnica.*

