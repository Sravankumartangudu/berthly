import AppKit
import Combine
import SwiftUI

/// The moments a trip alerts you. Keys are saved in `Trip.fired`, so never rename one.
enum Stage: String, CaseIterable {
    case evening = "eve", thirty = "30", ten = "10", two = "2", open = "0", chart = "chart"

    func time(for trip: Trip) -> Date? {
        let o = trip.opens
        switch self {
        case .evening:
            // 20:00 IST the evening before opening day.
            let day = Rules.calendar.date(byAdding: .day, value: -1, to: Rules.day(o))!
            return Rules.at(20, on: day)
        case .thirty: return o.addingTimeInterval(-30 * 60)
        case .ten: return o.addingTimeInterval(-10 * 60)
        case .two: return o.addingTimeInterval(-2 * 60)
        case .open: return o
        case .chart: return trip.chart?.addingTimeInterval(-15 * 60)
        }
    }

    /// How late an alert may still appear (for example after the Mac wakes from sleep).
    var grace: TimeInterval {
        switch self {
        case .evening: return 3 * 3600
        case .thirty: return 20 * 60
        case .ten: return 8 * 60
        case .two: return 2 * 60
        case .open: return 10 * 60
        case .chart: return 2 * 3600
        }
    }

    var headline: String {
        switch self {
        case .evening: return "Get ready for tomorrow"
        case .thirty: return "Opens in 30 minutes"
        case .ten: return "Sign in to IRCTC now"
        case .two: return "Two minutes to go"
        case .open: return "Booking is open — go!"
        case .chart: return "Chart is due soon"
        }
    }

    var tip: String {
        switch self {
        case .evening: return "Tick off the checklist tonight so tomorrow is just clicks."
        case .thirty: return "Go through the checklist. Close heavy apps and tabs, and keep your phone close."
        case .ten: return "Sign in now, then search your train and stations so the list is ready. Don't sign in twice in two tabs."
        case .two: return "Have the train list open with your class and quota picked. Click Book Now the moment the clock hits zero."
        case .open: return "Pick passengers from the Master List, approve the Aadhaar OTP, and pay fast. Use your backup if this one fills up."
        case .chart: return "Check your PNR once the chart is out to see if your waitlist ticket got confirmed."
        }
    }

    /// Stages that come before opening and count down to it.
    var countsDown: Bool { [.thirty, .ten, .two, .open].contains(self) }
}

final class AlertModel: ObservableObject {
    @Published var trip: Trip?
    @Published var stage: Stage = .thirty
    @Published var now = Date()
    @Published var compact = false
    var onOpen: () -> Void = {}
    var onPNR: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onShowTrip: () -> Void = {}
}

/// The floating card. It stays above other windows but never takes focus from the browser.
final class AlertPanel {
    let model = AlertModel()
    private var panel: NSPanel?
    private var compactWatch: AnyCancellable?

    var isShowing: Bool { panel?.isVisible == true }

    func show(_ trip: Trip, _ stage: Stage) {
        model.trip = trip
        model.stage = stage
        model.compact = false
        if panel == nil { build() }
        place()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel?.animator().alphaValue = 1
        }
    }

    func close() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func build() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        // The card is always dark, like a station departure board, whatever the app appearance.
        p.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: AlertView(model: model).environmentObject(Store.shared))
        p.contentView = host
        panel = p
        // Shrinking to the pill (or growing back) keeps the top-right corner where it was.
        compactWatch = model.$compact.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.fit() }
        }
    }

    private func fit() {
        guard let panel, let host = panel.contentView else { return }
        let size = host.fittingSize
        let old = panel.frame
        panel.setFrame(NSRect(x: old.maxX - size.width, y: old.maxY - size.height, width: size.width, height: size.height),
                       display: true, animate: true)
    }

    /// Top-right of the main screen, under the menu bar.
    private func place() {
        guard let panel, let screen = NSScreen.main else { return }
        panel.layoutIfNeeded()
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.maxX - size.width - 16, y: f.maxY - size.height - 10,
                              width: size.width, height: size.height), display: true)
    }
}

struct AlertView: View {
    @ObservedObject var model: AlertModel
    @EnvironmentObject var store: Store

    private var trip: Trip? { model.trip.flatMap { t in store.trips.first { $0.id == t.id } } ?? model.trip }

