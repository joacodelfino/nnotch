import SwiftUI

struct CalendarAlertView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var calendar: CalendarManager
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "bell.badge.fill").foregroundStyle(prefs.accentColor)
                Text(vm.calendarAlerts.count == 1 ? "Tu evento empieza ahora" : "Tus eventos empiezan ahora")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button { vm.dismissCalendarAlerts() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 19)).foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain).accessibilityLabel("Cerrar aviso")
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(vm.calendarAlerts) { event in CalendarEventRow(event: event) }
                }
            }
            HStack {
                Text("Avisos de Calendario · se cierra en 20 s")
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button("Ver calendario") {
                    calendar.showToday()
                    vm.dismissCalendarAlerts(keepOpen: true)
                    vm.expand(tab: .calendar)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(8)
        .islandCard()
    }
}
