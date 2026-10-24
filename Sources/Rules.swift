import Foundation

/// Indian Railways booking-window rules. Every time here is Indian Standard Time, whatever zone the Mac is in.
/// The rules change from time to time, so they all live in this one file (see `Rules.checked`).
enum Rules {
    /// When these rules were last checked against IRCTC / Indian Railways notices.
    static let checked = "October 2026"

    static let ist = TimeZone(identifier: "Asia/Kolkata")!
    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = ist
        return c
    }()

    /// General (non-Tatkal) booking opens this many days before the journey, not counting the journey day.
    static let advanceDays = 60
    static let generalOpenHour = 8

    /// The first minutes after general booking opens are for Aadhaar-verified accounts only.
    static let generalAadhaarMinutes = 15
    /// IRCTC-authorised agents can't book Tatkal in the first 30 minutes.
    static let agentBlockMinutes = 30

    /// Booking links. The app only opens these pages; you sign in, fill and pay on IRCTC yourself.
    static let bookingURL = URL(string: "https://www.irctc.co.in/nget/train-search")!
    static let pnrURL = URL(string: "https://www.indianrail.gov.in/enquiry/PNR/PnrEnquiry.html?locale=en")!
    static let ntesURL = URL(string: "https://enquiry.indianrail.gov.in/ntes/")!

    /// Midnight IST on the given IST calendar day.
    static func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }

    static func at(_ hour: Int, _ minute: Int = 0, on d: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(d))!
    }

    /// Tatkal and Premium Tatkal open the day before the train leaves its *originating* station.
    static func tatkalOpens(trainStarts: Date, travelClass: TravelClass) -> Date {
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: day(trainStarts))!
        return at(travelClass.isAC ? 10 : 11, on: dayBefore)
    }

    /// General booking opens at 08:00 IST, 60 days before the journey (the journey day itself not counted).
    static func generalOpens(trainStarts: Date) -> Date {
        let d = calendar.date(byAdding: .day, value: -advanceDays, to: day(trainStarts))!
        return at(generalOpenHour, on: d)
    }

    /// The first reservation chart (rules from December 2025): trains leaving 05:00–14:00 get it at 20:00 the
    /// evening before; every other train about 10 hours before departure. The final chart follows 30 minutes
    /// before departure.
    static func chartTime(departure: Date) -> Date {
        let hour = calendar.component(.hour, from: departure)
        if (5..<14).contains(hour) {
            let eve = calendar.date(byAdding: .day, value: -1, to: day(departure))!
            return at(20, on: eve)
        }
        return departure.addingTimeInterval(-10 * 3600)
    }
}

enum TravelClass: String, Codable, CaseIterable, Identifiable {
    case ac2 = "2A", ac3 = "3A", ac3e = "3E", cc = "CC", ec = "EC", sl = "SL", second = "2S"
    var id: String { rawValue }
    var isAC: Bool { ![.sl, .second].contains(self) }
    var label: String {
        switch self {
        case .ac2: return "2A · AC 2-tier"
        case .ac3: return "3A · AC 3-tier"
        case .ac3e: return "3E · AC 3 economy"
        case .cc: return "CC · AC chair car"
        case .ec: return "EC · Executive chair"
        case .sl: return "SL · Sleeper"
        case .second: return "2S · Second sitting"
        }
    }
}

enum Quota: String, Codable, CaseIterable, Identifiable {
    case tatkal = "Tatkal", premium = "Premium Tatkal", general = "General"
    var id: String { rawValue }
}

/// "in 2d 4h", "in 12:05", "now"; clocks show seconds in the last hour.
func countdown(to target: Date, from now: Date) -> String {
    let s = Int(target.timeIntervalSince(now).rounded(.up))
    if s <= 0 { return "open now" }
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return String(format: "%dh %02dm", h, m) }
    return String(format: "%d:%02d", m, sec)
}

extension DateFormatter {
    /// Formats in IST, e.g. "Fri 24 Oct, 10:00".
    static func ist(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.timeZone = Rules.ist
        f.dateFormat = format
        return f
    }
}
