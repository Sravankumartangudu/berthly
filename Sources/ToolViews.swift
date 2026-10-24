import AppKit
import SwiftUI

/// One tool from the sidebar. `add` saves a new trip and shows it.
struct ToolPage: View {
    let tool: Tool
    let now: Date
    let add: (Trip) -> Void

    var body: some View {
        switch tool {
        case .festivals: FestivalPlanner(now: now, add: add)
        case .refund: RefundCalculator(now: now)
        case .tatkal: TatkalCharges()
        case .stations: StationCodes()
        case .journey: JourneyKit()
        case .tips: GoodToKnow()
        }
    }
}

private struct PageHeader: View {
    let tool: Tool
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(tool.title, systemImage: tool.symbol).font(.title2.bold())
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private func rupees(_ v: Double) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_IN")
    f.numberStyle = .currency
    f.currencySymbol = "₹"
    f.maximumFractionDigits = v.rounded() == v ? 0 : 2
    return f.string(from: NSNumber(value: v)) ?? "₹\(v)"
}

private func copy(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

/// Under a From or To field: the station's name once a code is typed, or a few matches to click.
struct StationSuggestions: View {
    @Binding var text: String

    var body: some View {
        let q = text.trimmingCharacters(in: .whitespaces)
        if let exact = Stations.named(q) {
            Text(exact.name).font(.caption).foregroundStyle(.secondary)
        } else if let moved = Stations.replacement(for: q) {
            HStack(spacing: 6) {
                Text("\(q.uppercased()) is now \(moved.code), \(moved.name).").font(.caption).foregroundStyle(.orange)
                Button("Use \(moved.code)") { text = moved.code }.buttonStyle(.bordered).controlSize(.small)
            }
        } else if q.count >= 2 {
            let matches = Stations.search(q, limit: 4)
            if !matches.isEmpty {
                HStack(spacing: 6) {
                    ForEach(matches) { s in
                        Button("\(s.code) · \(s.name)") { text = s.code }
                            .buttonStyle(.bordered).controlSize(.small).lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Festival planner

struct FestivalPlanner: View {
    let now: Date
    let add: (Trip) -> Void
    @State private var custom = Rules.calendar.date(byAdding: .day, value: Rules.advanceDays + 15, to: Rules.day(Date()))!
    /// Days before the festival you plan to travel.
    @State private var lead = 1

    var body: some View {
        Form {
            Section {
                PageHeader(tool: .festivals, text: "Festival trains fill up on the first morning general booking opens, \(Rules.advanceDays) days ahead. See when that is for the days you want, and turn one into a trip so \(AppInfo.name) alerts you.")
            }
            Section("Any date") {
                DatePicker("Travel date", selection: Binding(get: { custom }, set: { custom = Rules.day($0) }), displayedComponents: .date)
                opening(for: custom)
                Button("Plan a trip for this date") { add(plan(custom)) }
            }
            Section {
                Picker("I'll travel", selection: $lead) {
                    Text("2 days before").tag(2)
                    Text("The day before").tag(1)
                    Text("On the day").tag(0)
                }
                .pickerStyle(.segmented)
                ForEach(Festivals.upcoming(now: now)) { f in
                    let travel = Rules.calendar.date(byAdding: .day, value: -lead, to: f.date)!
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(f.name).font(.body.weight(.semibold))
                                Text(DateFormatter.ist("EEE d MMM yyyy").string(from: f.date)).foregroundStyle(.secondary)
                            }
                            opening(for: travel, travelLabel: true)
                            if !f.note.isEmpty { Text(f.note).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Plan") { add(plan(travel)) }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Festivals and holidays")
            } footer: {
                Text("Dates checked \(Festivals.checked). Some depend on the moon and may shift by a day; Eid dates are expected dates.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func opening(for day: Date, travelLabel: Bool = false) -> some View {
        let general = Rules.generalOpens(trainStarts: day)
        let tatkal = Rules.tatkalOpens(trainStarts: day, travelClass: .ac3)
        let f = DateFormatter.ist("EEE d MMM")
        VStack(alignment: .leading, spacing: 2) {
            if travelLabel { Text("Travel \(f.string(from: day))").font(.caption.weight(.medium)) }
            if day < Rules.day(now) {
                Text("This date has passed.").font(.callout).foregroundStyle(.secondary)
            } else if general > now {
                Text("General booking opens **\(f.string(from: general)), 08:00 IST** · in \(countdown(to: general, from: now))")
                    .font(.callout)
            } else {
                Text("General booking is open now.").font(.callout).foregroundStyle(Theme.go)
            }
            if day >= Rules.day(now) {
                Text("Tatkal: \(f.string(from: tatkal)) at 10:00 (AC) or 11:00 (SL, 2S)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// A general-quota trip for the date, or Tatkal if general booking has already opened.
    private func plan(_ day: Date) -> Trip {
        var t = Trip()
        t.journeyDate = Rules.day(day)
        t.quota = Rules.generalOpens(trainStarts: day) > now ? .general : .tatkal
        return t
    }
}

// MARK: - Refund calculator

struct RefundCalculator: View {
    let now: Date
    @EnvironmentObject var store: Store
    @State private var travelClass = TravelClass.ac3
    @State private var quota = Quota.general
    @State private var status = TicketStatus.confirmed
    @State private var fare: Double?
    @State private var passengers = 1
    @State private var departure = Rules.calendar.date(byAdding: .day, value: 3, to: Rules.at(20, on: Date()))!
    @State private var cancelAt = Date()
    @State private var usingNow = true

    var body: some View {
        let when = usingNow ? now : cancelAt
        let q = Refunds.quote(fare: fare ?? 0, passengers: passengers, travelClass: travelClass, quota: quota,
                              status: status, departure: departure, at: when)
        Form {
            Section {
                PageHeader(tool: .refund, text: "What you'd get back if you cancel, under the Indian Railways refund rules. IRCTC works out the exact amount when you cancel.")
            }
            let booked = store.trips.filter(\.booked)
            if !booked.isEmpty {
                Section {
                    Menu("Fill in from a booked trip") {
                        ForEach(booked) { t in Button(t.title) { fill(t) } }
                    }
                    .fixedSize()
                }
            }
            Section("Ticket") {
                Picker("Class", selection: $travelClass) {
                    ForEach(TravelClass.allCases) { Text($0.label).tag($0) }
                }
                Picker("Quota", selection: $quota) {
                    ForEach(Quota.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Status", selection: $status) {
                    ForEach(TicketStatus.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Fare paid (₹, all passengers)", value: $fare, format: .number, prompt: Text("From the ticket, without the IRCTC fee"))
                Stepper("Passengers: \(passengers)", value: $passengers, in: 1...6)
                DatePicker("Train departs (IST)", selection: $departure)
                Toggle("Cancelling now", isOn: $usingNow)
                if !usingNow { DatePicker("Cancelling at (IST)", selection: $cancelAt) }
            }
            Section("Estimate") {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(fare == nil ? "—" : rupees(q.refund))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(q.refund > 0 ? Theme.go : .secondary)
                    Text(fare == nil ? "Enter the fare to see the amount" : "back · \(rupees(q.deduction)) deducted")
                        .foregroundStyle(.secondary)
                }
                Text(q.rule).fixedSize(horizontal: false, vertical: true)
                if let tdr = q.tdrHint {
                    Text(tdr).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text(Refunds.footnote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Cancel on IRCTC") { NSWorkspace.shared.open(Rules.bookingURL) }
                    .help("My Account → My Transactions → Booked Ticket History, then pick the ticket and the passengers.")
            }
            Section("The rules") {
                ForEach(Refunds.rulesTable, id: \.0) { row in
                    LabeledContent(row.0) { Text(row.1).multilineTextAlignment(.trailing) }
                }
                Text("Minimum charge per passenger: " + Refunds.flatTable).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func fill(_ t: Trip) {
        travelClass = t.travelClass
        quota = t.quota
        status = TicketStatus.parse(t.pnrStatus) ?? .confirmed
        fare = t.fare
        passengers = t.passengers
        if let d = t.departure { departure = d } else { departure = Rules.at(12, on: t.journeyDate) }
    }
}

// MARK: - Tatkal charges

struct TatkalCharges: View {
    @State private var travelClass = TravelClass.ac3
    @State private var basic: Double?
    @State private var passengers = 1

    var body: some View {
        Form {
            Section {
                PageHeader(tool: .tatkal, text: "Tatkal adds a charge to the basic fare of each passenger, with a minimum and a maximum by class. Premium Tatkal has no fixed charge: its fare rises as seats sell.")
            }
            Section("Charge per passenger") {
                ForEach(TravelClass.allCases.filter(\.hasTatkal)) { c in
                    if let ch = Refunds.tatkalCharge(c) {
                        LabeledContent(c.label, value: "\(Int(ch.percent * 100))% of basic fare · \(rupees(ch.min))–\(rupees(ch.max))")
                    }
                }
                LabeledContent(TravelClass.ac1.label, value: "No Tatkal quota")
                Text("From IRCTC's Tatkal FAQ, checked \(Rules.checked). 3E isn't listed separately, so it shows the 3A figures; IRCTC's fare breakup has the exact charge.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Work it out") {
                Picker("Class", selection: $travelClass) {
                    ForEach(TravelClass.allCases.filter(\.hasTatkal)) { Text($0.label).tag($0) }
                }
                TextField("Basic fare per passenger (₹)", value: $basic, format: .number, prompt: Text("IRCTC shows it in the fare breakup"))
                Stepper("Passengers: \(passengers)", value: $passengers, in: 1...Rules.tatkalPassengers)
                if let basic, let per = Refunds.tatkalCharge(basicFare: basic, travelClass) {
                    LabeledContent("Tatkal charge", value: "\(rupees(per)) per passenger · \(rupees(per * Double(passengers))) in all")
                    Text("Plus reservation, superfast and GST charges as on any ticket.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Station codes

struct StationCodes: View {
    @State private var query = ""

    var body: some View {
        let results = Stations.search(query, limit: 40)
        Form {
            Section {
                PageHeader(tool: .stations, text: "Find a station's code by name or city. IRCTC's search box takes either; the code is quicker to type at opening time. \(Stations.all.count.formatted()) stations, offline.")
            }
            Section {
                TextField("Search", text: $query, prompt: Text("City, station name or code, e.g. Hyderabad or SC"))
                if !query.isEmpty && results.isEmpty {
                    Text("No station matches “\(query)”.").foregroundStyle(.secondary)
                }
                ForEach(results) { s in
                    HStack {
                        Text(s.code).font(.system(.body, design: .monospaced).weight(.bold)).frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name)
                            if !s.formerly.isEmpty { Text("Formerly \(s.formerly)").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Copy") { copy(s.code) }.buttonStyle(.borderless)
                    }
                }
            }
            Section("Renamed stations") {
                ForEach(Stations.renamed, id: \.new) { r in
                    LabeledContent(r.old, value: r.new)
                }
            }
            Section {
                Text(Stations.credit).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - On the journey

struct JourneyKit: View {
    var body: some View {
        Form {
            Section {
                PageHeader(tool: .journey, text: "Official help for the day you travel. Each button opens the official site in your browser.")
            }
            Section("Help and services") {
                ForEach(RailLinks.all, id: \.title) { link in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title).font(.body.weight(.medium))
                            Text(link.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Open") { NSWorkspace.shared.open(link.url) }
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("139 · Rail helpline").font(.body.weight(.medium))
                        Text(RailLinks.helpline).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Copy") { copy("139") }
                }
            }
            Section {
                ForEach(TDR.cases, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0).font(.body.weight(.medium))
                        Text(row.1).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 1)
                }
                Text(TDR.howTo).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Refund when something goes wrong (TDR)")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Good to know

struct GoodToKnow: View {
    var body: some View {
        Form {
            Section {
                PageHeader(tool: .tips, text: "Rules that help you get a seat or travel easier. Checked \(Rules.checked).")
            }
            ForEach(Tips.all, id: \.title) { tip in
                Section(tip.title) {
                    Text(tip.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}
