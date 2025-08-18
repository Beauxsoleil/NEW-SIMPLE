import Foundation

enum RulesService {
    static func defaultEngine() -> RulesEngine {
        let ageRule = Rule(
            name: "Age",
            predicate: .age(min: 17, max: 34),
            failHeadline: .needsWaiver,
            chip: "Age",
            action: "Age waiver"
        )
        return RulesEngine(rules: [ageRule])
    }

    static func evaluate(_ applicant: Applicant) -> EligibilityOutcome {
        defaultEngine().evaluate(applicant: applicant)
    }

    static func writeStarterRules(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(defaultEngine())
        try data.write(to: url, options: .atomic)
    }
}

