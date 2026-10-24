import AppKit
import SwiftUI

final class TripsWindow {
    private var window: NSWindow?
    let selection = Selection()

    final class Selection: ObservableObject {
        @Published var page: Page?
        @Published var now = Date()
    }

    /// What the window shows on the right: a trip or one of the tools.
    enum Page: Hashable {
        case trip(UUID)
        case tool(Tool)
    }

    func show(_ id: UUID? = nil) {
        // Start on the trip that opens soonest rather than an empty page.
        let store = Store.shared
        if let id {
            selection.page = .trip(id)
        } else if case .trip(let shown)? = selection.page, store.trips.contains(where: { $0.id == shown }) {
            // Keep the trip that's already showing.
        } else if case .tool? = selection.page {
            // Keep the tool that's already showing.
        } else {
            selection.page = (store.upcoming(now: selection.now).first ?? store.trips.first).map { .trip($0.id) }
        }
        present()
    }

    func show(_ tool: Tool) {
        selection.page = .tool(tool)
        present()
    }

    private func present() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = AppInfo.name
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 760, height: 520)
            let host = NSHostingController(rootView: TripsView(selection: selection).environmentObject(Store.shared))
            // Otherwise the form's full height becomes the window's minimum size.
            host.sizingOptions = []
            w.contentViewController = host
            w.setContentSize(NSSize(width: 900, height: 640))
            w.center()
            w.setFrameAutosaveName("TripsWindow")
            window = w
        }
        // Cooperative activation: never grabs the keyboard while you're typing in another app, where a
        // stray Space or Return would otherwise press "Add a trip".
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func newTrip() {
        let t = Trip()
        Store.shared.trips.append(t)
        show(t.id)
    }
}

