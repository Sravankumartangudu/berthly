// Clock sync check: swiftc -o /tmp/berthly-clock tests/clock/main.swift Sources/Clock.swift && /tmp/berthly-clock
import Foundation
Clock.shared.onChange = { print(Clock.shared.summary, "offset", Clock.shared.offset); exit(0) }
Clock.shared.sync()
DispatchQueue.main.asyncAfter(deadline: .now() + 12) { print("no sync:", Clock.shared.summary); exit(1) }
RunLoop.main.run()
