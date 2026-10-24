import AppKit
import Foundation

/// The tools in the trips window sidebar.
enum Tool: String, CaseIterable, Identifiable {
    case festivals, refund, tatkal, stations, journey, tips
    var id: String { rawValue }

    var title: String {
        switch self {
        case .festivals: return "Festival planner"
        case .refund: return "Refund calculator"
        case .tatkal: return "Tatkal charges"
        case .stations: return "Station codes"
        case .journey: return "On the journey"
        case .tips: return "Good to know"
        }
    }

    var symbol: String {
        switch self {
        case .festivals: return "sparkles"
        case .refund: return "arrow.uturn.backward.circle"
        case .tatkal: return "indianrupeesign.circle"
        case .stations: return "mappin.and.ellipse"
        case .journey: return "lifepreserver"
        case .tips: return "lightbulb"
        }
    }
}

// MARK: - Ticket status

enum TicketStatus: String, CaseIterable, Identifiable {
    case confirmed = "Confirmed", rac = "RAC", waitlisted = "Waitlisted"
    var id: String { rawValue }

    /// Reads what you typed from the PNR page: "CNF B2 34", "RAC 5", "WL 12", "GNWL 20/WL 10", "B2 34".
    /// Nil when it can't tell.
    static func parse(_ text: String) -> TicketStatus? {
        let s = text.uppercased()
        if s.isEmpty || s.contains("CAN") { return nil }
        if s.contains("RAC") { return .rac }
        if s.contains("WL") { return .waitlisted }
        if s.contains("CNF") { return .confirmed }
        // A coach and berth on its own, such as "B2 34" or "S5 12".
        if s.range(of: #"\b[A-Z]{1,2}\d{1,2}\s*[,/ -]?\s*\d{1,2}\b"#, options: .regularExpression) != nil { return .confirmed }
        return nil
    }
}

// MARK: - Festivals

struct Festival: Identifiable {
    let name: String
    let date: Date
    let note: String
    var id: String { name + "\(date.timeIntervalSince1970)" }
}

/// Busy travel days. Lunar dates follow Drik Panchang (New Delhi) and the Government of India holiday list.
enum Festivals {
    static let checked = "October 2026"

    static let all: [Festival] = [
        ("Diwali", "2026-11-08", "Dhanteras is Fri 6 Nov; Bhai Dooj Wed 11 Nov."),
        ("Bhai Dooj", "2026-11-11", ""),
        ("Chhath Puja", "2026-11-15", "Sandhya Arghya. Nahay Khay is Fri 13 Nov; Usha Arghya Mon 16 Nov."),
        ("Christmas", "2026-12-25", "A Friday, so a long weekend."),
        ("New Year", "2027-01-01", "A Friday."),
        ("Pongal and Makar Sankranti", "2027-01-15", "Some calendars put Makar Sankranti on Thu 14 Jan."),
        ("Republic Day", "2027-01-26", "A Tuesday."),
        ("Maha Shivaratri", "2027-03-06", ""),
        ("Eid al-Fitr", "2027-03-10", "Expected; depends on the moon."),
        ("Holi", "2027-03-22", "Holika Dahan is Sun 21 Mar. The central holiday list has Tue 23 Mar."),
        ("Ugadi and Gudi Padwa", "2027-04-07", ""),
        ("Summer holidays begin", "2027-05-01", "School holidays run through May and June; dates vary by state."),
        ("Eid al-Adha", "2027-05-17", "Expected; depends on the moon."),
        ("Independence Day", "2027-08-15", "A Sunday."),
        ("Raksha Bandhan", "2027-08-17", ""),
        ("Janmashtami", "2027-08-25", ""),
        ("Ganesh Chaturthi", "2027-09-04", ""),
        ("Onam", "2027-09-12", "Thiruvonam."),
        ("Durga Puja", "2027-10-07", "Maha Ashtami. Dussehra is Sat 9 Oct."),
        ("Dussehra", "2027-10-09", ""),
        ("Diwali", "2027-10-29", "Dhanteras is Wed 27 Oct; Bhai Dooj Sun 31 Oct."),
        ("Chhath Puja", "2027-11-04", "Sandhya Arghya. Nahay Khay is Tue 2 Nov; Usha Arghya Fri 5 Nov."),
        ("Christmas", "2027-12-25", "A Saturday."),
    ].map { name, day, note in
        Festival(name: name, date: DateFormatter.ist("yyyy-MM-dd").date(from: day)!, note: note)
    }

