import Foundation

extension Store {
    private var rulesFileURL: URL {
        // Application Support/<bundle>/eligibility_rules.json
        (try? appSupportDir())!.appendingPathComponent("eligibility_rules.json")
    }

    func evaluateEligibility(for applicant: Applicant) -> RuleOutcome {
        let engine = loadRulesEngineOrDefaults()
        return engine.evaluate(applicant: applicant)
    }

    func writeStarterRulesToDisk() {
        do {
            let json = try JSONEncoder().encode(starterRulesEngine())
            try json.write(to: rulesFileURL, options: [.atomic])
            print("Starter rules written to \(rulesFileURL.lastPathComponent)")
        } catch {
            print("Write starter rules error: \(error)")
        }
    }

    private func loadRulesEngineOrDefaults() -> RulesEngine {
        if let data = try? Data(contentsOf: rulesFileURL),
           let eng = try? JSONDecoder().decode(RulesEngine.self, from: data) {
            return eng
        }
        return starterRulesEngine()
    }

    private func starterRulesEngine() -> RulesEngine {
        let rules: [Rule] = [
            Rule(name: "Underage",
                 predicate: .number(field: "age", op: .gte, value: 17),
                 failHeadline: .ineligible,
                 chip: "Under 17",
                 action: "Wait until 17"),

            Rule(name: "Missing Age",
                 predicate: .exists(field: "age", shouldExist: true),
                 failHeadline: .needsDocs,
                 chip: "Add DOB/Age",
                 action: "Get DOB"),

            Rule(name: "Legal Issues",
                 predicate: .not(.stringContains(field: "legalIssues", keywords: ["felony","probation","parole"])),
                 failHeadline: .ineligible,
                 chip: "Legal Hold",
                 action: "Refer to Guidance"),

            Rule(name: "Tattoo Waiver",
                 predicate: .or([
                    .bool(field: "hasTattoos", equals: false),
                    .not(.stringContains(field: "tattoosNotes", keywords: ["face","neck","hand"])),
                 ]),
                 failHeadline: .needsWaiver,
                 chip: "Tattoo Waiver?",
                 action: "Tattoo Waiver"),

            Rule(name: "Dependents",
                 predicate: .number(field: "dependents", op: .lte, value: 3),
                 failHeadline: .needsWaiver,
                 chip: "Dependents > 3",
                 action: "Dependency Waiver"),

            Rule(name: "Docs Stage Missing Docs",
                 predicate: .or([
                    .number(field: "dependents", op: .lt, value: 9999),
                    .not(.stringContains(field: "stage", keywords: ["Documents"])),
                 ]),
                 failHeadline: .needsDocs,
                 chip: "Collect IDs",
                 action: "SSN/BC/DL checklist"),

            Rule(name: "Education Missing",
                 predicate: .exists(field: "educationLevel", shouldExist: true),
                 failHeadline: .needsDocs,
                 chip: "Add Education",
                 action: "Transcripts/GED")
        ]
        return RulesEngine(rules: rules)
    }
}

private func appSupportDir() throws -> URL {
    let fm = FileManager.default
    let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let bundle = Bundle.main.bundleIdentifier ?? "ROPS"
    let dir = base.appendingPathComponent(bundle, isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
