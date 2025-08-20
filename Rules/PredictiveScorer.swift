import Foundation

struct PredictiveScorer {
    func score(applicant: Applicant) -> Double {
        var score = 0.0
        if let age = applicant.age, (17...24).contains(age) { score += 0.4 }
        if applicant.educationLevel.lowercased().contains("hs") { score += 0.3 }
        if applicant.interestLevel > 8 { score += 0.3 }
        return min(score, 1.0)
    }
}

