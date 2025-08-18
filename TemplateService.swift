import Foundation

enum TemplateService {
    static func defaultSnippets() -> [Snippet] {
        [
            .init(name: "First Contact", body: "Hey {FirstName}, this is {RecruiterName} with the Guard. Got a minute to chat about opportunities?"),
            .init(name: "Pre-MEPS Checklist", body: "Bring DL, SS card, BC, meds list. No caffeine. 8 hrs sleep."),
            .init(name: "RSP Predrill", body: "Uniform/Arrival time: {Time}. Location: {Location}. Questions? Reply here.")
        ]
    }

    static func eventNeeds(for type: EventType) -> String {
        switch type {
        case .schoolVisit: return "Needs: Table, banner, school approval, flyers, QR signup, swag."
        case .careerFair:  return "Needs: Table, power extension, banner, flyers, swag, lead forms."
        case .mepsTrip:    return "Needs: Packet verified, transport, lodging (if req’d), snack/water."
        case .appAppointment: return "Needs: DL, SSN, BC; transcripts; prior service docs (if any)."
        case .other:       return "Needs: As required."
        }
    }

    static func messageBody(for e: RecruitEvent) -> String {
        let date = e.start.formatted(date: .abbreviated, time: .shortened)
        let loc  = e.location.map { " at \($0)" } ?? ""
        return """
        \(e.title) — \(e.type.rawValue)\(loc)
        \(date)–\(e.end.formatted(date: .omitted, time: .shortened))
        \(eventNeeds(for: e.type))
        Related: \(e.relatedApplicantIDs.count) applicant(s)
        """
    }
}
