# JNotch

Centro de control interactivo y modular en el notch para macOS, construido 100% en **Swift + SwiftUI** (sin dependencias externas, compila directo con Swift Package Manager sin requerir Xcode completo).

> Basado originalmente en [`sayweer/dynamicIsland`](https://github.com/sayweer/dynamicIsland) (MIT), adaptado y traducido como base modular propia para **JNotch**.

## Qué incluye la base actual

- **Notch nativo (`NotchPanel` + `NotchHostingView`)**: ventana `NSPanel` transparente arriba de la barra de menú, sin robar foco y dejando pasar los clicks fuera de la isla.
- **Inicio (`HomeView`)**: reproductor de música (Spotify / Apple Music) con carátula y barra de progreso, zonas rápidas de AirDrop y Bandeja, accesos directos a apps y métricas de CPU/RAM/Red.
- **Calendario y Recordatorios (`CalendarTabView`)**: integrado directo con `EventKit` de macOS.
- **Notas Rápidas y Links (`NotesTabView`)**: bloc rápido persistente dentro del notch.
- **Bandeja de Archivos (`ShelfView`)** y **Portapapeles (`ClipboardView`)**.
- **Herramientas (`ToolsView`)**: Pomodoro, cuenta regresiva, cronómetro, agua, contador y fechas clave.
- **Módulos encendibles/apagables (`SettingsView`)**: desde Ajustes podés activar o desactivar cualquier pestaña.

## Compilar y ejecutar

```bash
# Compila JNotch.app en modo release y lo abre
./build-app.sh --run
```

El bundle compilado queda en `build/JNotch.app`.

## Estructura para agregar nuevos módulos

1. **Estado / Lógica**: agregar un manager `@MainActor final class MiModulo: ObservableObject` en `Sources/JNotch/Managers/`.
2. **Pestaña**: sumar el `case` en `IslandTab` (`Sources/JNotch/NotchViewModel.swift`).
3. **Vista**: crear la vista en `Sources/JNotch/Views/` y conectarla en el `switch vm.activeTab` de `Sources/JNotch/Views/ExpandedView.swift`.
