import Foundation

extension Store {
    func evaluateEligibility(for applicant: Applicant) -> EligibilityOutcome {
        RulesService.evaluate(applicant)
    }

    func writeStarterRulesToDisk() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("starter_rules.json")
            try RulesService.writeStarterRules(to: url)
            print("Starter rules written to: \(url.path)")
        } catch {
            print("Write rules error: \(error)")
        }
    }
}

