import Foundation

enum AISummarizer {
    static func summarizeNotes(_ notes: [String]) -> String {
        guard !notes.isEmpty else { return "No notes available." }
        let joined = notes.joined(separator: " ")
        let keyPoints = joined
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(5)
        return keyPoints.map { "• \($0)" }.joined(separator: "\n")
    }
}

