# nnotch

Centro de control interactivo y modular en el notch para macOS, construido 100% en **Swift + SwiftUI** (sin dependencias externas, compila directo por terminal sin requerir Xcode completo).

> Basado originalmente en [`sayweer/dynamicIsland`](https://github.com/sayweer/dynamicIsland) (MIT), adaptado y evolucionado como proyecto propio **nnotch**.

## Qué incluye actualmente

- **Notch nativo (`NotchPanel` + `NotchHostingView`)**: ventana `NSPanel` transparente arriba de la barra de menú, sin robar foco y dejando pasar los clicks fuera de la isla.
- **Inicio (`HomeView`)**: reproductor universal (YouTube, Brave, Safari, Chrome, Zen, Spotify, Apple Music y apps con sonido vía CoreAudio), con controles de reproducción; zonas rápidas de AirDrop y Bandeja, accesos directos editables y métricas de CPU/RAM/Red. En Safari, los controles web dependen de los permisos de Automatización y JavaScript desde eventos de Apple.
- **Calendario mensual**: grilla de lunes a domingo, selección de día, navegación entre meses, eventos y enlaces para unirse a reuniones. Integrado con `EventKit` de macOS, incluidas las cuentas de Google configuradas en Cuentas de Internet.
- **Notas Rápidas y Links (`NotesTabView`)**: bloc rápido persistente dentro del notch.
- **Bandeja de Archivos (`ShelfView`)** y **Portapapeles (`ClipboardView`)**. La bandeja permite selección individual, selección con ⌘-clic o rectángulo, arrastre de varios archivos y vaciado con confirmación.
- **Herramientas (`ToolsView`)**: Pomodoro, cuenta regresiva, cronómetro y monitor de sistema/red en grilla 2×2, con tarjetas compactas alineadas al área del resto de los módulos.
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
4. En **Cuentas**, elegí los calendarios que querés mostrar. Podés navegar entre meses y seleccionar un día para ver sus eventos.

La sesión web de versiones anteriores no daba acceso fiable a los eventos y ya no se utiliza. Las cuentas con nombre Google o Gmail se detectan automáticamente; si tu cuenta de trabajo tiene otro nombre, sus eventos siguen disponibles en **Todos** o **Mac**.

## Avisos de eventos

Con nnotch en ejecución y el módulo Calendario habilitado, el notch se abre al empezar un evento con hora. Muestra el título, el horario y **Unirse** cuando hay enlace de reunión. El aviso dura 20 segundos; se puede cerrar o abrir el calendario desde él.

- La campana de Calendario activa o desactiva los avisos (se guarda la preferencia).
- Los avisos respetan los calendarios habilitados en **Cuentas**, independientemente del filtro o mes que estés mirando.
- Los eventos simultáneos aparecen juntos. Un evento no vuelve a avisar después de reiniciar nnotch.
- Los eventos de todo el día no generan avisos. Si la Mac estaba dormida, solo se avisa de eventos que empezaron hace menos de un minuto.
- En **Cuentas → Probar aviso** podés comprobar la presentación sin crear eventos en tu calendario.

Las pruebas de fechas, cambios de horario y programación de avisos se ejecutan con `bash scripts/test-calendar.sh`.

## Bandeja flotante

La bandeja flotante es una función propia de nnotch, inspirada en el flujo de Dropover; no requiere tener Dropover instalado ni se conecta con esa aplicación.

Mientras arrastrás archivos desde Finder, sacudí el mouse de izquierda a derecha varias veces rápidamente: aparece una bandeja junto al cursor. Soltá archivos ahí y luego arrastralos a otra app. También podés abrirla desde el menú de nnotch → **Abrir bandeja flotante**.

La bandeja flotante y la del notch comparten los mismos archivos. Podés seleccionar uno con clic, sumar o quitar elementos con ⌘-clic, o arrastrar desde un espacio vacío para seleccionar con un rectángulo. **Seleccionar todos** marca todos los elementos; si seleccionás más de uno aparece el control para arrastrarlos juntos. **Quitar** y **Vaciar bandeja** piden confirmación. La ventana flotante se cierra al quedar vacía; arrastrar un archivo desde la bandeja hacia otra app conserva la copia guardada.
