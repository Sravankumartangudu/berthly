import AppKit
import Foundation

enum AppInfo {
    static let name = "Berthly"
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
}

/// One thing to have ready before booking opens. `id` is what's saved, so never rename one.
struct CheckItem: Identifiable {
    let id: String
    let text: String
    let hint: String

    static let all: [CheckItem] = [
        CheckItem(id: "aadhaar", text: "IRCTC account is Aadhaar-verified",
                  hint: "Online Tatkal needs it, plus an Aadhaar OTP while you book. My Account → Authenticate User."),
        CheckItem(id: "master", text: "Passengers saved in IRCTC's Master List",
                  hint: "My Profile → Master List. Then you pick passengers instead of typing names, ages and IDs."),
        CheckItem(id: "trip", text: "Train, date, class and stations written down",
                  hint: "The card on this trip has them all. Use “Copy details” for a note."),
        CheckItem(id: "payment", text: "Payment ready",
                  hint: "UPI app unlocked and signed in, or the IRCTC eWallet topped up. Cards with a slow OTP lose time."),
        CheckItem(id: "phone", text: "Phone at hand for OTPs",
                  hint: "Aadhaar OTP and payment OTP both arrive by SMS."),
        CheckItem(id: "backup", text: "Backup picked",
                  hint: "A second train or class to try if the first one fills up."),
        CheckItem(id: "login", text: "Signed in to IRCTC 5–10 minutes early",
                  hint: "Signing in at the opening second is the slowest part. The 10-minute alert opens IRCTC for you."),
    ]
}

struct Trip: Codable, Identifiable, Equatable {
    var id = UUID()
    var from = ""
    var to = ""
    var trainNumber = ""
    var trainName = ""
    /// The day you board, as an IST calendar day.
    var journeyDate = Rules.calendar.date(byAdding: .day, value: 1, to: Rules.day(Date()))!
    /// 0 when the train leaves its first station on your boarding day; -1 when it left the day before, and so on.
    /// Tatkal opens by the train's start date, not yours.
    var startDayOffset = 0
    /// Departure from your boarding station, minutes after midnight IST. Used for the chart time.
    var departureMinutes: Int?
    var travelClass = TravelClass.ac3
    var quota = Quota.tatkal
    var passengers = 1
    var backup = ""
    var notes = ""
    var checked: Set<String> = []
    /// Alert stages already shown (see `Alerts.stages`), so a relaunch doesn't repeat them.
    var fired: Set<String> = []
    var pnr = ""
    var pnrStatus = ""
    /// Ticket fare for all passengers, in rupees, without IRCTC's convenience fee. Used for the refund estimate.
    var fare: Double?
    /// Fixed times for the ✨ preview cards, which use a made-up trip that is never saved.
    var previewOpens: Date?
    var previewChart: Date?

    init() {}

