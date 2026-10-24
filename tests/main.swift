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
exit(fails == 0 ? 0 : 1)
