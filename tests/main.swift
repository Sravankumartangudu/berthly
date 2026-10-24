import Foundation
let f = DateFormatter.ist("EEE d MMM yyyy HH:mm zzz")
func d(_ s: String) -> Date { let p = DateFormatter.ist("yyyy-MM-dd HH:mm"); return p.date(from: s)! }
var fails = 0
func check(_ label: String, _ got: Date, _ want: String) {
  let ok = got == d(want); if !ok { fails += 1 }
  print(ok ? "✓" : "✗", label, f.string(from: got), ok ? "" : "(want \(want))")
}
let j = d("2026-11-15 00:00")
check("Tatkal AC 3A", Rules.tatkalOpens(trainStarts: j, travelClass: .ac3), "2026-11-14 10:00")
check("Tatkal SL", Rules.tatkalOpens(trainStarts: j, travelClass: .sl), "2026-11-14 11:00")
check("Tatkal 2S", Rules.tatkalOpens(trainStarts: j, travelClass: .second), "2026-11-14 11:00")
check("Tatkal over month edge", Rules.tatkalOpens(trainStarts: d("2026-12-01 00:00"), travelClass: .cc), "2026-11-30 10:00")
check("General 60d", Rules.generalOpens(trainStarts: j), "2026-09-16 08:00")
check("Chart 16:55 dep", Rules.chartTime(departure: d("2026-11-15 16:55")), "2026-11-15 06:55")
check("Chart 06:10 dep", Rules.chartTime(departure: d("2026-11-15 06:10")), "2026-11-14 20:00")
check("Chart 13:59 dep", Rules.chartTime(departure: d("2026-11-15 13:59")), "2026-11-14 20:00")
check("Chart 14:00 dep", Rules.chartTime(departure: d("2026-11-15 14:00")), "2026-11-15 04:00")
check("Chart 02:30 dep", Rules.chartTime(departure: d("2026-11-15 02:30")), "2026-11-14 16:30")
var t = Trip(); t.journeyDate = j; t.startDayOffset = -1; t.travelClass = .sl
check("Mid-route boarding", t.opens, "2026-11-13 11:00")
t.departureMinutes = 14*60+30
check("Trip departure", t.departure!, "2026-11-15 14:30")
check("Evening alert", Stage.evening.time(for: t)!, "2026-11-12 20:00")
// Old/partial JSON still loads
let old = #"[{"from":"SBC","to":"MAS","journeyDate":800000000}]"#.data(using: .utf8)!
let list = try! JSONDecoder().decode([Trip].self, from: old)
print(list[0].from == "SBC" && list[0].quota == .tatkal ? "✓ partial JSON loads" : "✗ partial JSON"); 
print("countdown:", countdown(to: Date().addingTimeInterval(3725), from: Date()), countdown(to: Date().addingTimeInterval(65), from: Date()), countdown(to: Date().addingTimeInterval(200000), from: Date()))
func expect(_ label: String, _ ok: Bool, _ got: Any = "") {
  if !ok { fails += 1 }
  print(ok ? "✓" : "✗", label, ok ? "" : "(got \(got))")
}

// Ticket status typed from the PNR page
for (text, want) in [("CNF B2 34", TicketStatus.confirmed), ("B2 34", .confirmed), ("S5, 12", .confirmed), ("RAC 5", .rac),
                     ("WL 12", .waitlisted), ("GNWL 20/WL 10", .waitlisted), ("RLWL 3", .waitlisted)] {
  expect("status \(text)", TicketStatus.parse(text) == want, String(describing: TicketStatus.parse(text)))
}
expect("status blank", TicketStatus.parse("") == nil)
expect("status cancelled", TicketStatus.parse("CAN") == nil)

