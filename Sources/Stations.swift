import Foundation

struct Station: Hashable, Identifiable {
    let code: String
    let name: String
    /// The old code and name of a renamed station, e.g. "ALD Allahabad Jn", or "".
    let formerly: String
    var id: String { code }

    /// The code before a rename, when the code changed (ALD for Prayagraj Jn).
    var oldCode: String? {
        guard let first = formerly.split(separator: " ").first.map(String.init),
              first.count <= 5, first == first.uppercased(), first.allSatisfy(\.isLetter), first != code else { return nil }
        return first
    }
}

/// The station list bundled with the app (Resources/stations.tsv: code, name, former code and name). It works offline
/// and nothing is looked up online.
enum Stations {
    static let all: [Station] = load(Bundle.main.url(forResource: "stations", withExtension: "tsv"))

    static func load(_ url: URL?) -> [Station] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            if line.hasPrefix("#") { return nil }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 2, !f[0].isEmpty else { return nil }
            return Station(code: f[0], name: f[1], formerly: f.count > 2 ? f[2] : "")
        }
    }

    static func named(_ code: String, in list: [Station] = all) -> Station? {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        return list.first { $0.code == c }
    }

    /// The station that used to have this code, such as PRYJ for ALD.
    static func replacement(for code: String, in list: [Station] = all) -> Station? {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard !c.isEmpty else { return nil }
        return list.first { $0.oldCode == c }
    }

    /// Best matches first: the exact code, codes starting with it, names starting with it, then names
    /// containing it.
    static func search(_ query: String, in list: [Station] = all, limit: Int = 8) -> [Station] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        func rank(_ s: Station) -> Int? {
            let code = s.code.lowercased(), name = s.name.lowercased(), old = s.formerly.lowercased()
            if code == q { return 0 }
            if s.oldCode?.lowercased() == q { return 1 }
            if code.hasPrefix(q) { return 2 }
            if name.hasPrefix(q) { return 3 }
            let words = (name + " " + old).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            if words.contains(where: { $0.hasPrefix(q) }) { return 4 }
            if q.count >= 3, name.contains(q) || old.contains(q) { return 5 }
            return nil
        }
        return list.compactMap { s in rank(s).map { (s, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : ($0.0.name.count, $0.0.name) < ($1.0.name.count, $1.0.name) }
            .prefix(limit).map(\.0)
    }

    /// Station codes that changed in recent years. Shown on the Station codes page.
    static let renamed: [(old: String, new: String)] = [
        ("ALD Allahabad Jn", "PRYJ Prayagraj Jn"),
        ("MGS Mughal Sarai Jn", "DDU Pt. Deen Dayal Upadhyaya Jn"),
        ("FD Faizabad Jn", "AYC Ayodhya Cantt"),
        ("AY Ayodhya", "AY Ayodhya Dham Jn"),
        ("HBJ Habibganj", "RKMP Rani Kamalapati"),
        ("JHS Jhansi Jn", "VGLJ Virangana Lakshmibai Jhansi Jn"),
        ("MUV Manduadih", "BSBS Banaras"),
        ("CSTM Mumbai CST", "CSMT Mumbai CSMT"),
        ("BCT Mumbai Central", "MMCT Mumbai Central"),
        ("Bangalore City Jn", "SBC KSR Bengaluru City Jn"),
        ("Hubli Jn", "UBL SSS Hubballi Jn"),
    ]

    static let credit = "Station list from datameet/railways (CC0, public domain), updated by \(AppInfo.name) for renamed stations in October 2026. New stations or recent renames may be missing; IRCTC's own search always has the latest."
}
