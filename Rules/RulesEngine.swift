import Foundation

struct Rule: Codable {
    var name: String
    var predicate: RulePredicate
    var failHeadline: RuleHeadline
    var chip: String
    var action: String?
}

struct RulesEngine: Codable {
    var rules: [Rule]

    func evaluate(applicant: Applicant) -> RuleOutcome {
        var outcome = RuleOutcome(headline: .eligible, chips: [], actions: [])
        for rule in rules {
            if !rule.predicate.evaluate(applicant: applicant) {
                outcome.headline = rule.failHeadline
                outcome.chips.append(rule.chip)
                if let a = rule.action { outcome.actions.append(a) }
            }
        }
        return outcome
    }
}