// Calendar file
var cal = Trip(); cal.from = "NDLS"; cal.to = "MMCT"; cal.trainNumber = "12952"; cal.journeyDate = j
cal.departureMinutes = 16 * 60 + 55; cal.pnr = ""
let ics = CalendarExport.ics(for: cal, now: d("2026-10-24 12:00"))
expect("ics has 3 events", ics.components(separatedBy: "BEGIN:VEVENT").count - 1 == 3)
expect("ics opening in UTC", ics.contains("DTSTART:20261114T043000Z"), ics)
expect("ics journey in UTC", ics.contains("DTSTART:20261115T112500Z"))
expect("ics CRLF lines", !ics.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
expect("ics lines ≤ 75 bytes", ics.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
cal.pnr = "4521367890"
let booked = CalendarExport.ics(for: cal, now: d("2026-10-24 12:00"))
expect("ics never has the PNR", !booked.contains("4521367890"))
expect("ics booked skips opening", !booked.contains("-opens@"))
expect("ics escape", CalendarExport.escape("a,b;c\\d\ne") == "a\\,b\\;c\\\\d\\ne", CalendarExport.escape("a,b;c\\d\ne"))
var noDep = Trip(); noDep.journeyDate = j
expect("ics all-day without a time", CalendarExport.ics(for: noDep, now: d("2026-10-24 12:00")).contains("DTSTART;VALUE=DATE:20261115"))

// Station search
let st = Stations.load(URL(fileURLWithPath: "Resources/stations.tsv"))
expect("stations loaded", st.count > 500, st.count)
expect("search code SC", Stations.search("sc", in: st).first?.code == "SC", Stations.search("sc", in: st).map(\.code))
expect("search name hyderabad", Stations.search("hyderabad", in: st).contains { $0.code == "HYB" }, Stations.search("hyderabad", in: st).map(\.code))
expect("named ndls", Stations.named(" ndls ", in: st)?.name.lowercased().contains("delhi") == true)

expect("replacement ALD → PRYJ", Stations.replacement(for: "ald", in: st)?.code == "PRYJ")

// Refunds: a 3A ticket for two at ₹2,000, train at 20:00 IST on 15 Nov.
let dep = d("2026-11-15 20:00")
func refund(_ at: String, _ status: TicketStatus = .confirmed, _ quota: Quota = .general, fare: Double = 2000) -> Double {
  Refunds.quote(fare: fare, passengers: 2, travelClass: .ac3, quota: quota, status: status, departure: dep, at: d(at)).refund
}
expect("refund >72h flat", refund("2026-11-11 20:00") == 2000 - 360, refund("2026-11-11 20:00"))
expect("refund 72–24h 25%", refund("2026-11-13 20:00") == 1500, refund("2026-11-13 20:00"))
expect("refund 25% floored at flat", refund("2026-11-13 20:00", fare: 1000) == 1000 - 360, refund("2026-11-13 20:00", fare: 1000))
expect("refund 24–8h 50%", refund("2026-11-15 10:00") == 1000, refund("2026-11-15 10:00"))
expect("refund <8h none", refund("2026-11-15 13:00") == 0)
expect("refund RAC clerkage", refund("2026-11-15 19:00", .rac) == 1880, refund("2026-11-15 19:00", .rac))
expect("refund WL after 30 min none", refund("2026-11-15 19:45", .waitlisted) == 0)
expect("refund Tatkal confirmed none", refund("2026-11-14 12:00", .confirmed, .tatkal) == 0)
expect("refund Tatkal WL clerkage", refund("2026-11-14 12:00", .waitlisted, .tatkal) == 1880)
expect("refund never negative", refund("2026-11-11 20:00", .rac, fare: 50) == 0)
expect("tatkal SL min", Refunds.tatkalCharge(basicFare: 200, .sl) == 100)
expect("tatkal 3A 30%", Refunds.tatkalCharge(basicFare: 1200, .ac3) == 360)
expect("tatkal 2A cap", Refunds.tatkalCharge(basicFare: 3000, .ac2) == 500)
expect("no tatkal in 1A", Refunds.tatkalCharge(.ac1) == nil)

exit(fails == 0 ? 0 : 1)
