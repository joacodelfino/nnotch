# nnotch

Centro de control interactivo y modular en el notch para macOS, construido 100% en **Swift + SwiftUI** (sin dependencias externas, compila directo por terminal sin requerir Xcode completo).

> Basado originalmente en [`sayweer/dynamicIsland`](https://github.com/sayweer/dynamicIsland) (MIT), adaptado y evolucionado como proyecto propio **nnotch**.

## Qué incluye actualmente

- **Notch nativo (`NotchPanel` + `NotchHostingView`)**: ventana `NSPanel` transparente arriba de la barra de menú, sin robar foco y dejando pasar los clicks fuera de la isla.
- **Inicio (`HomeView`)**: reproductor universal (YouTube, Brave, Safari, Chrome, Zen, Spotify, Apple Music y cualquier app con sonido vía CoreAudio), zonas rápidas de AirDrop y Bandeja, accesos directos editables y métricas de CPU/RAM/Red.
- **Calendario y Recordatorios (`CalendarTabView`)**: integrado con `EventKit` de macOS, incluidas las cuentas de Google configuradas en Cuentas de Internet.
- **Notas Rápidas y Links (`NotesTabView`)**: bloc rápido persistente dentro del notch.
- **Bandeja de Archivos (`ShelfView`)** y **Portapapeles (`ClipboardView`)**.
- **Herramientas (`ToolsView`)**: Pomodoro, cuenta regresiva, cronómetro y monitor de sistema/red en grilla 2×2.
- **Ajustes (`SettingsView`)**: panel rápido dentro del notch + ventana completa de configuración.

## Compilar y ejecutar

```bash
# Compila nnotch.app en modo release y lo abre
./build-app.sh --run
```

El bundle compilado queda en `build/nnotch.app`.

## Estructura para agregar nuevos módulos

1. **Estado / Lógica**: agregar un manager `@MainActor final class MiModulo: ObservableObject` en `Sources/NNotch/Managers/`.
2. **Pestaña**: sumar el `case` en `IslandTab` (`Sources/NNotch/NotchViewModel.swift`).
3. **Vista**: crear la vista en `Sources/NNotch/Views/` y conectarla en el `switch vm.activeTab` de `Sources/NNotch/Views/ExpandedView.swift`.

## Conectar Google Calendar

1. En nnotch → Calendario → Google, tocá **Permitir Calendario a nnotch** y autorizá el acceso en el diálogo de macOS. Si antes lo denegaste, habilitá nnotch en Privacidad y seguridad → Calendarios.
2. Si ya tenés Google en macOS con **Calendarios** activado, no necesitás agregarlo otra vez.
3. Si todavía no lo agregaste, abrí **Cuentas de Internet**, agregá Google y activá **Calendarios**. Luego volvé a nnotch.
4. En **Cuentas**, elegí los calendarios que querés mostrar. Se muestran los eventos de los próximos 14 días.

La sesión web de versiones anteriores no daba acceso fiable a los eventos y ya no se utiliza. Las cuentas con nombre Google o Gmail se detectan automáticamente; si tu cuenta de trabajo tiene otro nombre, sus eventos siguen disponibles en **Todos** o **Mac**.
