import Foundation

enum EligibilityHeadline: String, Codable {
    case eligible = "Eligible"
    case needsWaiver = "Needs Waiver"
    case notEligible = "Not Eligible"
}

struct EligibilityOutcome: Codable {
    var headline: EligibilityHeadline
    var chips: [String]
    var actions: [String]
}

