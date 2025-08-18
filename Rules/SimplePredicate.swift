import Foundation

enum SimplePredicate: Codable {
    case age(min: Int, max: Int)
    case hasHighSchool

    func evaluate(applicant: Applicant) -> Bool {
        switch self {
        case let .age(min, max):
            guard let age = applicant.age else { return false }
            return (min...max).contains(age)
        case .hasHighSchool:
            return applicant.educationLevel.lowercased().contains("hs") ||
                   applicant.educationLevel.lowercased().contains("high school")
        }
    }
}

