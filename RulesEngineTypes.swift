// RulesEngineTypes.swift
// Drop-in types + DSL for the Eligibility rules.
// Works with RulesEngine.swift and SettingsView button.

import Foundation

// MARK: - Eligibility presentation types

enum EligibilityHeadline: String, Codable {
    case eligible = "Eligible"
    case needsWaiver = "Needs Waiver"
    case ineligible = "Ineligible"
    case needsDocs = "Needs Documents"
}

struct EligibilityOutcome: Codable {
    var headline: EligibilityHeadline
    var chips: [String]
    var actions: [String]
}

// MARK: - Simple predicate DSL

enum NumOp: String, Codable { case lt, lte, gt, gte, eq, neq }

enum SimplePredicate: Codable {
    case and([SimplePredicate])
    case or([SimplePredicate])
    case not(SimplePredicate)
    case number(field: String, op: NumOp, value: Double)
    case bool(field: String, equals: Bool)
    case stringContains(field: String, keywords: [String])
    case exists(field: String, shouldExist: Bool)

    private enum CodingKeys: String, CodingKey { case type, field, op, value, values, equals, shouldExist, items }
    private enum Kind: String, Codable { case and, or, not, number, bool, stringContains, exists }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let k = try c.decode(Kind.self, forKey: .type)
        switch k {
        case .and: self = .and(try c.decode([SimplePredicate].self, forKey: .items))
        case .or:  self = .or(try c.decode([SimplePredicate].self, forKey: .items))
        case .not: self = .not(try c.decode(SimplePredicate.self, forKey: .items))
        case .number:
            self = .number(field: try c.decode(String.self, forKey: .field),
                           op: try c.decode(NumOp.self, forKey: .op),
                           value: try c.decode(Double.self, forKey: .value))
        case .bool:
            self = .bool(field: try c.decode(String.self, forKey: .field),
                         equals: try c.decode(Bool.self, forKey: .equals))
        case .stringContains:
            self = .stringContains(field: try c.decode(String.self, forKey: .field),
                                   keywords: try c.decode([String].self, forKey: .values))
        case .exists:
            self = .exists(field: try c.decode(String.self, forKey: .field),
                           shouldExist: try c.decode(Bool.self, forKey: .shouldExist))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .and(let arr):
            try c.encode(Kind.and, forKey: .type)
            try c.encode(arr, forKey: .items)
        case .or(let arr):
            try c.encode(Kind.or, forKey: .type)
            try c.encode(arr, forKey: .items)
        case .not(let p):
            try c.encode(Kind.not, forKey: .type)
            try c.encode(p, forKey: .items)
        case .number(let field, let op, let value):
            try c.encode(Kind.number, forKey: .type)
            try c.encode(field, forKey: .field)
            try c.encode(op, forKey: .op)
            try c.encode(value, forKey: .value)
        case .bool(let field, let equals):
            try c.encode(Kind.bool, forKey: .type)
            try c.encode(field, forKey: .field)
            try c.encode(equals, forKey: .equals)
        case .stringContains(let field, let keywords):
            try c.encode(Kind.stringContains, forKey: .type)
            try c.encode(field, forKey: .field)
            try c.encode(keywords, forKey: .values)
        case .exists(let field, let should):
            try c.encode(Kind.exists, forKey: .type)
            try c.encode(field, forKey: .field)
            try c.encode(should, forKey: .shouldExist)
        }
    }
}

// MARK: - Applicant field access

extension SimplePredicate {
    func evaluate(applicant: Applicant) -> Bool {
        switch self {
        case .and(let items): return items.allSatisfy { $0.evaluate(applicant: applicant) }
        case .or(let items):  return items.contains { $0.evaluate(applicant: applicant) }
        case .not(let p):     return !p.evaluate(applicant: applicant)
        case .number(let field, let op, let value):
            guard let num = Self.numberValue(field: field, applicant: applicant) else { return false }
            switch op {
            case .lt:  return num < value
            case .lte: return num <= value
            case .gt:  return num > value
            case .gte: return num >= value
            case .eq:  return num == value
            case .neq: return num != value
            }
        case .bool(let field, let equals):
            guard let b = Self.boolValue(field: field, applicant: applicant) else { return false }
            return b == equals
        case .stringContains(let field, let keywords):
            let hay = (Self.stringValue(field: field, applicant: applicant) ?? "").lowercased()
            return keywords.map { $0.lowercased() }.contains { hay.contains($0) }
        case .exists(let field, let should):
            let any = Self.anyValue(field: field, applicant: applicant)
            let present: Bool
            switch any {
            case .none: present = false
            case .some(let val as String):
                present = !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default:
                present = true
            }
            return should ? present : !present
        }
    }

    private static func anyValue(field: String, applicant: Applicant) -> Any? {
        switch field {
        case "age": return applicant.age
        case "priorService": return applicant.priorService
        case "legalIssues": return applicant.legalIssues
        case "physicalHealth": return applicant.physicalHealth
        case "educationLevel": return applicant.educationLevel
        case "hasTattoos": return applicant.hasTattoos
        case "tattoosNotes": return applicant.tattoosNotes
        case "dependents": return applicant.dependents
        case "heightInInches": return applicant.heightInInches
        case "weightInPounds": return applicant.weightInPounds
        case "waistInInches": return applicant.waistInInches
        case "stage": return applicant.stage.rawValue
        default: return nil
        }
    }

    private static func numberValue(field: String, applicant: Applicant) -> Double? {
        if let v = anyValue(field: field, applicant: applicant) as? Int { return Double(v) }
        if let v = anyValue(field: field, applicant: applicant) as? Double { return v }
        return nil
    }

    private static func boolValue(field: String, applicant: Applicant) -> Bool? {
        anyValue(field: field, applicant: applicant) as? Bool
    }

    private static func stringValue(field: String, applicant: Applicant) -> String? {
        anyValue(field: field, applicant: applicant) as? String
    }
}