    /// Festivals from today on.
    static func upcoming(now: Date) -> [Festival] {
        all.filter { $0.date >= Rules.day(now) }
    }
}

// MARK: - Official links

struct RailLink {
    let title: String
    let detail: String
    let url: URL
}

enum RailLinks {
    static let all: [RailLink] = [
        RailLink(title: "Rail Madad", detail: "Complaints and help during the journey: cleanliness, AC, water, staff, security. Track a complaint.",
                 url: URL(string: "https://railmadad.indianrailways.gov.in/")!),
        RailLink(title: "IRCTC e-Catering", detail: "Order food to your seat at a coming station with the PNR. Helpline 1323.",
                 url: URL(string: "https://www.ecatering.irctc.co.in/")!),
        RailLink(title: "Retiring rooms", detail: "IRCTC's rooms and dormitories at stations, for a long wait or an early train. Booked with a PNR.",
                 url: URL(string: "https://rr.irctc.co.in/")!),
        RailLink(title: "Train running status (NTES)", detail: "Live position, delay and expected arrival of any train.",
                 url: Rules.ntesURL),
        RailLink(title: "PNR status", detail: "Your coach, berth and waitlist position from Indian Railways.",
                 url: Rules.pnrURL),
        RailLink(title: "IRCTC", detail: "Cancel a ticket, file a TDR, or change the boarding station.",
                 url: Rules.bookingURL),
    ]

    static let helpline = "Indian Railways' single helpline: enquiries, complaints, and security or medical help on the train."
}

// MARK: - Refunds

struct RefundQuote {
    let refund: Double
    let deduction: Double
    /// Which rule applied, in a sentence.
    let rule: String
    /// When a TDR may still get money back.
    let tdrHint: String?
}

struct TatkalCharge {
    let percent: Double
    let min: Double
    let max: Double
}

/// Cancellation refunds under the Railway Passengers (Cancellation of Ticket and Refund of Fare) Rules, 2015, with
/// the slabs as revised in April 2026 (72, 24 and 8 hours; they were 48, 12 and 4). IRCTC works out the final amount.
enum Refunds {
    /// Confirmed tickets: flat charge only before this many hours, 25% before `halfHours`, 50% before `cutoffHours`.
    static let flatHours = 72.0
    static let halfHours = 24.0
    static let cutoffHours = 8.0
    /// RAC and waitlisted tickets can be cancelled until 30 minutes before departure, less the clerkage.
    static let racMinutes = 30.0
    static let clerkage = 60.0

    /// The smallest cancellation charge per passenger on a confirmed ticket.
    static func flatCharge(_ c: TravelClass) -> Double {
        switch c {
        case .ac1, .ec: return 240
        case .ac2: return 200
        case .ac3, .ac3e, .cc: return 180
        case .sl: return 120
        case .second: return 60
        }
    }

    static func quote(fare: Double, passengers: Int, travelClass: TravelClass, quota: Quota,
                      status: TicketStatus, departure: Date, at: Date) -> RefundQuote {
        let fare = max(0, fare)
        let n = Double(max(1, passengers))
        let hours = departure.timeIntervalSince(at) / 3600
        func result(_ deduction: Double, _ rule: String, tdr: String? = nil) -> RefundQuote {
            let d = min(fare, max(0, deduction))
            return RefundQuote(refund: fare - d, deduction: d, rule: rule, tdrHint: tdr)
        }
        let tdrLate = "If the train is cancelled or runs more than 3 hours late and you don't travel, you get the whole fare back: file a TDR on IRCTC before it leaves."

        if status != .confirmed {
            if hours * 60 >= racMinutes {
                return result(clerkage * n, "\(status.rawValue) ticket: the fare back less ₹\(Int(clerkage)) per passenger, if you cancel at least \(Int(racMinutes)) minutes before departure. A waitlisted e-ticket still waitlisted after the chart is cancelled and refunded this way by itself.")
            }
            return result(fare, "\(status.rawValue) ticket: no refund less than \(Int(racMinutes)) minutes before departure, or after it.", tdr: tdrLate)
        }
        if quota != .general {
            return result(fare, "A confirmed \(quota.rawValue) ticket gets no refund when you cancel it.", tdr: tdrLate)
        }
        let flat = flatCharge(travelClass) * n
        if hours > flatHours {
            return result(flat, "More than \(Int(flatHours)) hours before departure: a flat ₹\(Int(flatCharge(travelClass))) per passenger is deducted.")
        }
        if hours > halfHours {
            return result(max(fare * 0.25, flat), "\(Int(flatHours))–\(Int(halfHours)) hours before departure: 25% of the fare is deducted, at least ₹\(Int(flatCharge(travelClass))) per passenger.")
        }
        if hours > cutoffHours {
            return result(max(fare * 0.5, flat), "\(Int(halfHours))–\(Int(cutoffHours)) hours before departure: 50% of the fare is deducted, at least ₹\(Int(flatCharge(travelClass))) per passenger.")
        }
        return result(fare, "Less than \(Int(cutoffHours)) hours before departure, or after it: a confirmed ticket gets no refund.", tdr: tdrLate)
    }

    static let footnote = "An estimate. The slabs changed in April 2026 (72, 24 and 8 hours; they were 48, 12 and 4), and some official pages still show the old ones. GST is added to the charge on AC classes, and IRCTC's booking fee isn't refunded. Vande Bharat Sleeper and Amrit Bharat trains have stricter rules. IRCTC shows the exact amount before you confirm a cancellation."

