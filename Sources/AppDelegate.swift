import AppKit
import AVFoundation
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store.shared
    private let settings = Settings.shared
    private let clock = Clock.shared
    private let alert = AlertPanel()
    private let trips = TripsWindow()
    private let synth = AVSpeechSynthesizer()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastSecond = -1
    private var lastTick = -1
    /// A preview trip that isn't saved.
    private var demo: Trip?

    private static let sounds = ["Glass", "Hero", "Ping", "Pop", "Purr", "Submarine", "Tink"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.applyAppearance()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🚆"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        NexusBeacon.start(name: AppInfo.name) { [weak self] in
            guard let self else { return ("ok", "") }
            let now = self.clock.now
            if let next = self.store.upcoming(now: now).first {
                let what = "\(next.quota.rawValue) \(next.route)"
                return ("ok", next.opens > now ? "\(what) opens in \(countdown(to: next.opens, from: now))" : "\(what) is open")
            }
            return ("ok", "no trips waiting")
        }
        NexusBeacon.attach(statusItem)   // lets the app live in Nexus's menu

        alert.model.onOpen = { NSWorkspace.shared.open(Rules.bookingURL) }
        alert.model.onPNR = { [weak self] in self?.openPNR(self?.alert.model.trip) }
        alert.model.onDismiss = { [weak self] in self?.alert.close() }
        alert.model.onShowTrip = { [weak self] in
            guard let self, let t = self.alert.model.trip, t.id != self.demo?.id else { return }
            self.trips.show(t.id)
        }

        clock.start()

        // A quarter-second tick keeps the seconds flipping on time; the work below runs once per second.
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()

        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--tool"), i + 1 < args.count, let tool = Tool(rawValue: args[i + 1]) {
            trips.show(tool)
        } else if args.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.preview(.ten) }
        } else if store.trips.isEmpty || CommandLine.arguments.contains("--trips") {
            trips.show()
        }
    }

    // MARK: - Ticking

    private func tick() {
        let now = clock.now
        let second = Int(now.timeIntervalSince1970)
        guard second != lastSecond else { return }
        lastSecond = second

        alert.model.now = now
        trips.selection.now = now
        updateTitle(now)
        checkStages(now)
        tickSound(now)
    }

    /// Shows the latest due alert for each trip and marks it (and anything earlier) as done.
    private func checkStages(_ now: Date) {
        for trip in store.trips {
            var due: [Stage] = []
            for stage in Stage.allCases where !trip.fired.contains(stage.rawValue) {
                guard let at = stage.time(for: trip), at <= now else { continue }
                if stage == .chart && (!settings.chartAlerts || !trip.booked) { continue }
                if stage != .chart && trip.booked { continue }
                due.append(stage)
            }
            guard !due.isEmpty else { continue }
            store.update(trip.id) { t in due.forEach { t.fired.insert($0.rawValue) } }
            // Show only the newest one, if it isn't stale.
            if let last = due.last, let at = last.time(for: trip), now.timeIntervalSince(at) < last.grace {
                present(trip, last)
            }
        }
    }

    private func present(_ trip: Trip, _ stage: Stage) {
        // A newer alert for a different trip only replaces the card if its opening is sooner.
        if alert.isShowing, let shown = alert.model.trip, shown.id != trip.id, shown.id != demo?.id,
           shown.opens < trip.opens, shown.opens > clock.now.addingTimeInterval(-600) {
            return
        }
        alert.show(trip, stage)
        if settings.sound != "off" { NSSound(named: settings.sound)?.play() }
        if settings.voice {
            synth.stopSpeaking(at: .immediate)
            synth.speak(AVSpeechUtterance(string: "\(trip.quota.rawValue). \(stage.headline)."))
        }
        if stage == .ten, settings.openAtTen, trip.id != demo?.id { NSWorkspace.shared.open(Rules.bookingURL) }
    }

    /// Soft ticks for the last ten seconds before an opening the card is counting down to.
    private func tickSound(_ now: Date) {
        guard settings.ticks, alert.isShowing, let trip = alert.model.trip, alert.model.stage.countsDown else { return }
        let left = Int(trip.opens.timeIntervalSince(now).rounded(.up))
        guard left != lastTick else { return }
        lastTick = left
        if (1...10).contains(left) { NSSound(named: "Tink")?.play() }
        if left == 0 { NSSound(named: "Hero")?.play() }
    }

    // MARK: - Menu bar

    private func updateTitle(_ now: Date) {
        guard let button = statusItem?.button else { return }
        var text = "🚆"
        if let next = store.upcoming(now: now).first {
            let left = next.opens.timeIntervalSince(now)
            if left <= 0 { text += " open" } else if left < 3 * 3600 { text += " " + countdown(to: next.opens, from: now) }
        }
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
        ])
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = clock.now
        menu.addItem(sectionHeader("\(AppInfo.name) · booking opens"))

        let upcoming = store.upcoming(now: now)
        if upcoming.isEmpty {
            menu.addItem(disabled(store.trips.isEmpty ? "No trips yet" : "Nothing waiting to open"))
        }
        let f = DateFormatter.ist("EEE HH:mm")
        for t in upcoming.prefix(8) {
            let when = t.opens <= now ? "open now" : "\(f.string(from: t.opens)) · in \(countdown(to: t.opens, from: now))"
            let mi = item("\(t.quota.rawValue)  \(t.title)  —  \(when)", #selector(showTrip(_:)))
            mi.representedObject = t.id
            menu.addItem(mi)
        }
        let booked = store.trips.filter { $0.booked && $0.journeyDate >= Rules.day(now) }
        if !booked.isEmpty {
            menu.addItem(.separator())
            menu.addItem(sectionHeader("Booked"))
            for t in booked.prefix(6) {
                let status = t.pnrStatus.isEmpty ? "" : " · \(t.pnrStatus)"
                let mi = item("\(t.title)  —  PNR \(t.pnr)\(status)", #selector(showTrip(_:)))
                mi.representedObject = t.id
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("New trip…", #selector(newTrip), key: "n"))
        menu.addItem(item("Show trips", #selector(showTrips), key: "t"))
        menu.addItem(.separator())
        menu.addItem(item("Open IRCTC", #selector(openIRCTC), key: "o"))
        menu.addItem(item("Check a PNR on Indian Railways", #selector(openPNRPage)))
        menu.addItem(item("Train running status (NTES)", #selector(openNTES)))
        let tools = NSMenu()
        for tool in Tool.allCases {
            let mi = item(tool.title, #selector(showTool(_:)))
            mi.representedObject = tool.rawValue
            mi.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil)
            tools.addItem(mi)
        }
        menu.addItem(submenu("Rail tools", tools))

        menu.addItem(.separator())
        let preview = NSMenu()
        for (label, stage) in [("Evening before", Stage.evening), ("30 minutes before", .thirty), ("10 minutes before", .ten),
                               ("Final 2 minutes", .two), ("Booking open", .open), ("Chart due", .chart)] {
            let mi = item(label, #selector(previewFromMenu(_:)))
            mi.representedObject = stage.rawValue
            preview.addItem(mi)
        }
        menu.addItem(submenu("✨ Preview an alert", preview))

        let prefs = NSMenu()
        prefs.addItem(sectionHeader("Alerts"))
        prefs.addItem(toggle("Open IRCTC with the 10-minute alert", settings.openAtTen, #selector(toggleOpenAtTen)))
        prefs.addItem(toggle("Tick through the last 10 seconds", settings.ticks, #selector(toggleTicks)))
        prefs.addItem(toggle("Alert before the chart comes out", settings.chartAlerts, #selector(toggleChart)))
        let soundMenu = NSMenu()
        for name in ["off"] + Self.sounds {
            let mi = item(name == "off" ? "Off" : name, #selector(setSound(_:)))
            mi.representedObject = name
            mi.state = settings.sound == name ? .on : .off
            soundMenu.addItem(mi)
        }
        prefs.addItem(submenu("Alert sound", soundMenu))
        prefs.addItem(toggle("Voice announcement", settings.voice, #selector(toggleVoice)))

        prefs.addItem(.separator())
        prefs.addItem(sectionHeader("Clock"))
        prefs.addItem(disabled(clock.summary))
        prefs.addItem(item("Sync clock now", #selector(syncClock)))

        prefs.addItem(.separator())
        prefs.addItem(sectionHeader("App"))
        let appearanceMenu = NSMenu()
        for (raw, label) in [("system", "System"), ("light", "Light"), ("dark", "Dark")] {
            let mi = item(label, #selector(setAppearance(_:)))
            mi.representedObject = raw
            mi.state = settings.appearance == raw ? .on : .off
            appearanceMenu.addItem(mi)
        }
        prefs.addItem(submenu("Appearance", appearanceMenu))
        prefs.addItem(toggle("Launch at login", SMAppService.mainApp.status == .enabled, #selector(toggleLogin)))
        prefs.addItem(disabled("Version \(AppInfo.version) · rules checked \(Rules.checked)"))
        menu.addItem(submenu("⚙ Settings", prefs))

        menu.addItem(.separator())
        menu.addItem(item("Quit \(AppInfo.name)", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return mi
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        mi.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.8,
        ])
        mi.isEnabled = false
        return mi
    }

    private func toggle(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let mi = item(title, action)
        mi.state = on ? .on : .off
        return mi
    }

    private func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.submenu = sub
        return mi
    }

    // MARK: - Actions

    @objc private func showTrip(_ sender: NSMenuItem) { trips.show(sender.representedObject as? UUID) }
    @objc private func showTrips() { trips.show() }
    @objc private func newTrip() { trips.newTrip() }
    @objc private func showTool(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let tool = Tool(rawValue: raw) { trips.show(tool) }
    }
    @objc private func openIRCTC() { NSWorkspace.shared.open(Rules.bookingURL) }
    @objc private func openPNRPage() { openPNR(nil) }
    @objc private func openNTES() { NSWorkspace.shared.open(Rules.ntesURL) }

    /// Copies the trip's PNR (if any) for pasting, then opens the official enquiry page.
    private func openPNR(_ trip: Trip?) {
        if let pnr = trip?.pnr.filter(\.isNumber), !pnr.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pnr, forType: .string)
        }
        NSWorkspace.shared.open(Rules.pnrURL)
    }

    @objc private func previewFromMenu(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let stage = Stage(rawValue: raw) { preview(stage) }
    }

    /// Shows the card with a made-up trip whose opening is the right distance away for the stage.
    private func preview(_ stage: Stage) {
        var t = Trip()
        t.from = "NDLS"; t.to = "MMCT"
        t.trainNumber = "12952"; t.trainName = "Rajdhani Express"
        t.travelClass = .ac3; t.quota = .tatkal; t.passengers = 2
        t.checked = ["aadhaar", "master", "trip"]
        let lead: TimeInterval
        switch stage {
        case .evening: lead = 14 * 3600
        case .thirty: lead = 30 * 60
        case .ten: lead = 10 * 60
        case .two: lead = 15
        case .open: lead = -5
        case .chart: lead = 0
        }
        t.previewOpens = clock.now.addingTimeInterval(lead)
        if stage == .chart {
            t.pnr = "4521367890"; t.pnrStatus = "WL 4"
            t.previewChart = clock.now.addingTimeInterval(15 * 60)
        }
        demo = t
        alert.show(t, stage)
        if settings.sound != "off" { NSSound(named: settings.sound)?.play() }
    }

    @objc private func toggleOpenAtTen() { settings.openAtTen.toggle() }
    @objc private func toggleTicks() { settings.ticks.toggle() }
    @objc private func toggleChart() { settings.chartAlerts.toggle() }
    @objc private func toggleVoice() { settings.voice.toggle() }
    @objc private func syncClock() { clock.sync() }

    @objc private func setSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        settings.sound = name
        if name != "off" { NSSound(named: name)?.play() }
    }

    @objc private func setAppearance(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String { settings.appearance = raw }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("\(AppInfo.name): launch-at-login change failed: \(error)")
        }
    }
}
