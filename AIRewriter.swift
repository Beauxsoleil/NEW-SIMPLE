import Foundation

enum RewriteMode: String, CaseIterable, Identifiable {
    case concise, friendly, formal, bulletize
    var id: String { rawValue }
}

enum AIRewriter {
    static func rewrite(_ text: String, mode: RewriteMode) -> String {
        var t = normalizeWhitespace(text)
        switch mode {
        case .concise:
            t = dropFillers(t)
            t = shortenPhrases(t)
            t = ensurePeriod(t)
        case .friendly:
            t = addWarmth(t)
            t = ensurePeriod(t)
        case .formal:
            t = formalize(t)
            t = ensurePeriod(t)
        case .bulletize:
            t = bulletize(t)
        }
        return t
    }

    static func weeklySummary(applicants: [Applicant], events: [RecruitEvent], agingWarn: Int, agingDanger: Int) -> String {
        let enlistedThisMonth = applicants.filter {
            $0.stage == .enlisted && Calendar.current.isDate($0.stageStart, equalTo: Date(), toGranularity: .month)
        }.count
        let red = applicants.filter { $0.daysSinceActivity >= agingDanger }
        let yellow = applicants.filter { let d = $0.daysSinceActivity; return d >= agingWarn && d < agingDanger }

        var lines: [String] = []
        lines.append("WINS")
        lines.append("- \(enlistedThisMonth) enlistment(s) MTD.")

        if !events.isEmpty {
            lines.append("NEXT 7 DAYS")
            for e in events.sorted(by: { $0.start < $1.start }) {
                let loc = e.location.map { " @ \($0)" } ?? ""
                lines.append("- \(e.start.formatted(date: .abbreviated, time: .shortened)) \(e.title)\(loc)")
            }
        }

        if !red.isEmpty || !yellow.isEmpty {
            lines.append("RISKS")
            if !red.isEmpty { lines.append("- \(red.count) need touch today (RED).") }
            if !yellow.isEmpty { lines.append("- \(yellow.count) aging (YELLOW).") }
        }

        let issues = applicants.flatMap { $0.issues }.prefix(6)
        if !issues.isEmpty {
            lines.append("ISSUES")
            for i in issues { lines.append("- \(i)") }
        }
        return lines.joined(separator: "\n")
    }

    static func fill(template: String, applicant: Applicant?, settings: SettingsModel?) -> String {
        var out = template
        if let a = applicant {
            let first = a.fullName.split(separator: " ").first.map(String.init) ?? a.fullName
            out = out.replacingOccurrences(of: "{FirstName}", with: first)
            out = out.replacingOccurrences(of: "{FullName}", with: a.fullName)
            out = out.replacingOccurrences(of: "{Phone}", with: a.phone)
        }
        if let s = settings {
            out = out.replacingOccurrences(of: "{RecruiterName}", with: s.recruiterName)
            out = out.replacingOccurrences(of: "{Initials}", with: s.recruiterInitials)
            out = out.replacingOccurrences(of: "{RSID}", with: s.rsid)
        }
        return out
    }

    private static func normalizeWhitespace(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func dropFillers(_ s: String) -> String {
        var t = s
        let fillers = ["just", "really", "very", "kind of", "sort of", "basically", "actually", "like"]
        for f in fillers {
            t = t.replacingOccurrences(of: " \(f) ", with: " ", options: .caseInsensitive)
        }
        return t
    }
    private static func shortenPhrases(_ s: String) -> String {
        var t = s
        let map = [
            "at this time":"now",
            "as soon as possible":"ASAP",
            "in order to":"to",
            "let me know":"LMK"
        ]
        for (k,v) in map { t = t.replacingOccurrences(of: k, with: v, options: .caseInsensitive) }
        return t
    }
    private static func ensurePeriod(_ s: String) -> String {
        guard let ch = s.trimmingCharacters(in: .whitespacesAndNewlines).last else { return s }
        let end = ".?!".contains(ch) ? "" : "."
        return s + end
    }
    private static func addWarmth(_ s: String) -> String {
        var t = s
        if !t.lowercased().hasPrefix("hi") && !t.lowercased().hasPrefix("hey") {
            t = "Hi — " + t
        }
        t += " Thanks!"
        return t
    }
    private static func formalize(_ s: String) -> String {
        var t = s
        let map = ["hey":"hello", "hi":"hello", "thanks":"thank you", "gonna":"going to", "wanna":"want to", "ASAP":"as soon as possible"]
        for (k,v) in map {
            t = t.replacingOccurrences(of: "\\b\(k)\\b", with: v, options: [.regularExpression, .caseInsensitive])
        }
        return t
    }
    private static func bulletize(_ s: String) -> String {
        let parts = s.split(whereSeparator: { ".;".contains($0) })
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "• " + $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: "\n")
    }
}