    var body: some View {
        Group {
            if let trip {
                if model.compact { pill(trip) } else { card(trip) }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.compact)
    }

    private var target: Date? {
        guard let trip else { return nil }
        return model.stage == .chart ? trip.chart : trip.opens
    }

    private var isOpen: Bool { (target.map { model.now >= $0 } ?? false) && model.stage != .chart }

    private var accent: Color { isOpen ? Theme.go : Theme.amber }

    private func clock(_ trip: Trip) -> String {
        guard let target else { return "" }
        let s = Int(target.timeIntervalSince(model.now).rounded(.up))
        if s <= 0 { return model.stage == .chart ? "due" : "OPEN" }
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func pill(_ trip: Trip) -> some View {
        HStack(spacing: 10) {
            Text("🚆")
            Text(clock(trip))
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .contentTransition(.numericText(countsDown: true))
            Text(trip.travelClass.rawValue).font(.caption.bold()).foregroundStyle(.secondary)
            Button { model.compact = false } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.board, in: Capsule())
        .overlay(Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 1))
        .padding(8)
    }

    private func card(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        chip(trip.quota.rawValue.uppercased(), accent)
                        chip(trip.travelClass.rawValue, .white.opacity(0.6))
                    }
                    Text(trip.route).font(.system(size: 20, weight: .bold))
                    if !trip.trainNumber.isEmpty || !trip.trainName.isEmpty {
                        Text("\(trip.trainNumber) \(trip.trainName)").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { model.compact = true } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Shrink to a small countdown")
                Button { model.onDismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Dismiss")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isOpen ? Stage.open.headline : model.stage.headline)
                    .font(.headline).foregroundStyle(accent)
                if model.stage.countsDown || model.stage == .chart {
                    Text(clock(trip))
                        .font(.system(size: 54, weight: .heavy, design: .monospaced))
                        .foregroundStyle(accent)
                        .contentTransition(.numericText(countsDown: true))
                        .shadow(color: accent.opacity(0.45), radius: 14)
                }
                Text(subtitle(trip)).font(.caption).foregroundStyle(.secondary)
            }

            Text(isOpen ? Stage.open.tip : model.stage.tip)
                .font(.callout).fixedSize(horizontal: false, vertical: true)

            if model.stage != .chart {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(CheckItem.all) { item in
                        let on = trip.checked.contains(item.id)
                        Button {
                            let flip: (inout Trip) -> Void = { t in
                                if on { t.checked.remove(item.id) } else { t.checked.insert(item.id) }
                            }
                            // Preview trips aren't saved, so they're ticked on the card only.
                            if store.trips.contains(where: { $0.id == trip.id }) { store.update(trip.id, flip) }
                            else if model.trip != nil { flip(&model.trip!) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? Theme.go : .secondary)
                                Text(item.text).strikethrough(on, color: .secondary)
                                    .foregroundStyle(on ? .secondary : .primary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help(item.hint)
                    }
                }
                .font(.callout)
            }

            HStack {
                if model.stage == .chart {
                    Button("Check PNR") { model.onPNR() }.buttonStyle(Primary(color: accent))
                } else {
                    Button("Open IRCTC") { model.onOpen() }.buttonStyle(Primary(color: accent))
                }
                Button("Copy details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(trip.details, forType: .string)
                }
                .buttonStyle(Secondary())
                Spacer()
                Button("Trip…") { model.onShowTrip() }.buttonStyle(Secondary())
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.board, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(accent.opacity(0.45), lineWidth: 1))
        .padding(10)
    }

    private func subtitle(_ trip: Trip) -> String {
        let f = DateFormatter.ist("EEE d MMM, HH:mm:ss")
        if model.stage == .chart, let c = trip.chart { return "Chart around \(f.string(from: c)) IST" }
        return "\(trip.quota.rawValue) opens \(f.string(from: trip.opens)) IST · \(Clock.shared.summary)"
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).kerning(0.6)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

enum Theme {
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.2)
    static let go = Color(red: 0.25, green: 0.88, blue: 0.5)
    /// Departure-board navy.
    static let board = LinearGradient(colors: [Color(red: 0.09, green: 0.11, blue: 0.2), Color(red: 0.04, green: 0.05, blue: 0.1)],
                                      startPoint: .top, endPoint: .bottom)
}

struct Primary: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.callout.bold())
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(.black)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}

struct Secondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0.1), in: Capsule())
    }
}
