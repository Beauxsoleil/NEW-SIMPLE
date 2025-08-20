import Foundation

enum SimplePredicate: Codable {
    case age(min: Int, max: Int)
    case hasHighSchool
    case hasValidMedicalHistory(required: [MedicalFlag])
    case hasCleanLegalRecord(disqualifiers: [LegalDisqualifier])

    func evaluate(applicant: Applicant) -> Bool {
        switch self {
        case let .age(min, max):
            guard let age = applicant.age else { return false }
            return (min...max).contains(age)
        case .hasHighSchool:
            return applicant.educationLevel.lowercased().contains("hs") ||
                   applicant.educationLevel.lowercased().contains("high school")
        case let .hasValidMedicalHistory(required):
            return required.allSatisfy { !applicant.medicalFlags.contains($0) }
        case let .hasCleanLegalRecord(disqualifiers):
            return disqualifiers.allSatisfy { !applicant.legalHistory.contains($0) }
        }
    }
}

