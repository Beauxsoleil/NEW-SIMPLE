import Foundation

struct Entity {
    enum Kind {
        case person
        case date
        case location
        case org
        case idNumber
        case phone
    }
    let kind: Kind
    let text: String
    let range: Range<String.Index>
}

enum NERService {
    static func extract(from text: String) -> [Entity] {
        var entities: [Entity] = []
        let nsRange = NSRange(text.startIndex..., in: text)

        let dateRegex = try! NSRegularExpression(pattern: "\\b\\d{4}-\\d{2}-\\d{2}\\b")
        dateRegex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            if let match = match, let range = Range(match.range, in: text) {
                entities.append(Entity(kind: .date, text: String(text[range]), range: range))
            }
        }

        let phoneRegex = try! NSRegularExpression(pattern: "\\b(?:\\d{3}[-\\.\\s]?){2}\\d{4}\\b")
        phoneRegex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            if let match = match, let range = Range(match.range, in: text) {
                entities.append(Entity(kind: .phone, text: String(text[range]), range: range))
            }
        }

        return entities
    }
}

