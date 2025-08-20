// ApplicantFlags.swift
// Enumerations for applicant medical and legal screening notes.
// Shared between applicant models and rule evaluation.

import Foundation

enum MedicalFlag: String, Codable, CaseIterable, Identifiable {
    case asthma
    case heartCondition
    case mentalHealth
    case vision
    case hearing
    case orthopedic
    case other

    var id: String { rawValue }
}

enum LegalDisqualifier: String, Codable, CaseIterable, Identifiable {
    case felony
    case probation
    case parole
    case dui
    case other

    var id: String { rawValue }
}