    static let rulesTable: [(String, String)] = [
        ("Confirmed, over 72 h before", "Flat charge per passenger"),
        ("Confirmed, 72–24 h", "25% of the fare (at least the flat charge)"),
        ("Confirmed, 24–8 h", "50% of the fare (at least the flat charge)"),
        ("Confirmed, under 8 h", "No refund"),
        ("RAC or waitlisted", "₹60 per passenger, until 30 min before"),
        ("Confirmed Tatkal or Premium Tatkal", "No refund"),
        ("Train cancelled", "Full refund (e-tickets automatically)"),
    ]

    static let flatTable = "1A and EC ₹240 · 2A ₹200 · 3A, 3E and CC ₹180 · SL ₹120 · 2S ₹60, plus GST on AC classes."

    /// The Tatkal charge per passenger: a share of the basic fare between a minimum and a maximum.
    /// 3E isn't listed separately, so it uses the 3A figures. There's no Tatkal in 1A.
    static func tatkalCharge(_ c: TravelClass) -> TatkalCharge? {
        switch c {
        case .ac1: return nil
        case .second: return TatkalCharge(percent: 0.1, min: 10, max: 15)
        case .sl: return TatkalCharge(percent: 0.3, min: 100, max: 200)
        case .cc: return TatkalCharge(percent: 0.3, min: 125, max: 225)
        case .ac3, .ac3e: return TatkalCharge(percent: 0.3, min: 300, max: 400)
        case .ac2, .ec: return TatkalCharge(percent: 0.3, min: 400, max: 500)
        }
    }

    static func tatkalCharge(basicFare: Double, _ c: TravelClass) -> Double? {
        guard let ch = tatkalCharge(c), basicFare > 0 else { return nil }
        return min(max((basicFare * ch.percent).rounded(), ch.min), ch.max)
    }
}

// MARK: - TDR

/// Ticket deposit receipts: refunds for things that went wrong, filed on IRCTC.
enum TDR {
    static let cases: [(String, String)] = [
        ("Train cancelled", "E-tickets are cancelled and refunded in full by themselves; no TDR is needed."),
        ("Train more than 3 hours late", "If you don't travel, file a TDR before the train actually leaves your station for the whole fare back."),
        ("AC not working", "File within 20 hours of arriving, with the certificate from the ticket checker. You get back the difference to the class you were really given."),
        ("Moved to a lower class", "File within 2 days of the ticket checker's certificate; you get the fare difference back."),
        ("Train diverted", "If it doesn't call at your boarding or destination station and you don't travel, file within 72 hours of the scheduled departure."),
        ("Only some of a party travelled", "File within 72 hours of arriving, with the ticket checker's certificate for those who didn't travel."),
    ]

    static let howTo = "On IRCTC: My Account → My Transactions → File TDR, then pick the ticket, the passengers and the reason. The refund goes back to the account you paid from. Deadlines follow the 2015 refund rules; IRCTC shows the reasons it accepts for your ticket."
}

// MARK: - Tips

struct Tip {
    let title: String
    let text: String
}

enum Tips {
    static let all: [Tip] = [
        Tip(title: "VIKALP: an alternate train",
            text: "Opt in to VIKALP when you book a waitlisted ticket. If you're still fully waitlisted after the chart, you may be moved to another train on the route that leaves within 72 hours, with no extra fare. The whole PNR moves, in the same class. RAC and part-confirmed tickets don't qualify."),
        Tip(title: "Free auto-upgrade",
            text: "Tick “Consider for auto-upgradation” and a full-fare passenger may be moved up to two classes higher (SL → 3E → 3A → 2A → 1A, or 2S → CC → EC) at no extra cost when seats are free. A senior citizen or lower-berth passenger may lose the lower berth if upgraded."),
        Tip(title: "Lower berths for seniors and women",
            text: "Men aged 60 and over, women aged 45 and over and pregnant women get a lower berth from a small quota in each coach when one is free. Tick “Book only if a lower berth is allotted” to avoid paying for an upper one."),
        Tip(title: "No senior citizen fare concession",
            text: "The fare discount for senior citizens has been withdrawn since 20 March 2020 and hasn't come back. The lower-berth quota still applies."),
        Tip(title: "Passengers per ticket",
            text: "Up to \(Rules.tatkalPassengers) passengers on one Tatkal or Premium Tatkal ticket and up to \(Rules.generalPassengers) on a general one. Children under 5 travel free without a berth; add them as infants."),
        Tip(title: "Tatkal needs Aadhaar",
            text: "Online Tatkal booking needs an IRCTC account verified with Aadhaar, and an OTP to your Aadhaar-linked phone. Do it days before, not on the morning."),
        Tip(title: "Carry an original ID",
            text: "An e-ticket on your phone is fine, but at least one passenger on the ticket must carry an original photo ID (Aadhaar, PAN, passport, driving licence, voter ID or similar) for the ticket checker."),
        Tip(title: "One account, by hand",
            text: "IRCTC allows one account per person and blocks bots, auto-fill extensions and shared logins. \(AppInfo.name) only reminds you and opens the official site; you book yourself."),
    ]
}
