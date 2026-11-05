# 🛸 Cyber Delivery Tycoon

Juego cyberpunk de entrega con drones desarrollado en **Luau** sincronizado con **Rojo 7.7.1** para **Roblox Studio**.

---

## 🌟 Características Principales
* **Vuelo Físico Suave:** Simulación mediante restricciones `LinearVelocity` y `AlignOrientation` con inercia progresiva (`Lerp`).
* **Cámara FPV y Tercera Persona:** Alterna entre cámara en primera persona dentro de la cabina y vista orbital con la tecla `[V]`.
* **Gafas Holográficas Cyberpunk:** Accesorio holográfico acoplado a la cabeza del avatar que enciende sus lentes de neón al pilotar.
* **HUD Neón Futurista:** Velocímetro, altímetro por raycast, brújula/marcador 3D hacia el helipuerto de entrega y popup animado de recompensas.
* **Efectos Audiovisuales Dinámicos:** 4 estelas de neón cian/magenta en los propulsores, partículas de plasma y modulación de pitch/volumen de turbina en tiempo real.
* **Economía y Rutas de Entrega:** Misiones dinámicas entre helipuertos corporativos (Torre Arasaka, Distrito Neón, Hangar Central) con recompensas en `CyberCréditos` y conteo de entregas.

---

## 🎮 Controles
| Tecla | Acción |
|---|---|
| **E** | Conectar gafas FPV / Iniciar pilotaje |
| **W / S** | Acelerar hacia adelante / Retroceso |
| **A / D** | Desplazamiento lateral (Alabeo con inclinación) |
| **Espacio** | Ascender |
| **Shift / Ctrl / C** | Descender hacia helipuerto |
| **Q** | Activar Turbo Neón |
| **X** | Freno aéreo asistido |
| **V** | Alternar cámara FPV / 3ra Persona |
| **F** / **E** | Desconectar enlace FPV y volver al avatar |

---

## 📂 Estructura del Proyecto
```
robx/
├── default.project.json      # Configuración de mapeo de Rojo
├── Documentacion/            # Auditorías técnicas y análisis de errores
├── src/
│   ├── client/
│   │   └── Main.client.luau  # Controlador cliente y enlace FPV
│   ├── server/
│   │   └── Main.server.luau  # Helipuertos, física de red y economía
│   └── shared/
│       ├── CyberGoggles.luau    # Visor holográfico del avatar
│       ├── DeliveryManager.luau # Rutas y detección de aterrizaje
│       ├── DroneAudio.luau      # Audio dinámico de turbinas
│       ├── DroneCargo.luau      # Contenedor y rayo tractor
│       ├── DroneController.luau # Motor físico de vuelo e inercia
│       ├── DroneHUD.luau        # Interfaz de usuario cyberpunk
│       └── DroneVFX.luau        # Estelas y partículas de plasma
```

---

## 🚀 Despliegue con Rojo
Para sincronizar el proyecto con Roblox Studio:
```bash
rojo serve
```
Y conectar el plugin de Rojo en Roblox Studio.

