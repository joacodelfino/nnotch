import SwiftUI
import Combine

/// Content flanking the physical notch while collapsed.
/// Both zones are user-configurable from Settings.
struct CollapsedView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var music: MusicManager
    @EnvironmentObject private var timers: TimerCenter
    @EnvironmentObject private var stats: SystemStats
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        HStack(spacing: 0) {
            indicator(prefs.collapsedLeft)
                .frame(width: 74)
            Spacer(minLength: 8)
            indicator(prefs.collapsedRight)
                .frame(width: 74)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func indicator(_ content: Preferences.CollapsedContent) -> some View {
        Group {
            switch content {
            case .auto:
                if let badge = timers.collapsedBadge {
                    Label(badge, systemImage: "timer")
                } else if music.nowPlaying?.isPlaying == true {
                    musicMini
                } else {
                    batteryMini
                }
            case .clock:
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                }
            case .date:
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.day().month(.abbreviated))
                }
            case .weekday:
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.weekday(.abbreviated))
                }
            case .battery: batteryMini
            case .music: musicMini
            case .network: networkMini
            case .cpu: Text("CPU \(Int(stats.cpuUsage * 100))%")
            case .memory: Text("RAM \(Int(stats.memoryUsage * 100))%")
            case .timer:
                Label(timers.collapsedBadge ?? "—", systemImage: "timer")
            case .hidden: Color.clear
            }
        }
        .font(.caption.monospacedDigit().weight(.medium))
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .help(content.title)
    }

    private var musicMini: some View {
        HStack(spacing: 5) {
            if let artwork = music.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 17, height: 17)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            if prefs.showEqualizer {
                EqualizerBars(playing: music.nowPlaying?.isPlaying == true, tint: prefs.accentColor)
            }
        }
    }

    @ViewBuilder
    private var batteryMini: some View {
        if let level = stats.batteryLevel {
            HStack(spacing: 3) {
                if stats.batteryCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                }
                Text("%\(level)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Image(systemName: batterySymbol(level))
                    .font(.system(size: 11))
                    .foregroundStyle(level <= 20 ? .red : .white.opacity(0.85))
            }
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var networkMini: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("↓ " + NetworkMonitor.format(network.downloadBps))
            Text("↑ " + NetworkMonitor.format(network.uploadBps))
        }
        .font(.system(size: 8).monospacedDigit())
        .foregroundStyle(.white.opacity(0.75))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

/// Tiny animated bars synced to playback state.
struct EqualizerBars: View {
    var playing: Bool
    var tint: Color = .green
    @State private var heights: [CGFloat] = [7, 12, 9]

    private let timer = Timer.publish(every: 0.28, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: 2.5, height: heights[index])
            }
        }
        .frame(height: 14, alignment: .bottom)
        .onReceive(timer) { _ in
            guard playing else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                heights = heights.map { _ in CGFloat.random(in: 4...14) }
            }
        }
    }
}
