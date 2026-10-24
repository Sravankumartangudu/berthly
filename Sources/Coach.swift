import Foundation

/// ✨ Trip coach: asks the local `claude` CLI for a booking plan. Optional; the app works without it.
/// Only the trip details below are sent, never your IRCTC sign-in, Aadhaar or payment details.
enum Coach {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    private static let path = #"export PATH="$HOME/.local/bin:$HOME/.devbar/bin:/opt/homebrew/bin:/usr/local/bin:$PATH""#

    static let available: Bool = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "\(path); command -v claude >/dev/null"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }()

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppInfo.name, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: d.path)
        return d
    }()

    static func prompt(for trip: Trip, now: Date) -> String {
        let f = DateFormatter.ist("EEE d MMM yyyy, HH:mm")
        let general = Rules.generalOpens(trainStarts: trip.trainStarts)
        let tatkal = Rules.tatkalOpens(trainStarts: trip.trainStarts, travelClass: trip.travelClass)
        // Never the PNR: anyone with it can look up the passengers' names on the PNR page.
        var shared = trip
        shared.pnr = ""
        let booked = trip.booked ? "Already booked\(trip.pnrStatus.isEmpty ? "" : ", status \(trip.pnrStatus)")." : ""
        return """
        You are a calm, practical Indian Railways booking coach inside a Mac app. The traveller books on IRCTC \
        by hand; the app only reminds them and opens pages. Never suggest booking bots, autofill extensions, \
        CAPTCHA solvers, several IRCTC accounts, or touts and unauthorised agents: they break IRCTC's rules \
        and the Railways Act. Rules the app uses (checked \(Rules.checked); say so if you know they have changed): \
        general booking opens 08:00 IST \(Rules.advanceDays) days ahead; Tatkal and Premium Tatkal open the day \
        before the train's start date, 10:00 IST for AC and 11:00 IST for SL/2S; online Tatkal needs an \
        Aadhaar-verified account and an Aadhaar OTP; at most 4 passengers per Tatkal PNR; the first chart \
        comes at 20:00 the evening before for trains leaving 05:00–14:00 and about 10 hours before departure \
        for the rest, with a final chart 30 minutes before departure.

        Right now it is \(f.string(from: now)) IST.
        Trip:
        \(shared.details)
        \(booked)
        \(general <= now
          ? "General booking opened \(f.string(from: general)) IST and stays open until the chart, so it can still be booked if seats or a waitlist are available."
          : "General booking opens \(f.string(from: general)) IST.") \
        \(tatkal <= now ? "Tatkal opened \(f.string(from: tatkal)) IST." : "Tatkal opens \(f.string(from: tatkal)) IST.")
        \(trip.notes.isEmpty ? "" : "Traveller's notes: \(trip.notes)")

        Give a short plan in plain text, under 220 words. No markdown: no **, # headings or tables; plain numbered lines are fine.
        1. Which quota to aim for and why (general first if it's still open in time, Tatkal vs Premium Tatkal trade-off).
        2. A minute-by-minute plan for the opening.
        3. Two or three fallbacks: other trains on the route if you know them, nearby boarding stations, \
        another class, Vikalp, or splitting the journey. Say plainly when you're unsure a train exists.
        """
    }

    /// Runs one question; `done` is called on the main queue.
    static func ask(_ trip: Trip, now: Date, done: @escaping (Result<String, Error>) -> Void) {
        guard available else {
            return done(.failure(Failure(message: "The ✨ coach needs the Claude command-line tool (claude). Install it and sign in, then try again.")))
        }
        let settings = authSettings()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "\(path); exec claude \"$@\"", "coach",
                       "-p", prompt(for: trip, now: now),
                       "--model", "haiku",
                       "--setting-sources", "project",
                       "--settings", settings.path,
                       "--tools", ""]
        p.currentDirectoryURL = dir
        p.environment = ProcessInfo.processInfo.environment.filter {
            !["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID"].contains($0.key)
        }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.terminationHandler = { proc in
            try? FileManager.default.removeItem(at: settings)
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let problem = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                if proc.terminationStatus == 0, !text.isEmpty {
                    done(.success(plain(text)))
                } else {
                    let why = problem.split(separator: "\n").last.map(String.init) ?? "it stopped with code \(proc.terminationStatus)"
                    done(.failure(Failure(message: "The coach couldn't answer: \(why)")))
                }
            }
        }
        do { try p.run() } catch {
            try? FileManager.default.removeItem(at: settings)
            done(.failure(error))
        }
    }

    /// The answer is shown as plain text, so drop any markdown bold markers and heading hashes.
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let t = line.drop { $0 == " " }
                return t.hasPrefix("#") ? String(t.drop { $0 == "#" || $0 == " " }) : String(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Copy just the sign-in keys from ~/.claude/settings.json, so the coach signs in like Terminal does
    /// while skipping the rest of your user settings (hooks, plugins, MCP servers). The copy is readable
    /// only by you from the moment it's created, and is deleted when the coach finishes.
    private static func authSettings() -> URL {
        let out = dir.appendingPathComponent("auth-settings-\(UUID().uuidString).json")
        let user = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        var auth: [String: Any] = [:]
        if let data = try? Data(contentsOf: user),
           let all = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["apiKeyHelper", "env", "awsAuthRefresh", "awsCredentialExport", "forceLoginMethod"] {
                auth[key] = all[key]
            }
        }
        let data = (try? JSONSerialization.data(withJSONObject: auth)) ?? Data("{}".utf8)
        FileManager.default.createFile(atPath: out.path, contents: data, attributes: [.posixPermissions: 0o600])
        return out
    }
}
