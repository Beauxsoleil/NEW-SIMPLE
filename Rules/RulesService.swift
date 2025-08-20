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

        let medicalRule = Rule(
            name: "Medical History",
            predicate: .hasValidMedicalHistory(required: [.asthma, .colorBlind]),
            failHeadline: .needsWaiver,
            chip: "Medical",
            action: "Submit medical waiver"
        )

        let legalRule = Rule(
            name: "Legal Record",
            predicate: .hasCleanLegalRecord(disqualifiers: [.felony, .dui]),
            failHeadline: .notEligible,
            chip: "Legal",
            action: "Review with legal"
        )

        return RulesEngine(rules: [ageRule, medicalRule, legalRule])
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