struct TripsView: View {
    @ObservedObject var selection: TripsWindow.Selection
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationSplitView {
            List(selection: $selection.page) {
                Section("Trips") {
                    ForEach(store.trips.sorted { $0.opens < $1.opens }) { t in
                        TripRow(trip: t, now: selection.now).tag(TripsWindow.Page.trip(t.id))
                    }
                    if store.trips.isEmpty {
                        Text("No trips yet").foregroundStyle(.secondary).selectionDisabled()
                    }
                }
                Section("Tools") {
                    ForEach(Tool.allCases) { tool in
                        Label(tool.title, systemImage: tool.symbol).tag(TripsWindow.Page.tool(tool))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { add(Trip()) } label: { Label("New trip", systemImage: "plus") }
                .buttonStyle(.borderless).padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 270)
        } detail: {
            switch selection.page {
            case .trip(let id)? where store.trips.contains(where: { $0.id == id }):
                TripDetail(id: id, now: selection.now) { selection.page = .tool($0) }.id(id)
            case .tool(let tool)?:
                ToolPage(tool: tool, now: selection.now, add: add).id(tool)
            default:
                Welcome(now: selection.now) { add(Trip()) }
            }
        }
        .environment(\.timeZone, Rules.ist)
    }

    /// Saves a new trip (blank, or started from a tool) and shows it.
    private func add(_ t: Trip) {
        store.trips.append(t)
        selection.page = .trip(t.id)
    }
}

struct TripRow: View {
    let trip: Trip
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trip.title).font(.body.weight(.medium)).lineLimit(1)
            HStack(spacing: 6) {
                if trip.booked {
                    Text("Booked · PNR \(trip.pnr)").foregroundStyle(.green)
                } else if trip.opens <= now {
                    Text("\(trip.quota.rawValue) open").foregroundStyle(.green)
                } else {
                    Text("\(trip.quota.rawValue) in \(countdown(to: trip.opens, from: now))")
                }
                Text("· \(DateFormatter.ist("d MMM").string(from: trip.journeyDate))").foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

/// Live IST clock with seconds, corrected by the internet time sync.
struct ISTClock: View {
    let now: Date
    var body: some View {
        HStack(spacing: 8) {
            Text(DateFormatter.ist("HH:mm:ss").string(from: now))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
            Text("IST").font(.caption.bold()).foregroundStyle(.secondary)
            Text(Clock.shared.summary).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct Welcome: View {
    let now: Date
    let add: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("🚆").font(.system(size: 56))
                Text("Be ready the second booking opens").font(.title2.bold())
                Text("Add a trip and \(AppInfo.name) works out when Tatkal or general booking opens, counts down to the second, walks you through a checklist and opens IRCTC for you. You book and pay on IRCTC yourself.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
                Button("Add a trip", action: add).buttonStyle(.borderedProminent).controlSize(.large)
                ISTClock(now: now).padding(.top, 4)
                RulesCard().frame(maxWidth: 520).padding(.top, 4)
            }
            .padding(.horizontal, 30).padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

struct RulesCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOW BOOKING OPENS").font(.caption.bold()).foregroundStyle(.secondary)
            rule("General", "08:00 IST, \(Rules.advanceDays) days before the train starts. The first \(Rules.generalAadhaarMinutes) minutes are for Aadhaar-verified accounts.")
            rule("Tatkal (AC)", "10:00 IST the day before the train leaves its first station: 2A, 3A, 3E, CC, EC.")
            rule("Tatkal (non-AC)", "11:00 IST the same day: SL and 2S.")
            rule("Premium Tatkal", "Same times as Tatkal, with fares that rise as seats sell.")
            rule("Aadhaar", "Online Tatkal needs an Aadhaar-verified IRCTC account and an Aadhaar OTP while booking. Agents can't book in the first \(Rules.agentBlockMinutes) minutes.")
            rule("Chart", "20:00 the evening before for trains leaving 05:00–14:00; about 10 hours before departure for the rest. The final chart comes 30 minutes before departure.")
            Text("Rules checked \(Rules.checked). Indian Railways changes them now and then, so check irctc.co.in if something looks off. \(AppInfo.name) is not affiliated with IRCTC or Indian Railways.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func rule(_ name: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).font(.callout.bold()).frame(width: 118, alignment: .leading)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TripDetail: View {
    let id: UUID
    let now: Date
    let openTool: (Tool) -> Void
    @EnvironmentObject var store: Store
    @State private var advice: String?
    @State private var thinking = false
    @State private var confirmDelete = false

    private var trip: Binding<Trip> {
        Binding(get: { store.trips.first { $0.id == id } ?? Trip() },
                set: { new in store.update(id) { $0 = new } })
    }

    var body: some View {
        let t = trip.wrappedValue
        Form {
            Section { header(t) }

            Section("Journey") {
                TextField("From", text: trip.from, prompt: Text("Station code or name, e.g. NDLS"))
                StationSuggestions(text: trip.from)
                TextField("To", text: trip.to, prompt: Text("e.g. MMCT"))
                StationSuggestions(text: trip.to)
                TextField("Train number", text: trip.trainNumber, prompt: Text("e.g. 12952"))
                TextField("Train name", text: trip.trainName, prompt: Text("Optional"))
                DatePicker("Boarding date", selection: Binding(get: { t.journeyDate },
                                                               set: { trip.journeyDate.wrappedValue = Rules.day($0) }),
                           displayedComponents: .date)
                Picker("Train leaves its first station", selection: trip.startDayOffset) {
                    Text("The same day").tag(0)
                    Text("1 day earlier").tag(-1)
                    Text("2 days earlier").tag(-2)
                    Text("3 days earlier").tag(-3)
                }
                .help("Booking opens by the date the train starts its run. If you board mid-route the day after it starts, pick “1 day earlier”.")
                Toggle("I know the departure time", isOn: Binding(
                    get: { t.departureMinutes != nil },
                    set: { trip.departureMinutes.wrappedValue = $0 ? (t.departureMinutes ?? 20 * 60) : nil }))
                if t.departureMinutes != nil {
                    DatePicker("Departs (IST)", selection: Binding(
                        get: { t.departure ?? t.journeyDate },
                        set: { d in
                            let c = Rules.calendar.dateComponents([.hour, .minute], from: d)
                            trip.departureMinutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                        }), displayedComponents: .hourAndMinute)
                }
            }

            Section("Ticket") {
                Picker("Quota", selection: trip.quota) {
                    ForEach(Quota.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Class", selection: trip.travelClass) {
                    ForEach(TravelClass.allCases) { Text($0.label).tag($0) }
                }
                quotaNote(t)
                Stepper("Passengers: \(t.passengers)", value: trip.passengers,
                        in: 1...(t.quota == .general ? Rules.generalPassengers : Rules.tatkalPassengers))
                    .help("IRCTC allows up to \(Rules.tatkalPassengers) passengers on a Tatkal ticket and \(Rules.generalPassengers) on a general one.")
                TextField("Backup (another train, class or station)", text: trip.backup)
                TextField("Notes", text: trip.notes, prompt: Text("No passwords, OTPs or Aadhaar numbers"), axis: .vertical).lineLimit(2...5)
            }

            Section("Checklist") {
                ForEach(CheckItem.all) { item in
                    Toggle(isOn: Binding(
                        get: { t.checked.contains(item.id) },
                        set: { on in store.update(id) { if on { $0.checked.insert(item.id) } else { $0.checked.remove(item.id) } } })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.text)
                            Text(item.hint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            Section("After booking") {
                TextField("PNR (10 digits)", text: trip.pnr)
                TextField("Status, e.g. CNF B2 34, RAC 5, WL 12", text: trip.pnrStatus)
                TextField("Fare paid (₹, all passengers)", value: trip.fare, format: .number,
                          prompt: Text("Optional, for the refund estimate"))
                if t.booked { refundLine(t) }
                if let chart = t.chart {
                    LabeledContent("Chart expected", value: DateFormatter.ist("EEE d MMM, HH:mm").string(from: chart) + " IST")
                } else {
                    Text("Add the departure time above to get an alert before the chart comes out.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Check PNR on Indian Railways") { openPNR(t) }
                        .help("Copies the PNR and opens the official PNR enquiry page. Paste it there.")
                    Button("Train running status (NTES)") { NSWorkspace.shared.open(Rules.ntesURL) }
                }
            }

            Section("✨ Trip coach") {
                if let advice {
                    Text(advice).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(thinking ? "Thinking…" : (advice == nil ? "Plan this trip" : "Ask again")) { ask(t) }
                        .disabled(thinking)
                    if thinking { ProgressView().controlSize(.small) }
                    Spacer()
                    Text("Sends the trip details, never the PNR, to Claude.").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button("Copy details") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(t.details, forType: .string)
                    }
                    Button("Add to Calendar") { CalendarExport.open(t, now: now) }
                        .help("Adds the booking opening, the journey and the chart time to Calendar, with reminders. The PNR isn't included.")
                    Spacer()
                    Button("Delete trip", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete this trip?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.trips.removeAll { $0.id == id } }
        }
    }

    private func header(_ t: Trip) -> some View {
        let open = t.opens <= now
        let general = Rules.generalOpens(trainStarts: t.trainStarts)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(t.route).font(.title.bold())
                Spacer()
                ISTClock(now: now)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(open ? "\(t.quota.rawValue) is open" : countdown(to: t.opens, from: now))
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .foregroundStyle(open ? Theme.go : Theme.amber)
                    .contentTransition(.numericText(countsDown: true))
                if !open { Text("until \(t.quota.rawValue) opens").foregroundStyle(.secondary) }
            }
            Text("\(t.quota.rawValue) opens \(DateFormatter.ist("EEEE d MMMM, HH:mm").string(from: t.opens)) IST")
                .font(.callout)
            if t.quota != .general {
                Text(general > now
                     ? "General booking opens \(DateFormatter.ist("EEE d MMM, HH:mm").string(from: general)) IST, which is often easier than Tatkal."
                     : "General booking opened \(DateFormatter.ist("EEE d MMM").string(from: general)). Check it for seats before waiting for Tatkal.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Open IRCTC") { NSWorkspace.shared.open(Rules.bookingURL) }.buttonStyle(.borderedProminent)
                Text("\(t.checked.count) of \(CheckItem.all.count) ready").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func quotaNote(_ t: Trip) -> some View {
        if t.quota != .general && !t.travelClass.hasTatkal {
            Label("There's no \(t.quota.rawValue) in 1A. Pick General, or another class.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange).font(.callout)
        } else if t.quota == .tatkal, let ch = Refunds.tatkalCharge(t.travelClass) {
            Text("Tatkal charge: \(Int(ch.percent * 100))% of the basic fare, ₹\(Int(ch.min))–₹\(Int(ch.max)) per passenger. A confirmed Tatkal ticket isn't refunded if you cancel.")
                .font(.caption).foregroundStyle(.secondary)
        } else if t.quota == .premium {
            Text("Premium Tatkal fares rise as seats sell, and a confirmed ticket isn't refunded if you cancel.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// What cancelling right now would give back, from the fare and the status typed in.
    @ViewBuilder private func refundLine(_ t: Trip) -> some View {
        let status = TicketStatus.parse(t.pnrStatus)
        let dep = t.departure ?? Rules.at(0, on: t.journeyDate)
        let q = Refunds.quote(fare: t.fare ?? 0, passengers: t.passengers, travelClass: t.travelClass, quota: t.quota,
                              status: status ?? .confirmed, departure: dep, at: now)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.fare == nil ? "If you cancel now" : "If you cancel now: about ₹\(Int(q.refund.rounded())) back")
                    .font(.callout.weight(.medium))
                Text(q.rule + (status == nil ? " (Read as confirmed; type the status above to change that.)" : "")
                     + (t.departure == nil ? " Add the departure time for an exact slab." : ""))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Refund calculator") { openTool(.refund) }
        }
    }

    private func openPNR(_ t: Trip) {
        let pnr = t.pnr.filter(\.isNumber)
        if !pnr.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pnr, forType: .string)
        }
        NSWorkspace.shared.open(Rules.pnrURL)
    }

    private func ask(_ t: Trip) {
        thinking = true
        Coach.ask(t, now: Clock.shared.now) { result in
            thinking = false
            switch result {
            case .success(let text): advice = text
            case .failure(let error): advice = "⚠️ " + error.localizedDescription
            }
        }
    }
}
