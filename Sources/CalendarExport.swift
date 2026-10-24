import AppKit
import Foundation

/// Turns a trip into calendar events (an .ics file) for Calendar to import. No calendar access is
/// asked for: Calendar shows its own import dialog and you pick the calendar.
enum CalendarExport {
    /// The events for a trip: booking opening, the journey and, when the departure time is known, the chart.
    /// The PNR is left out, because calendars often sync to other services.
    static func ics(for trip: Trip, now: Date) -> String {
        var events: [[String]] = []
        let name = trip.trainNumber.isEmpty ? trip.route : "\(trip.trainNumber) \(trip.route)"

        if !trip.booked {
            events.append(event(
                uid: "\(trip.id)-opens", now: now, start: trip.opens, minutes: 15,
                summary: "\(trip.quota.rawValue) opens · \(name) \(trip.travelClass.rawValue)",
                description: "Sign in to IRCTC 10 minutes early. Berthly alerts you on the Mac too.",
                url: Rules.bookingURL, alarm: 10))
        }
        if let dep = trip.departure {
            events.append(event(
                uid: "\(trip.id)-journey", now: now, start: dep, minutes: 60,
                summary: "🚆 \(name)\(trip.trainName.isEmpty ? "" : " · \(trip.trainName)")",
                description: "\(trip.travelClass.label). Carry an original photo ID for every passenger.",
                url: Rules.ntesURL, alarm: 120))
            if let chart = trip.chart, chart > now {
                events.append(event(
                    uid: "\(trip.id)-chart", now: now, start: chart, minutes: 15,
                    summary: "Chart due · \(name)",
                    description: "Check the PNR on Indian Railways to see your final berth.",
                    url: Rules.pnrURL, alarm: 15))
            }
        } else {
            events.append(allDay(uid: "\(trip.id)-journey", now: now, day: trip.journeyDate,
                                 summary: "🚆 \(name) · \(trip.travelClass.rawValue)"))
        }

        let lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//\(AppInfo.name)//\(AppInfo.name) \(AppInfo.version)//EN",
                     "CALSCALE:GREGORIAN", "METHOD:PUBLISH"] + events.flatMap { $0 } + ["END:VCALENDAR"]
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// Writes the file where only you can read it and hands it to Calendar.
    static func open(_ trip: Trip, now: Date) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(AppInfo.name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let safe = trip.route.filter { $0.isLetter || $0.isNumber }
        let file = dir.appendingPathComponent("\(AppInfo.name) \(safe.isEmpty ? "trip" : safe).ics")
        try? FileManager.default.removeItem(at: file)
        guard FileManager.default.createFile(atPath: file.path, contents: Data(ics(for: trip, now: now).utf8),
                                             attributes: [.posixPermissions: 0o600]) else { return }
        if let calendar = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.open([file], withApplicationAt: calendar, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(file)
        }
        // Calendar has read it by then; don't leave travel plans lying around.
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: - iCalendar text (RFC 5545)

    private static func event(uid: String, now: Date, start: Date, minutes: Int, summary: String,
                              description: String, url: URL, alarm: Int) -> [String] {
        ["BEGIN:VEVENT",
         "UID:\(uid)@berthly",
         "DTSTAMP:\(utc(now))",
         "DTSTART:\(utc(start))",
         "DTEND:\(utc(start.addingTimeInterval(Double(minutes) * 60)))",
         "SUMMARY:\(escape(summary))",
         "DESCRIPTION:\(escape(description))",
         "URL:\(url.absoluteString)",
         "BEGIN:VALARM", "TRIGGER:-PT\(alarm)M", "ACTION:DISPLAY", "DESCRIPTION:\(escape(summary))", "END:VALARM",
         "END:VEVENT"]
    }

    private static func allDay(uid: String, now: Date, day: Date, summary: String) -> [String] {
        let next = Rules.calendar.date(byAdding: .day, value: 1, to: Rules.day(day))!
        return ["BEGIN:VEVENT",
                "UID:\(uid)@berthly",
                "DTSTAMP:\(utc(now))",
                "DTSTART;VALUE=DATE:\(dateOnly(day))",
                "DTEND;VALUE=DATE:\(dateOnly(next))",
                "SUMMARY:\(escape(summary))",
                "END:VEVENT"]
    }

    static func utc(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }

    /// The IST calendar day, which is the day the ticket is for.
    private static func dateOnly(_ d: Date) -> String {
        let f = DateFormatter.ist("yyyyMMdd")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Lines longer than 75 bytes continue on the next line after a space, without splitting a character.
    static func fold(_ line: String) -> String {
        var out = "", count = 0
        for ch in line {
            let n = String(ch).utf8.count
            if count + n > 75 { out += "\r\n "; count = 1 }
            out.append(ch)
            count += n
        }
        return out
    }
}