    /// Every field is optional in the file, so trips saved by older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Trip()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? d.id
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? d.from
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? d.to
        trainNumber = try c.decodeIfPresent(String.self, forKey: .trainNumber) ?? d.trainNumber
        trainName = try c.decodeIfPresent(String.self, forKey: .trainName) ?? d.trainName
        journeyDate = try c.decodeIfPresent(Date.self, forKey: .journeyDate) ?? d.journeyDate
        startDayOffset = try c.decodeIfPresent(Int.self, forKey: .startDayOffset) ?? d.startDayOffset
        departureMinutes = try c.decodeIfPresent(Int.self, forKey: .departureMinutes)
        travelClass = (try? c.decodeIfPresent(TravelClass.self, forKey: .travelClass)) ?? d.travelClass
        quota = (try? c.decodeIfPresent(Quota.self, forKey: .quota)) ?? d.quota
        passengers = try c.decodeIfPresent(Int.self, forKey: .passengers) ?? d.passengers
        backup = try c.decodeIfPresent(String.self, forKey: .backup) ?? d.backup
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? d.notes
        checked = try c.decodeIfPresent(Set<String>.self, forKey: .checked) ?? d.checked
        fired = try c.decodeIfPresent(Set<String>.self, forKey: .fired) ?? d.fired
        pnr = try c.decodeIfPresent(String.self, forKey: .pnr) ?? d.pnr
        pnrStatus = try c.decodeIfPresent(String.self, forKey: .pnrStatus) ?? d.pnrStatus
        fare = try c.decodeIfPresent(Double.self, forKey: .fare)
    }

    var trainStarts: Date { Rules.calendar.date(byAdding: .day, value: startDayOffset, to: Rules.day(journeyDate))! }

    var opens: Date {
        if let previewOpens { return previewOpens }
        return quota == .general ? Rules.generalOpens(trainStarts: trainStarts)
            : Rules.tatkalOpens(trainStarts: trainStarts, travelClass: travelClass)
    }

    var departure: Date? {
        departureMinutes.map { Rules.day(journeyDate).addingTimeInterval(Double($0) * 60) }
    }

    var chart: Date? { previewChart ?? departure.map(Rules.chartTime) }

    var booked: Bool { !pnr.trimmingCharacters(in: .whitespaces).isEmpty }

    var route: String {
        let f = from.isEmpty ? "?" : from, t = to.isEmpty ? "?" : to
        return "\(f) → \(t)"
    }

    var title: String {
        let train = trainNumber.isEmpty ? "" : "\(trainNumber) "
        return "\(train)\(route) · \(travelClass.rawValue)"
    }

    /// Plain text for a note or a message to whoever is booking with you.
    var details: String {
        var lines = [
            "Train: \(trainNumber.isEmpty ? "—" : trainNumber)\(trainName.isEmpty ? "" : " \(trainName)")",
            "From \(from.isEmpty ? "—" : from) to \(to.isEmpty ? "—" : to)",
            "Journey: \(DateFormatter.ist("EEE d MMM yyyy").string(from: journeyDate))",
            "Class: \(travelClass.label) · Quota: \(quota.rawValue) · Passengers: \(passengers)",
            "\(quota.rawValue) opens: \(DateFormatter.ist("EEE d MMM, HH:mm").string(from: opens)) IST",
        ]
        if !backup.isEmpty { lines.append("Backup: \(backup)") }
        if booked { lines.append("PNR: \(pnr)\(pnrStatus.isEmpty ? "" : " (\(pnrStatus))")") }
        return lines.joined(separator: "\n")
    }
}

/// Trips, saved as JSON in Application Support. Nothing leaves the Mac.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var trips: [Trip] = [] { didSet { if trips != oldValue { save() } } }

    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppInfo.name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Travel plans are personal: only you can read the folder.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir.appendingPathComponent("trips.json")
    }()

    init() {
        if let data = try? Data(contentsOf: file),
           let list = try? JSONDecoder().decode([Trip].self, from: data) {
            trips = list
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(trips) {
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    /// Trips whose booking hasn't opened yet, or opened in the last hour, soonest first.
    func upcoming(now: Date) -> [Trip] {
        trips.filter { !$0.booked && $0.opens > now.addingTimeInterval(-3600) }.sorted { $0.opens < $1.opens }
    }

    func update(_ id: UUID, _ change: (inout Trip) -> Void) {
        guard let i = trips.firstIndex(where: { $0.id == id }) else { return }
        change(&trips[i])
    }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    /// Opens the IRCTC page with the 10-minute alert so you can sign in early.
    var openAtTen: Bool {
        get { d.object(forKey: "openAtTen") as? Bool ?? true }
        set { d.set(newValue, forKey: "openAtTen") }
    }
    /// A system sound name, or "off".
    var sound: String {
        get { d.string(forKey: "sound") ?? "Glass" }
        set { d.set(newValue, forKey: "sound") }
    }
    var voice: Bool {
        get { d.object(forKey: "voice") as? Bool ?? false }
        set { d.set(newValue, forKey: "voice") }
    }
    /// Soft ticks through the last ten seconds before opening.
    var ticks: Bool {
        get { d.object(forKey: "ticks") as? Bool ?? true }
        set { d.set(newValue, forKey: "ticks") }
    }
    var chartAlerts: Bool {
        get { d.object(forKey: "chartAlerts") as? Bool ?? true }
        set { d.set(newValue, forKey: "chartAlerts") }
    }
    /// "system" (follow macOS), "light" or "dark".
    var appearance: String {
        get { d.string(forKey: "appearance") ?? "system" }
        set { d.set(newValue, forKey: "appearance"); applyAppearance() }
    }
    func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
