import Foundation

enum MedicalFlag: String, Codable {
    case asthma, colorBlind, depression, surgeryHistory
}

enum LegalDisqualifier: String, Codable {
    case felony, dui, domesticViolence, drugUse
}
